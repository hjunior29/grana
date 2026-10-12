defmodule Grana.AccountsSmtpTest do
  use Grana.DataCase, async: false
  use Mimic

  import Grana.AccountsFixtures
  import Swoosh.TestAssertions

  alias Grana.Accounts

  @valid %{
    "smtp_host" => "smtp.exemplo.com",
    "smtp_port" => "587",
    "smtp_username" => "grana",
    "smtp_password" => "segredo",
    "smtp_tls" => "always",
    "smtp_from_name" => "Grana",
    "smtp_from_address" => "grana@exemplo.com"
  }

  describe "configuração efetiva (env > banco > nil)" do
    test "sem nada, não há SMTP" do
      user_fixture()
      assert Accounts.smtp_config() == nil
      assert Accounts.smtp_source() == nil
      refute Accounts.smtp_configured?()
    end

    test "o banco vale quando não há ambiente" do
      user_fixture() |> smtp_fixture()

      assert %{host: "smtp.example.com", port: 587, tls: :always} = Accounts.smtp_config()
      assert Accounts.smtp_source() == :database
      assert Accounts.smtp_configured?()
    end

    test "cada campo do ambiente vence o do banco; o resto vem do banco" do
      user_fixture() |> smtp_fixture()
      put_smtp_env(%{host: "env.example.com", port: 25, tls: :never})

      assert %{host: "env.example.com", port: 25, tls: :never, username: "grana"} =
               Accounts.smtp_config()

      assert Accounts.smtp_source() == :mixed
      assert Enum.sort(Accounts.smtp_env_fields()) == [:host, :port, :tls]
      refute Accounts.smtp_env_complete?()
    end

    test "o banco completa o servidor que falta no ambiente" do
      user_fixture() |> smtp_fixture(%{smtp_port: nil, smtp_password: nil})
      put_smtp_env(%{port: 465, password: "do-env"})

      assert %{host: "smtp.example.com", port: 465, password: "do-env"} = Accounts.smtp_config()
      assert Accounts.smtp_source() == :mixed
    end

    test "sem servidor em lugar nenhum não há SMTP, mesmo com outros campos no ambiente" do
      user_fixture()
      put_smtp_env(%{port: 465, username: "eu@exemplo.com", password: "x"})

      assert Accounts.smtp_config() == nil
      assert Accounts.smtp_source() == nil
    end

    test "só o ambiente: o que falta usa o padrão" do
      user_fixture()
      put_smtp_env(%{host: "env.example.com", username: "eu@exemplo.com"})

      assert %{port: 587, tls: :always, from_name: "Grana", from_address: "eu@exemplo.com"} =
               Accounts.smtp_config()

      assert Accounts.smtp_source() == :env
    end

    test "o ambiente completo ignora o que foi salvo" do
      user_fixture() |> smtp_fixture()

      put_smtp_env(%{
        host: "env.example.com",
        port: 25,
        username: "env",
        password: "env",
        tls: :never,
        from_name: "Env",
        from_address: "env@example.com"
      })

      assert %{host: "env.example.com", username: "env"} = Accounts.smtp_config()
      assert Accounts.smtp_source() == :env
      assert Accounts.smtp_env_complete?()
    end
  end

  describe "save_smtp_settings/2 com parte no ambiente" do
    test "grava só o que não vem do ambiente e exige só isso" do
      user = user_fixture()

      put_smtp_env(%{
        port: 587,
        username: "env-user",
        password: "env-secret",
        tls: :always,
        from_address: "env@example.com"
      })

      assert {:error, changeset} = Accounts.save_smtp_settings(user, %{})
      assert Map.keys(errors_on(changeset)) == [:smtp_host]

      assert {:ok, saved} =
               Accounts.save_smtp_settings(user, %{
                 "smtp_host" => "smtp.exemplo.com",
                 "smtp_username" => "ignorado"
               })

      assert saved.smtp_host == "smtp.exemplo.com"
      assert saved.smtp_username == nil
      assert %{host: "smtp.exemplo.com", username: "env-user"} = Accounts.smtp_config()
      assert Accounts.smtp_source() == :mixed
    end
  end

  defp put_smtp_env(env) do
    Application.put_env(:grana, :smtp_env, env)
    on_exit(fn -> Application.delete_env(:grana, :smtp_env) end)
  end

  describe "save_smtp_settings/2" do
    setup do
      %{user: user_fixture()}
    end

    test "envia o teste e grava, com a senha cifrada no banco", %{user: user} do
      assert {:ok, saved} = Accounts.save_smtp_settings(user, @valid)

      assert_email_sent(to: {nil, user.email}, subject: "Seu email no Grana está funcionando")
      assert saved.smtp_host == "smtp.exemplo.com"

      %{rows: [[raw]]} = Repo.query!("SELECT smtp_password FROM users WHERE id = ?", [user.id])
      refute raw =~ "segredo"
      assert Accounts.get_user!(user.id).smtp_password == "segredo"
    end

    test "não grava quando o teste falha", %{user: user} do
      expect(Grana.Mailer, :send_email, fn _email, _config -> {:error, :econnrefused} end)

      assert {:error, changeset} = Accounts.save_smtp_settings(user, @valid)
      assert %{smtp_host: [message]} = errors_on(changeset)
      assert message =~ "nada foi salvo"
      refute Accounts.smtp_configured?()
    end

    test "valida os campos", %{user: user} do
      assert {:error, changeset} =
               Accounts.save_smtp_settings(user, %{
                 @valid
                 | "smtp_port" => "99999",
                   "smtp_tls" => "x",
                   "smtp_from_address" => "invalido"
               })

      assert %{smtp_port: _, smtp_tls: _, smtp_from_address: _} = errors_on(changeset)
      refute_email_sent()
    end

    test "senha em branco mantém a salva", %{user: user} do
      {:ok, saved} = Accounts.save_smtp_settings(user, @valid)
      {:ok, _} = Accounts.save_smtp_settings(saved, %{@valid | "smtp_password" => ""})

      assert Accounts.get_user!(user.id).smtp_password == "segredo"
    end

    test "remove_smtp_settings desliga tudo", %{user: user} do
      user = smtp_fixture(user)
      assert {:ok, _} = Accounts.remove_smtp_settings(user)
      refute Accounts.smtp_configured?()
    end

    test "change_smtp_settings nunca devolve a senha salva", %{user: user} do
      user = smtp_fixture(user)
      changeset = Accounts.change_smtp_settings(user)
      assert Ecto.Changeset.get_field(changeset, :smtp_password) == nil
    end
  end

  describe "2FA" do
    setup do
      %{user: user_fixture() |> smtp_fixture()}
    end

    defp sent_code do
      assert_email_sent(fn email ->
        send(self(), {:code, Regex.run(~r/\b(\d{6})\b/, email.text_body) |> List.last()})
      end)

      assert_received {:code, code}
      code
    end

    test "envia um código de 6 dígitos que vale uma vez", %{user: user} do
      assert {:ok, _} = Accounts.deliver_two_factor_code(user)
      code = sent_code()

      assert code =~ ~r/^\d{6}$/
      assert Accounts.verify_two_factor_code(user, code) == :ok
      assert Accounts.verify_two_factor_code(user, code) == {:error, :expired}
    end

    test "guarda só o hash do código", %{user: user} do
      {:ok, _} = Accounts.deliver_two_factor_code(user)
      code = sent_code()

      token = Repo.get_by!(Accounts.UserToken, user_id: user.id, context: "2fa")
      refute token.token == code
      assert token.token == Accounts.UserToken.hash_two_factor_code(code)
    end

    test "código errado conta tentativa e esgota em 5", %{user: user} do
      {:ok, _} = Accounts.deliver_two_factor_code(user)
      code = sent_code()
      wrong = if code == "000000", do: "111111", else: "000000"

      for _ <- 1..4,
          do: assert(Accounts.verify_two_factor_code(user, wrong) == {:error, :invalid})

      assert Accounts.verify_two_factor_code(user, wrong) == {:error, :too_many_attempts}
      assert Accounts.verify_two_factor_code(user, code) == {:error, :expired}
    end

    test "código expirado é recusado", %{user: user} do
      {:ok, _} = Accounts.deliver_two_factor_code(user)
      code = sent_code()

      past = DateTime.add(DateTime.utc_now(:second), -11, :minute)

      Repo.update_all(from(t in Accounts.UserToken, where: t.context == "2fa"),
        set: [inserted_at: past]
      )

      assert Accounts.verify_two_factor_code(user, code) == {:error, :expired}
    end

    test "reenvio respeita o cooldown de 60s e depois substitui o código", %{user: user} do
      {:ok, _} = Accounts.deliver_two_factor_code(user)
      _first = sent_code()
      assert Accounts.deliver_two_factor_code(user) == {:error, :cooldown}

      past = DateTime.add(DateTime.utc_now(:second), -61, :second)

      Repo.update_all(from(t in Accounts.UserToken, where: t.context == "2fa"),
        set: [inserted_at: past]
      )

      assert {:ok, _} = Accounts.deliver_two_factor_code(user)
      second = sent_code()

      assert Repo.aggregate(from(t in Accounts.UserToken, where: t.context == "2fa"), :count) == 1
      assert Accounts.verify_two_factor_code(user, second) == :ok
    end

    test "se o envio falha, o código não fica ativo", %{user: user} do
      expect(Grana.Mailer, :send_email, fn _email, _config -> {:error, :timeout} end)

      assert {:error, :timeout} = Accounts.deliver_two_factor_code(user)
      assert Repo.aggregate(from(t in Accounts.UserToken, where: t.context == "2fa"), :count) == 0
    end
  end

  describe "recuperação de senha" do
    setup do
      %{user: user_fixture() |> smtp_fixture()}
    end

    test "o link redefine a senha e derruba as sessões", %{user: user} do
      Accounts.generate_user_session_token(user)

      token =
        extract_user_token(fn url ->
          Accounts.deliver_reset_password_instructions(user, url)
        end)

      assert Accounts.get_user_by_reset_password_token(token).id == user.id

      assert {:ok, {_user, expired}} =
               Accounts.reset_user_password(user, %{
                 password: "outra senha longa",
                 password_confirmation: "outra senha longa"
               })

      assert expired != []
      assert Accounts.get_user_by_email_and_password(user.email, "outra senha longa")
      assert Accounts.get_user_by_reset_password_token(token) == nil
    end

    test "um novo pedido invalida o anterior", %{user: user} do
      {:ok, first} = Accounts.build_reset_password_token(user)
      {:ok, second} = Accounts.build_reset_password_token(user)

      assert Accounts.get_user_by_reset_password_token(first) == nil
      assert Accounts.get_user_by_reset_password_token(second)
    end

    test "token inválido ou expirado", %{user: user} do
      assert Accounts.get_user_by_reset_password_token("oops") == nil
      assert Accounts.get_user_by_reset_password_token("%%%") == nil

      {:ok, token} = Accounts.build_reset_password_token(user)
      past = DateTime.add(DateTime.utc_now(:second), -31, :minute)

      Repo.update_all(from(t in Accounts.UserToken, where: t.context == "reset_password"),
        set: [inserted_at: past]
      )

      assert Accounts.get_user_by_reset_password_token(token) == nil
    end
  end

  describe "public_base_url/1" do
    test "PUBLIC_URL > base_url do dono > localhost" do
      assert Accounts.public_base_url(%{base_url: "http://192.168.0.5:4000"}) ==
               "http://192.168.0.5:4000"

      assert Accounts.public_base_url() =~ "http://localhost"

      Application.put_env(:grana, :public_url, "https://grana.exemplo.com")
      on_exit(fn -> Application.delete_env(:grana, :public_url) end)

      assert Accounts.public_base_url(%{base_url: "http://x"}) == "https://grana.exemplo.com"
    end
  end
end
