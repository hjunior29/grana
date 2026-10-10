defmodule GranaWeb.UserLive.PasswordResetTest do
  use GranaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Grana.AccountsFixtures
  import Swoosh.TestAssertions

  alias Grana.Accounts

  setup do
    %{user: user_fixture()}
  end

  describe "esqueci a senha" do
    test "o login tem o link", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")
      assert has_element?(lv, "#forgot-password-link")
    end

    test "sem SMTP mostra como rodar o comando no servidor", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

      assert has_element?(lv, "#reset-instructions")
      refute has_element?(lv, "#forgot_password_form")
    end

    test "com SMTP envia o link e não revela se o email existe", %{conn: conn, user: user} do
      smtp_fixture(user)
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

      {:ok, _lv, html} =
        lv
        |> form("#forgot_password_form", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "Se o email estiver cadastrado"
      assert_email_sent(subject: "Redefinição de senha do Grana")
    end

    test "email desconhecido responde igual e não envia", %{conn: conn, user: user} do
      smtp_fixture(user)
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

      {:ok, _lv, html} =
        lv
        |> form("#forgot_password_form", user: %{email: "ninguem@example.com"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "Se o email estiver cadastrado"
      refute_email_sent()
    end
  end

  describe "redefinir senha" do
    setup %{user: user} do
      {:ok, token} = Accounts.build_reset_password_token(user)
      %{token: token}
    end

    test "token inválido volta ao login", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/users/log-in", flash: flash}}} =
               live(conn, ~p"/users/reset-password/oops")

      assert flash["error"] =~ "inválido ou expirou"
    end

    test "valida a senha", %{conn: conn, token: token} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password/#{token}")

      html =
        lv
        |> form("#reset_password_form", user: %{password: "curta", password_confirmation: "x"})
        |> render_change()

      assert html =~ "should be at least 12 character"
    end

    test "troca a senha e derruba as sessões", %{conn: conn, token: token, user: user} do
      session = Accounts.generate_user_session_token(user)
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password/#{token}")

      {:ok, _lv, html} =
        lv
        |> form("#reset_password_form",
          user: %{password: "uma senha nova longa", password_confirmation: "uma senha nova longa"}
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "Senha redefinida"
      assert Accounts.get_user_by_email_and_password(user.email, "uma senha nova longa")
      refute Accounts.get_user_by_session_token(session)
      assert Accounts.get_user_by_reset_password_token(token) == nil
    end

    test "confirmação diferente mostra erro", %{conn: conn, token: token} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password/#{token}")

      html =
        lv
        |> form("#reset_password_form",
          user: %{password: "uma senha nova longa", password_confirmation: "outra coisa"}
        )
        |> render_submit()

      assert html =~ "does not match password"
    end
  end
end
