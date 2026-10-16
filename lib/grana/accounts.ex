defmodule Grana.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Grana.Repo

  alias Grana.Accounts.{User, UserNotifier, UserToken}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  def get_user(id), do: Repo.get(User, id)

  ## Setup (dono da instância)

  @setup_cache_key {__MODULE__, :setup_required}

  @doc """
  Verdadeiro enquanto a instância não tem dono. Consultado em toda requisição,
  então o resultado fica em `:persistent_term` (ver `invalidate_setup_cache/0`).
  """
  def setup_required? do
    if Application.get_env(:grana, :cache_setup_state, true) do
      case :persistent_term.get(@setup_cache_key, :unknown) do
        :unknown ->
          required? = not Repo.exists?(User)
          :persistent_term.put(@setup_cache_key, required?)
          required?

        required? ->
          required?
      end
    else
      not Repo.exists?(User)
    end
  end

  @doc "Descarta o resultado em cache de `setup_required?/0` (criar dono, restaurar, apagar tudo)."
  def invalidate_setup_cache do
    :persistent_term.erase(@setup_cache_key)
    :ok
  end

  @doc """
  Cria o único usuário da instância. Falha com `{:error, :already_set_up}` se já
  existir um; é o único caminho de criação de usuário.
  """
  def register_owner(attrs) do
    result =
      Repo.transact(fn ->
        if Repo.exists?(User) do
          {:error, :already_set_up}
        else
          %User{} |> User.owner_changeset(attrs) |> Repo.insert()
        end
      end)

    with {:ok, user} <- result do
      invalidate_setup_cache()
      Grana.Setup.clear_code()
      {:ok, user}
    end
  end

  def change_owner(attrs \\ %{}, opts \\ []), do: User.owner_changeset(%User{}, attrs, opts)

  @preference_fields [:theme, :visual_style, :hide_values, :hide_names]

  @doc """
  Grava tema, estilo visual e privacidade (ocultar valores e nomes) e avisa as telas do
  usuário abertas (outras abas e aparelhos), que aplicam as preferências sem recarregar.
  """
  def update_user_preferences(%User{} = user, attrs) do
    with {:ok, user} <- user |> User.preferences_changeset(attrs) |> Repo.update() do
      Phoenix.PubSub.broadcast(
        Grana.PubSub,
        preferences_topic(user.id),
        {:preferences_updated, Map.take(user, @preference_fields)}
      )

      {:ok, user}
    end
  end

  @doc "Recebe `{:preferences_updated, campos}` quando o usuário muda uma preferência."
  def subscribe_preferences(user_id) do
    Phoenix.PubSub.subscribe(Grana.PubSub, preferences_topic(user_id))
  end

  defp preferences_topic(user_id), do: "user_preferences:#{user_id}"

  def complete_onboarding(%User{onboarded_at: nil} = user) do
    user |> User.onboarded_changeset() |> Repo.update()
  end

  def complete_onboarding(%User{} = user), do: {:ok, user}

  @doc """
  URL base usada nos links dos emails, que são gerados sem requisição:
  `PUBLIC_URL` > a origem capturada no setup > localhost na porta configurada
  (não usa o Endpoint, que não está de pé nos comandos de `bin/grana eval`).
  """
  def public_base_url(user \\ nil) do
    Application.get_env(:grana, :public_url) || (user && user.base_url) || local_url()
  end

  defp local_url do
    port = Application.get_env(:grana, GranaWeb.Endpoint)[:http][:port] || 4000
    "http://localhost:#{port}"
  end

  @doc "O único usuário da instância (ou `nil` enquanto o setup não foi feito)."
  def get_owner, do: Repo.one(from u in User, order_by: [asc: u.id], limit: 1)

  ## SMTP

  # Campo do SMTP => coluna em `users`.
  @smtp_columns [
    host: :smtp_host,
    port: :smtp_port,
    username: :smtp_username,
    password: :smtp_password,
    tls: :smtp_tls,
    from_name: :smtp_from_name,
    from_address: :smtp_from_address
  ]

  @doc """
  Configuração efetiva de SMTP, campo a campo: cada variável do ambiente (`SMTP_HOST`,
  `SMTP_PASSWORD`...) vence o campo salvo pela tela, e o que nenhum dos dois define usa o
  padrão. `nil` sem servidor (`host`); nesse caso o 2FA fica desligado.
  """
  def smtp_config, do: smtp_config_for(get_owner())

  @doc "Como `smtp_config/0`, com os campos salvos de `user` (inclusive ainda não gravados)."
  def smtp_config_for(user) do
    fields = Map.merge(saved_smtp_fields(user), smtp_env())

    if fields[:host] do
      username = fields[:username]

      Map.merge(
        %{
          port: 587,
          username: nil,
          password: nil,
          tls: :always,
          from_name: "Grana",
          from_address:
            if(username && String.contains?(username, "@"),
              do: username,
              else: "noreply@example.com"
            )
        },
        fields
      )
    end
  end

  @doc """
  De onde vem o SMTP: `:env` (só do ambiente), `:database` (só da tela), `:mixed` (o
  ambiente define uma parte e a tela, o resto) ou `nil` (sem servidor).
  """
  def smtp_source do
    owner = get_owner()
    saved = Map.drop(saved_smtp_fields(owner), smtp_env_fields())

    cond do
      smtp_config_for(owner) == nil -> nil
      saved == %{} -> :env
      smtp_env() == %{} -> :database
      true -> :mixed
    end
  end

  @doc "Campos do SMTP definidos no ambiente (`:host`, `:password`...), que a tela não edita."
  def smtp_env_fields, do: Map.keys(smtp_env())

  @doc "Se o ambiente define todos os campos do SMTP (não sobra nada para a tela)."
  def smtp_env_complete?, do: map_size(smtp_env()) == length(@smtp_columns)

  def smtp_configured?, do: smtp_config() != nil

  defp smtp_env, do: Application.get_env(:grana, :smtp_env, %{})

  defp saved_smtp_fields(nil), do: %{}

  defp saved_smtp_fields(%User{} = user) do
    @smtp_columns
    |> Enum.map(fn {field, column} -> {field, Map.fetch!(user, column)} end)
    |> Enum.reject(fn {_field, value} -> value in [nil, ""] end)
    |> Map.new(fn
      {:tls, value} -> {:tls, String.to_existing_atom(value)}
      pair -> pair
    end)
  end

  @doc """
  Changeset do formulário de SMTP. A senha salva nunca volta para a tela, e os campos que
  vêm do ambiente ficam de fora.
  """
  def change_smtp_settings(user, attrs \\ %{}) do
    User.smtp_settings_changeset(%{user | smtp_password: nil}, attrs, smtp_env_columns())
  end

  defp smtp_env_columns, do: Enum.map(smtp_env_fields(), &Keyword.fetch!(@smtp_columns, &1))

  @doc """
  Salva o SMTP depois de enviar um email de teste para o dono: ligar o SMTP liga o
  2FA, então uma configuração que não envia não pode ser gravada (ficaria trancado
  fora da própria conta).
  """
  def save_smtp_settings(%User{} = user, attrs) do
    with {:ok, changeset} <- smtp_test(user, attrs) do
      Repo.update(changeset)
    end
  end

  @doc "Só envia o email de teste com os dados informados, sem gravar nada."
  def send_smtp_test(%User{} = user, attrs) do
    with {:ok, _changeset} <- smtp_test(user, attrs), do: :ok
  end

  defp smtp_test(user, attrs) do
    changeset = User.smtp_settings_changeset(user, attrs, smtp_env_columns())

    with {:ok, candidate} <- Ecto.Changeset.apply_action(changeset, :update),
         {:ok, _email} <- UserNotifier.deliver_smtp_test(candidate, smtp_config_for(candidate)) do
      {:ok, changeset}
    else
      {:error, %Ecto.Changeset{}} = error ->
        error

      {:error, reason} ->
        {:error,
         changeset
         |> Ecto.Changeset.add_error(
           :smtp_host,
           "não foi possível enviar o email de teste (#{smtp_error(reason)}); nada foi salvo"
         )
         |> Map.put(:action, :update)}
    end
  end

  defp smtp_error(reason), do: reason |> inspect() |> String.slice(0, 160)

  def remove_smtp_settings(%User{} = user) do
    user
    |> Ecto.Changeset.change(
      smtp_host: nil,
      smtp_port: nil,
      smtp_username: nil,
      smtp_password: nil,
      smtp_tls: nil,
      smtp_from_name: nil,
      smtp_from_address: nil
    )
    |> Repo.update()
  end

  ## Two-factor (código por email)

  @two_factor_cooldown_seconds 60
  @two_factor_max_attempts 5

  @doc """
  Gera e envia um código de 6 dígitos (um ativo por vez, guardado só como hash).
  `{:error, :cooldown}` se um código foi enviado há menos de 60 segundos.
  """
  def deliver_two_factor_code(%User{} = user) do
    case active_two_factor_token(user) do
      %UserToken{inserted_at: sent_at} = token ->
        elapsed = DateTime.diff(DateTime.utc_now(:second), sent_at)

        if elapsed < @two_factor_cooldown_seconds do
          {:error, :cooldown}
        else
          Repo.delete(token)
          send_two_factor_code(user)
        end

      nil ->
        send_two_factor_code(user)
    end
  end

  defp send_two_factor_code(user) do
    code = random_code()
    token = Repo.insert!(UserToken.build_two_factor_token(user, code))

    case UserNotifier.deliver_two_factor_code(user, code) do
      {:ok, _email} = ok ->
        ok

      {:error, _reason} = error ->
        Repo.delete(token)
        error
    end
  end

  defp random_code do
    <<n::32>> = :crypto.strong_rand_bytes(4)
    n |> rem(1_000_000) |> Integer.to_string() |> String.pad_leading(6, "0")
  end

  defp active_two_factor_token(user) do
    Repo.one(from t in UserToken, where: t.user_id == ^user.id and t.context == "2fa")
  end

  @doc """
  Confere o código. O código vale por 10 minutos e 5 tentativas; qualquer
  desfecho final (certo, expirado, tentativas esgotadas) o consome.
  """
  def verify_two_factor_code(%User{} = user, code) when is_binary(code) do
    with %UserToken{} = token <- active_two_factor_token(user),
         :ok <- two_factor_not_expired(token) do
      check_two_factor_code(token, String.trim(code))
    else
      nil -> {:error, :expired}
      {:error, _} = error -> error
    end
  end

  defp two_factor_not_expired(token) do
    age = DateTime.diff(DateTime.utc_now(:second), token.inserted_at)

    if age > UserToken.two_factor_validity_in_minutes() * 60 do
      Repo.delete(token)
      {:error, :expired}
    else
      :ok
    end
  end

  defp check_two_factor_code(token, code) do
    if Plug.Crypto.secure_compare(token.token, UserToken.hash_two_factor_code(code)) do
      Repo.delete(token)
      :ok
    else
      attempts = token.attempts + 1

      if attempts >= @two_factor_max_attempts do
        Repo.delete(token)
        {:error, :too_many_attempts}
      else
        token |> Ecto.Changeset.change(attempts: attempts) |> Repo.update!()
        {:error, :invalid}
      end
    end
  end

  ## Recuperação de senha

  @doc "Cria o token de recuperação (invalidando os anteriores) e devolve o valor para o link."
  def build_reset_password_token(%User{} = user) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")

    Repo.transact(fn ->
      Repo.delete_all(
        from(t in UserToken, where: t.user_id == ^user.id and t.context == "reset_password")
      )

      Repo.insert!(user_token)
      {:ok, encoded_token}
    end)
  end

  def deliver_reset_password_instructions(%User{} = user, url_fun) when is_function(url_fun, 1) do
    {:ok, encoded_token} = build_reset_password_token(user)
    UserNotifier.deliver_reset_password_instructions(user, url_fun.(encoded_token))
  end

  def get_user_by_reset_password_token(token) when is_binary(token) do
    with {:ok, query} <- UserToken.verify_reset_password_token_query(token) do
      Repo.one(query)
    else
      _ -> nil
    end
  end

  @doc "Define a nova senha e derruba todas as sessões (os tokens voltam para desconectar os sockets)."
  def reset_user_password(%User{} = user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  @doc "Troca o email direto, sem confirmação por link (quando não há SMTP)."
  def update_user_email_directly(%User{} = user, attrs) do
    user |> User.email_changeset(attrs) |> Repo.update()
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Grana.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Grana.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end

  ## Identity (nome/CPF do titular)

  def change_user_identity(user, attrs \\ %{}) do
    User.identity_changeset(user, attrs)
  end

  def update_user_identity(user, attrs) do
    user
    |> User.identity_changeset(attrs)
    |> Repo.update()
  end

  # Provedor e modelo padrão da IA (ver Grana.AI): ambiente e cadastrados.
end
