defmodule Grana.MailerTest do
  use Grana.DataCase, async: false

  import Grana.AccountsFixtures
  import Swoosh.TestAssertions
  import Swoosh.Email

  alias Grana.Mailer

  defp email, do: new() |> to("dono@example.com") |> subject("Oi") |> text_body("corpo")

  describe "send_email/2" do
    test "sem SMTP e sem fallback local, não envia" do
      assert Mailer.send_email(email()) == {:error, :smtp_not_configured}
      refute_email_sent()
    end

    test "com fallback local (dev), envia pelo adapter configurado" do
      Application.put_env(:grana, :mailer_local_fallback, true)
      on_exit(fn -> Application.delete_env(:grana, :mailer_local_fallback) end)

      assert {:ok, _} = Mailer.send_email(email())
      assert_email_sent(subject: "Oi")
    end

    test "com SMTP salvo, usa o remetente configurado" do
      user_fixture() |> smtp_fixture(%{smtp_from_name: "Meu Grana"})

      assert {:ok, _} = Mailer.send_email(email())
      assert_email_sent(from: {"Meu Grana", "grana@example.com"})
    end

    test "porta 465 usa TLS implícito sem quebrar o envio" do
      user_fixture() |> smtp_fixture(%{smtp_port: 465})
      assert {:ok, _} = Mailer.send_email(email())
    end

    test "o SMTP do ambiente tem precedência sobre o salvo" do
      user_fixture() |> smtp_fixture()

      Application.put_env(:grana, :smtp_env, %{
        host: "smtp.env.com",
        port: 25,
        username: nil,
        password: nil,
        tls: :never,
        from_name: "Env",
        from_address: "env@example.com"
      })

      on_exit(fn -> Application.delete_env(:grana, :smtp_env) end)

      assert {:ok, _} = Mailer.send_email(email())
      assert_email_sent(from: {"Env", "env@example.com"})
    end
  end
end
