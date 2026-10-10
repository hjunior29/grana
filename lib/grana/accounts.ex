defmodule Grana.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Grana.Repo

  alias Grana.Accounts.{User, UserToken, UserNotifier}

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

  def complete_onboarding(%User{onboarded_at: nil} = user) do
    user |> User.onboarded_changeset() |> Repo.update()
  end

  def complete_onboarding(%User{} = user), do: {:ok, user}

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
  Deletes a user and all associated data.

  All `users_tokens` are removed by FK cascade (`on_delete: :delete_all`), which
  invalidates the session and remember-me cookies server-side.
  """
  def delete_user(user) do
    Repo.delete(user)
  end

  @doc """
  Lists a user's active session tokens. Used to disconnect any live LiveView
  sessions when the account is deleted.
  """
  def list_user_session_tokens(user) do
    Repo.all(from(t in UserToken, where: t.user_id == ^user.id and t.context == "session"))
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
