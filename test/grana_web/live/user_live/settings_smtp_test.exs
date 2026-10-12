defmodule GranaWeb.UserLive.SettingsSmtpTest do
  use GranaWeb.ConnCase, async: false
  use Mimic

  import Phoenix.LiveViewTest
  import Grana.AccountsFixtures
  import Swoosh.TestAssertions

  alias Grana.Accounts

  @form %{
    "smtp_host" => "smtp.exemplo.com",
    "smtp_port" => "587",
    "smtp_username" => "grana",
    "smtp_password" => "segredo",
    "smtp_tls" => "always",
    "smtp_from_name" => "Grana",
    "smtp_from_address" => "grana@exemplo.com"
  }

  setup %{conn: conn} do
    # O card só deixa salvar com CLOAK_KEY própria (como o da Pluggy).
    original = System.get_env("CLOAK_KEY")
    System.put_env("CLOAK_KEY", "uAsvYu1DjJFziFfKP1ZJyiinCOYCZD1CFb4QMGMzpZU=")

    on_exit(fn ->
      if original, do: System.put_env("CLOAK_KEY", original), else: System.delete_env("CLOAK_KEY")
    end)

    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "sem SMTP mostra o formulário", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    assert has_element?(lv, "#smtp-none")
    assert has_element?(lv, "#smtp-form")
  end

  test "envia o teste, salva e liga o 2FA", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    html = lv |> form("#smtp-form", user: @form) |> render_submit()

    assert html =~ "SMTP salvo"
    assert has_element?(lv, "#smtp-saved")
    assert_email_sent(subject: "Seu email no Grana está funcionando")
    assert Accounts.smtp_configured?()
    assert Accounts.get_user!(user.id).smtp_host == "smtp.exemplo.com"
  end

  test "falha no teste não salva e mostra o erro", %{conn: conn} do
    expect(Grana.Mailer, :send_email, fn _email, _config -> {:error, :econnrefused} end)
    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    html = lv |> form("#smtp-form", user: @form) |> render_submit()

    assert html =~ "nada foi salvo"
    refute html =~ "segredo"
    refute Accounts.smtp_configured?()
  end

  test "fonte banco: substituir e remover", %{conn: conn, user: user} do
    smtp_fixture(user)
    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    refute has_element?(lv, "#smtp-form")
    lv |> element("#smtp-replace") |> render_click()
    assert has_element?(lv, "#smtp-form")

    lv |> element("#smtp-remove-modal-confirm") |> render_click()
    assert has_element?(lv, "#smtp-none")
    refute Accounts.smtp_configured?()
  end

  test "fonte ambiente não oferece formulário nem botões", %{conn: conn} do
    Application.put_env(:grana, :smtp_env, %{
      host: "env.example.com",
      port: 587,
      tls: :always,
      username: "env-user",
      password: "env-secret",
      from_name: "Grana",
      from_address: "a@b.com"
    })

    on_exit(fn -> Application.delete_env(:grana, :smtp_env) end)

    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    assert has_element?(lv, "#smtp-env")
    assert has_element?(lv, "#smtp-env-host[readonly][value=SMTP_HOST]")
    assert has_element?(lv, "#smtp-env-password[readonly][value=SMTP_PASSWORD]")
    refute render(lv) =~ "env.example.com"
    assert has_element?(lv, "#smtp-env label span", ".env")
    refute has_element?(lv, "#smtp-form")
    refute has_element?(lv, "#smtp-remove")

    html = render_hook(lv, "smtp_save", %{"user" => @form})
    assert html =~ "já vem todo do .env"
  end

  test "ambiente sem SMTP_HOST: o resto fica travado e só falta o servidor", %{
    conn: conn,
    user: user
  } do
    Application.put_env(:grana, :smtp_env, %{
      port: 587,
      tls: :always,
      username: "env-user",
      password: "env-secret",
      from_name: "Grana",
      from_address: "env@example.com"
    })

    on_exit(fn -> Application.delete_env(:grana, :smtp_env) end)

    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    assert has_element?(lv, "#smtp-incomplete", "SMTP_HOST")
    assert has_element?(lv, "#smtp-2fa", "2FA desativado")
    assert has_element?(lv, "#smtp-form #smtp-env-password[readonly][value=SMTP_PASSWORD]")
    assert has_element?(lv, ~s|#smtp-form input[name="user[smtp_host]"]|)
    refute has_element?(lv, ~s|#smtp-form input[name="user[smtp_password]"]|)

    lv |> form("#smtp-form", user: %{smtp_host: "smtp.exemplo.com"}) |> render_submit()

    assert Accounts.get_user!(user.id).smtp_host == "smtp.exemplo.com"
    assert Accounts.smtp_source() == :mixed
    assert has_element?(lv, "#smtp-saved", "smtp.exemplo.com:587")
    assert has_element?(lv, "#smtp-env-caption", "SMTP_USERNAME")
    assert has_element?(lv, "#smtp-2fa", "2FA ativo")

    {:ok, lv, _html} = live(conn, ~p"/users/settings")
    assert has_element?(lv, "#diagnostics-integrations .ui-tag-env")
    assert has_element?(lv, "#diagnostics-integrations .ui-tag-salvo")
  end

  test "ambiente com servidor mas incompleto pode ser completado na tela", %{conn: conn} do
    Application.put_env(:grana, :smtp_env, %{host: "env.example.com", password: "env-secret"})
    on_exit(fn -> Application.delete_env(:grana, :smtp_env) end)

    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    assert has_element?(lv, "#smtp-env #smtp-env-host")
    refute has_element?(lv, "#smtp-env #smtp-env-port")
    refute has_element?(lv, "#smtp-form")

    lv |> element("#smtp-complete") |> render_click()

    assert has_element?(lv, "#smtp-form #smtp-env-host[readonly]")
    assert has_element?(lv, ~s|#smtp-form input[name="user[smtp_from_address]"]|)

    lv |> element("#smtp-complete-cancel") |> render_click()
    refute has_element?(lv, "#smtp-form")
  end

  test "sem CLOAK_KEY própria avisa em vez de mostrar o formulário", %{conn: conn} do
    System.delete_env("CLOAK_KEY")
    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    assert has_element?(lv, "#smtp-cloak-key-warning")
    refute has_element?(lv, "#smtp-form")

    assert render_hook(lv, "smtp_save", %{"user" => @form}) =~ "Defina CLOAK_KEY"
  end

  test "salvar e remover exigem sudo mode", %{conn: conn, user: user} do
    smtp_fixture(user)

    conn =
      log_in_user(conn, user,
        token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -21, :minute)
      )

    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             lv |> element("#smtp-remove-modal-confirm") |> render_click()

    assert Accounts.smtp_configured?()
  end
end
