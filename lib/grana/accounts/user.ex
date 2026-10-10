defmodule Grana.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true

    field :ai_provider, :string, default: "gemini"
    field :ai_model, :string, default: "gemini-2.0-flash"
    field :ai_api_key, Grana.Encrypted.Binary, redact: true

    # Identidade do titular, para reconhecer transferências entre contas próprias.
    field :name, :string
    field :cpf, Grana.Encrypted.Binary, redact: true

    # Open Finance (Pluggy): credenciais da aplicação do usuário e o segredo que
    # autentica os webhooks. Cifrados; nunca são devolvidos para o navegador.
    field :pluggy_client_id, :string
    field :pluggy_client_secret, Grana.Encrypted.Binary, redact: true
    field :pluggy_webhook_secret, Grana.Encrypted.Binary, redact: true

    # SMTP salvo pela tela (a senha é cifrada e só de escrita). O ambiente tem
    # precedência; ver Accounts.smtp_config/0.
    field :smtp_host, :string
    field :smtp_port, :integer
    field :smtp_username, :string
    field :smtp_password, Grana.Encrypted.Binary, redact: true
    field :smtp_tls, :string
    field :smtp_from_name, :string
    field :smtp_from_address, :string

    field :inactivity_reminded_at, :utc_datetime

    # Preenchido ao concluir (ou pular) o onboarding; base_url é a origem usada
    # nos links enviados por email quando não há PUBLIC_URL.
    field :onboarded_at, :utc_datetime
    field :base_url, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset do dono da instância, criado pelo assistente de setup: já nasce
  confirmado e com senha (confirmação obrigatória).
  """
  def owner_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :name, :password, :base_url])
    |> validate_email(validate_unique: false)
    |> validate_required([:name])
    |> validate_length(:name, max: 160)
    |> validate_confirmation(:password, required: true, message: "does not match password")
    |> validate_password(opts)
    |> put_change(:confirmed_at, DateTime.utc_now(:second))
  end

  def onboarded_changeset(user), do: change(user, onboarded_at: DateTime.utc_now(:second))

  @doc """
  A user changeset for registering or changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Grana.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the password.

  It is important to validate the length of the password, as long passwords may
  be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    # Examples of additional password validation:
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:password, max: 72, count: :bytes)
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%Grana.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  def ai_settings_changeset(user, attrs \\ %{}) do
    user
    |> cast(attrs, [:ai_provider, :ai_model, :ai_api_key])
    |> keep_secret_when_blank(:ai_api_key)
    |> validate_inclusion(:ai_provider, ["gemini"])
    |> validate_inclusion(:ai_model, ["gemini-2.0-flash", "gemini-2.5-flash", "gemini-2.5-pro"])
  end

  # Campos de segredo são só de escrita: a tela nunca recebe o valor salvo, então
  # deixar em branco significa "manter" (remover é uma ação explícita).
  defp keep_secret_when_blank(changeset, field) do
    if get_change(changeset, field, :unchanged) == nil,
      do: delete_change(changeset, field),
      else: changeset
  end

  @doc """
  Changeset das credenciais da Pluggy. Os dois campos são exigidos juntos: trocar
  o Client ID significa outra aplicação, com outro secret.
  """
  def pluggy_credentials_changeset(user, attrs \\ %{}) do
    user
    |> cast(attrs, [:pluggy_client_id, :pluggy_client_secret])
    |> update_change(:pluggy_client_id, &trim/1)
    |> update_change(:pluggy_client_secret, &trim/1)
    |> validate_required([:pluggy_client_id, :pluggy_client_secret])
    |> validate_format(
      :pluggy_client_id,
      ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
      message: "deve ser o Client ID (UUID) da aplicação"
    )
  end

  @smtp_tls_modes ~w(always if_available never)

  @doc """
  Changeset do SMTP. A senha é só de escrita: em branco significa "manter".
  """
  def smtp_settings_changeset(user, attrs \\ %{}) do
    user
    |> cast(attrs, [
      :smtp_host,
      :smtp_port,
      :smtp_username,
      :smtp_password,
      :smtp_tls,
      :smtp_from_name,
      :smtp_from_address
    ])
    |> keep_secret_when_blank(:smtp_password)
    |> update_change(:smtp_host, &trim/1)
    |> update_change(:smtp_username, &trim/1)
    |> update_change(:smtp_from_address, &trim/1)
    |> validate_required([:smtp_host, :smtp_port, :smtp_tls, :smtp_from_address])
    |> validate_number(:smtp_port, greater_than: 0, less_than: 65_536)
    |> validate_inclusion(:smtp_tls, @smtp_tls_modes)
    |> validate_format(:smtp_from_address, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "deve ser um email válido"
    )
    |> validate_length(:smtp_from_name, max: 80)
  end

  @doc """
  Changeset da identidade do titular (nome + CPF). O CPF é normalizado para só
  dígitos antes de ser criptografado, e exige 11 dígitos quando informado.
  """
  def identity_changeset(user, attrs \\ %{}) do
    user
    |> cast(attrs, [:name, :cpf])
    |> update_change(:cpf, &normalize_cpf/1)
    |> validate_length(:name, max: 160)
    |> validate_format(:cpf, ~r/^\d{11}$/, message: "deve ter 11 dígitos")
  end

  defp trim(nil), do: nil
  defp trim(value), do: String.trim(value)

  defp normalize_cpf(nil), do: nil
  defp normalize_cpf(""), do: nil
  defp normalize_cpf(cpf), do: String.replace(cpf, ~r/\D/, "")
end
