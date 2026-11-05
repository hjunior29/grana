defmodule Grana.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Grana.Accounts` context.

  Usuários são inseridos direto pelo `Repo`: em produção só existe um caminho de
  criação (`Accounts.register_owner/1`, que recusa um segundo usuário), mas os
  testes de isolamento entre usuários precisam de vários.
  """

  import Ecto.Query

  alias Grana.Accounts
  alias Grana.Accounts.{Scope, User}

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      name: "Dono de Teste",
      password: valid_user_password()
    })
  end

  def user_fixture(attrs \\ %{}) do
    attrs = valid_user_attributes(attrs)
    now = DateTime.utc_now(:second)

    %User{
      email: attrs.email,
      name: attrs.name,
      hashed_password: Bcrypt.hash_pwd_salt(attrs.password),
      confirmed_at: now,
      onboarded_at: now
    }
    |> Grana.Repo.insert!()
  end

  def unconfirmed_user_fixture(attrs \\ %{}) do
    user = user_fixture(attrs)
    user |> Ecto.Changeset.change(confirmed_at: nil, hashed_password: nil) |> Grana.Repo.update!()
  end

  @doc "Liga o SMTP (e, com ele, o 2FA) gravando direto no usuário; envia pelo adapter Test."
  def smtp_fixture(user, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        smtp_host: "smtp.example.com",
        smtp_port: 587,
        smtp_username: "grana",
        smtp_password: "segredo",
        smtp_tls: "always",
        smtp_from_name: "Grana",
        smtp_from_address: "grana@example.com"
      })

    user |> Ecto.Changeset.change(attrs) |> Grana.Repo.update!()
  end

  @doc """
  Cadastra um provedor de IA (Gemini por padrão) para o usuário e o define como padrão,
  gravando direto no banco (sem chamar a API). Devolve o usuário atualizado.
  """
  def ai_fixture(user, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{kind: "gemini", name: "Google Gemini", api_key: "fake-key"})
    model = Map.get(attrs, :model, "gemini-test-model")

    provider =
      %Grana.AI.ProviderConfig{user_id: user.id}
      |> Map.merge(Map.take(attrs, [:kind, :name, :base_url, :api_key]))
      |> Grana.Repo.insert!()

    {:ok, user} = Grana.AI.set_default(user, Grana.AI.ProviderConfig.ref(provider), model)
    user
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def set_password(user) do
    {:ok, {user, _expired_tokens}} =
      Accounts.reset_user_password(user, %{password: valid_user_password()})

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Grana.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Grana.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
