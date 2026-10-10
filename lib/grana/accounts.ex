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

  def update_user_preferences(%User{} = user, attrs) do
    user |> User.preferences_changeset(attrs) |> Repo.update()
  end

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

  @doc """
  Configuração efetiva de SMTP: o ambiente (`SMTP_HOST` etc.) tem precedência
  sobre a salva pela tela. `nil` quando não há SMTP; nesse caso o 2FA fica desligado.
  """
  def smtp_config do
    env_smtp_config() || saved_smtp_config(get_owner())
  end

  def smtp_source do
    cond do
      env_smtp_config() -> :env
      saved_smtp_config(get_owner()) -> :database
      true -> nil
    end
  end

  def smtp_configured?, do: smtp_config() != nil

  @doc "Configuração de SMTP de um usuário (ainda não persistido), no formato de `smtp_config/0`."
  def smtp_config_for(%User{} = user), do: saved_smtp_config(user)

  defp env_smtp_config do
    case Application.get_env(:grana, :smtp_env) do
      %{host: host} = config when is_binary(host) and host != "" -> config
      _ -> nil
    end
  end

  defp saved_smtp_config(%User{smtp_host: host} = user) when is_binary(host) and host != "" do
    %{
      host: host,
      port: user.smtp_port || 587,
      username: user.smtp_username,
      password: user.smtp_password,
      tls: String.to_existing_atom(user.smtp_tls || "always"),
      from_name: user.smtp_from_name || "Grana",
      from_address: user.smtp_from_address
    }
  end

  defp saved_smtp_config(_), do: nil

  @doc "Changeset do formulário de SMTP. A senha salva nunca volta para a tela."
  def change_smtp_settings(user, attrs \\ %{}) do
    User.smtp_settings_changeset(%{user | smtp_password: nil}, attrs)
  end

  @doc """
  Salva o SMTP depois de enviar um email de teste para o dono: ligar o SMTP liga o
  2FA, então uma configuração que não envia não pode ser gravada (ficaria trancado
  fora da própria conta).
  """
  def save_smtp_settings(%User{} = user, attrs) do
    changeset = User.smtp_settings_changeset(user, attrs)

    with {:ok, candidate} <- Ecto.Changeset.apply_action(changeset, :update),
         {:ok, _email} <- UserNotifier.deliver_smtp_test(candidate, saved_smtp_config(candidate)) do
      Repo.update(changeset)
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

  ## AI Settings

  @doc "Changeset do formulário de IA. A chave salva nunca volta para a tela."
  def change_user_ai_settings(user, attrs \\ %{}) do
    User.ai_settings_changeset(%{user | ai_api_key: nil}, attrs)
  end

  def update_user_ai_settings(user, attrs) do
    user
    |> User.ai_settings_changeset(attrs)
    |> Repo.update()
  end

  def remove_user_ai_api_key(user) do
    user
    |> Ecto.Changeset.change(ai_api_key: nil)
    |> Repo.update()
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

  @doc "Chave do Gemini definida no ambiente (GEMINI_API_KEY), se houver."
  def env_ai_api_key do
    case Application.get_env(:grana, :gemini_api_key) do
      key when is_binary(key) and key != "" -> key
      _ -> nil
    end
  end

  # A chave do ambiente (.env) tem prioridade sobre a salva pela tela.
  def get_user_ai_config(user_id) do
    user = get_user!(user_id)
    api_key = env_ai_api_key() || user.ai_api_key

    case api_key do
      nil ->
        {:error, :no_api_key}

      key ->
        {:ok,
         %{
           provider: user.ai_provider || "gemini",
           model: user.ai_model || "gemini-2.0-flash",
           api_key: key
         }}
    end
  end
end
