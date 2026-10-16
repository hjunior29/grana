defmodule GranaWeb.TwoFactorFlowTest do
  use GranaWeb.ConnCase, async: false
  use Mimic

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest
  import Grana.AccountsFixtures
  import Swoosh.TestAssertions

  alias Grana.Accounts

  setup do
    %{user: user_fixture()}
  end

  defp password_login(conn, user, extra \\ %{}) do
    post(conn, ~p"/users/log-in", %{
      "user" => Map.merge(%{"email" => user.email, "password" => valid_user_password()}, extra)
    })
  end

  defp last_code do
    assert_email_sent(fn email ->
      send(self(), {:code, Regex.run(~r/\b(\d{6})\b/, email.text_body) |> List.last()})
    end)

    assert_received {:code, code}
    code
  end

  describe "sem SMTP" do
    test "a senha entra direto, sem pedir código", %{conn: conn, user: user} do
      conn = password_login(conn, user)

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/dashboard"
      refute_email_sent()
    end
  end

  describe "com SMTP" do
    setup %{user: user} do
      %{user: smtp_fixture(user)}
    end

    test "senha certa envia o código e não loga ainda", %{conn: conn, user: user} do
      conn = password_login(conn, user)

      assert redirected_to(conn) == ~p"/users/log-in/code"
      refute get_session(conn, :user_token)
      assert get_session(conn, :pending_2fa_user_id) == user.id
      assert last_code() =~ ~r/^\d{6}$/
    end

    test "senha errada não envia nada", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => "errada"}
        })

      assert redirected_to(conn) == ~p"/users/log-in"
      refute_email_sent()
    end

    test "código certo conclui o login (e vai ao onboarding se pendente)", %{
      conn: conn,
      user: user
    } do
      conn = password_login(conn, user)
      code = last_code()

      conn = post(recycle(conn), ~p"/users/log-in/code", %{"code" => code})

      assert get_session(conn, :user_token)
      refute get_session(conn, :pending_2fa_user_id)
      assert redirected_to(conn) == ~p"/dashboard"
    end

    test "manter conectado vale depois do código", %{conn: conn, user: user} do
      conn = password_login(conn, user, %{"remember_me" => "true"})
      code = last_code()

      conn = post(recycle(conn), ~p"/users/log-in/code", %{"code" => code})
      assert conn.resp_cookies["_grana_web_user_remember_me"]
    end

    test "código errado volta para a tela do código", %{conn: conn, user: user} do
      conn = password_login(conn, user)
      _ = last_code()

      conn = post(recycle(conn), ~p"/users/log-in/code", %{"code" => "abcdef"})

      assert redirected_to(conn) == ~p"/users/log-in/code"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Código incorreto."
      refute get_session(conn, :user_token)
    end

    test "código expirado manda recomeçar", %{conn: conn, user: user} do
      conn = password_login(conn, user)
      code = last_code()

      Grana.Repo.delete_all(Grana.Accounts.UserToken)
      conn = post(recycle(conn), ~p"/users/log-in/code", %{"code" => code})

      assert redirected_to(conn) == ~p"/users/log-in"
      refute get_session(conn, :pending_2fa_user_id)
    end

    test "5 erros esgotam o código", %{conn: conn, user: user} do
      conn = password_login(conn, user)
      code = last_code()
      wrong = if code == "000000", do: "111111", else: "000000"

      conn =
        Enum.reduce(1..4, recycle(conn), fn _, conn ->
          conn = post(conn, ~p"/users/log-in/code", %{"code" => wrong})
          assert redirected_to(conn) == ~p"/users/log-in/code"
          recycle(conn)
        end)

      conn = post(conn, ~p"/users/log-in/code", %{"code" => wrong})
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "sem tentativa de login pendente, volta ao login", %{conn: conn} do
      conn = post(conn, ~p"/users/log-in/code", %{"code" => "123456"})
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "se o envio falha, não loga e avisa", %{conn: conn, user: user} do
      expect(Grana.Mailer, :send_email, fn _email, _config -> {:error, :timeout} end)

      conn = password_login(conn, user)

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "grana-disable-smtp"
      refute get_session(conn, :user_token)
    end

    test "login repetido dentro do cooldown reaproveita o código", %{conn: conn, user: user} do
      conn = password_login(conn, user)
      code = last_code()

      conn = password_login(recycle(conn), user)
      assert redirected_to(conn) == ~p"/users/log-in/code"
      refute_email_sent()

      conn = post(recycle(conn), ~p"/users/log-in/code", %{"code" => code})
      assert get_session(conn, :user_token)
    end

    test "o remember-me restaura a sessão sem pedir código", %{conn: conn, user: user} do
      conn = password_login(conn, user, %{"remember_me" => "true"})
      code = last_code()
      conn = post(recycle(conn), ~p"/users/log-in/code", %{"code" => code})
      cookie = conn.resp_cookies["_grana_web_user_remember_me"].value

      conn =
        build_conn()
        |> put_req_cookie("_grana_web_user_remember_me", cookie)
        |> get(~p"/dashboard")

      assert html_response(conn, 200)
    end

    test "trocar a senha não pede 2FA de novo", %{conn: conn, user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/users/update-password", %{
          "current_password" => valid_user_password(),
          "user" => %{
            "password" => "outra senha longa",
            "password_confirmation" => "outra senha longa"
          }
        })

      assert redirected_to(conn) == ~p"/users/settings"
      assert get_session(conn, :user_token)
      refute_email_sent()
    end
  end

  describe "tela do código" do
    setup %{user: user} do
      %{user: smtp_fixture(user)}
    end

    test "sem login pendente, volta ao login", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/users/log-in/code")
    end

    test "mostra o formulário e reenvia respeitando o cooldown", %{conn: conn, user: user} do
      conn = password_login(conn, user)
      _ = last_code()

      {:ok, lv, html} = live(recycle(conn), ~p"/users/log-in/code")
      assert has_element?(lv, "#two_factor_form")
      refute html =~ user.email

      assert lv |> element("#resend-code") |> render_click() =~ "Aguarde um minuto"

      past = DateTime.add(DateTime.utc_now(:second), -61, :second)

      Grana.Repo.update_all(
        from(t in Accounts.UserToken, where: t.context == "2fa"),
        set: [inserted_at: past]
      )

      assert lv |> element("#resend-code") |> render_click() =~ "Enviamos um novo código"
      assert last_code() =~ ~r/^\d{6}$/
    end

    test "reenvio com falha de SMTP avisa", %{conn: conn, user: user} do
      conn = password_login(conn, user)
      _ = last_code()
      {:ok, lv, _html} = live(recycle(conn), ~p"/users/log-in/code")

      Grana.Repo.update_all(
        from(t in Accounts.UserToken, where: t.context == "2fa"),
        set: [inserted_at: DateTime.add(DateTime.utc_now(:second), -61, :second)]
      )

      expect(Grana.Mailer, :send_email, fn _email, _config -> {:error, :timeout} end)
      assert lv |> element("#resend-code") |> render_click() =~ "Não foi possível enviar"
    end
  end
end
