defmodule GranaWeb.OnboardingLiveTest do
  use GranaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Grana.AccountsFixtures
  import Swoosh.TestAssertions

  alias Grana.Accounts

  setup %{conn: conn} do
    user = user_fixture() |> Ecto.Changeset.change(onboarded_at: nil) |> Grana.Repo.update!()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "exige login", %{conn: _} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(build_conn(), ~p"/onboarding")
  end

  defp advance(lv, 0), do: lv

  defp advance(lv, n) do
    lv |> element("#onboarding-skip") |> render_click()
    advance(lv, n - 1)
  end

  test "percorre as etapas e Voltar retorna uma etapa", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/onboarding")
    refute has_element?(lv, "#onboarding-back")

    advance(lv, 4)
    assert has_element?(lv, "#onboarding-finish")

    lv |> element("#onboarding-back") |> render_click()
    assert has_element?(lv, "#open-finance-settings")
  end

  test "o onboarding não tem mais etapa de importação", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/onboarding")

    refute has_element?(lv, "#onboarding-step-import")
    advance(lv, 3)
    refute has_element?(lv, "#import-form")
    advance(lv, 1)
    assert has_element?(lv, "#onboarding-finish")
  end

  test "não há mais Pular tudo", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/onboarding")
    refute has_element?(lv, "#onboarding-skip-all")
  end

  test "etapa de email mostra o card de SMTP", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/onboarding")
    lv |> element("#onboarding-skip") |> render_click()

    assert has_element?(lv, "#smtp-settings")
  end

  test "etapa de IA salva a chave", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/onboarding")
    advance(lv, 2)

    assert has_element?(lv, "#ai_form")
    assert has_element?(lv, ~s|button#onboarding-next[form="ai_form"]|)
    refute has_element?(lv, "#ai_form button", "Salvar")

    lv
    |> form("#ai_form", user: %{ai_model: "gemini-2.5-flash", ai_api_key: "chave-secreta"})
    |> render_submit()

    user = Accounts.get_user!(user.id)
    assert user.ai_api_key == "chave-secreta"
    assert user.ai_model == "gemini-2.5-flash"
    assert has_element?(lv, "#open-finance-settings")
  end

  test "etapa LLM com chave do .env não oferece salvar e o Continuar avança", %{conn: conn} do
    Application.put_env(:grana, :gemini_api_key, "env-key")
    on_exit(fn -> Application.delete_env(:grana, :gemini_api_key) end)

    {:ok, lv, _html} = live(conn, ~p"/onboarding")
    advance(lv, 2)

    assert has_element?(lv, "#ai-api-key-env")
    assert has_element?(lv, "#ai-api-key-env-input[disabled][value=GEMINI_API_KEY]")
    assert has_element?(lv, "#ai-api-key-env label span", ".env")
    refute render(lv) =~ "env-key"
    assert has_element?(lv, "#onboarding h1", "LLM")
    refute has_element?(lv, "#ai_form button", "Salvar")

    lv |> form("#ai_form", user: %{ai_model: "gemini-2.5-pro"}) |> render_submit()
    assert has_element?(lv, "#open-finance-settings")
    assert Accounts.get_user!(socket_user_id(lv)).ai_model == "gemini-2.5-pro"
  end

  defp socket_user_id(_lv), do: Grana.Repo.one!(Grana.Accounts.User).id

  test "etapa Open Finance mostra o card de credenciais", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/onboarding")
    advance(lv, 3)

    assert has_element?(lv, "#open-finance-settings")
  end

  test "Ir para o painel na última etapa conclui o onboarding", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/onboarding")
    advance(lv, 4)

    lv |> element("#onboarding-finish") |> render_click()
    assert_redirect(lv, ~p"/dashboard")
    assert Accounts.get_user!(user.id).onboarded_at
  end

  test "login de quem não concluiu o onboarding leva a /onboarding", %{user: user} do
    {:ok, _} = Accounts.update_user_password(user, %{password: valid_user_password()})

    conn =
      post(build_conn(), ~p"/users/log-in", %{
        "user" => %{"email" => user.email, "password" => valid_user_password()}
      })

    assert redirected_to(conn) == ~p"/onboarding"
  end

  describe "etapas que exigem dados" do
    use Mimic

    @smtp %{
      "smtp_host" => "smtp.exemplo.com",
      "smtp_port" => "587",
      "smtp_username" => "grana",
      "smtp_password" => "segredo",
      "smtp_tls" => "always",
      "smtp_from_name" => "Grana",
      "smtp_from_address" => "grana@exemplo.com"
    }

    setup do
      original = System.get_env("CLOAK_KEY")
      System.put_env("CLOAK_KEY", "uAsvYu1DjJFziFfKP1ZJyiinCOYCZD1CFb4QMGMzpZU=")

      on_exit(fn ->
        if original,
          do: System.put_env("CLOAK_KEY", original),
          else: System.delete_env("CLOAK_KEY")
      end)
    end

    test "SMTP: o botão só envia o teste, sem salvar", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/onboarding")
      advance(lv, 1)

      assert has_element?(lv, "#smtp-test", "Enviar teste")
      refute render(lv) =~ "Enviar teste e salvar"

      html = lv |> form("#smtp-form", user: @smtp) |> render_submit(%{"intent" => "test"})

      assert html =~ "Email de teste enviado"
      assert_email_sent(subject: "Teste de email — Grana")
      refute Accounts.smtp_configured?()
      assert has_element?(lv, "#smtp-form")
    end

    test "SMTP: Continuar testa, salva e avança", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/onboarding")
      advance(lv, 1)

      assert has_element?(lv, ~s|button#onboarding-next[form="smtp-form"]|)
      lv |> form("#smtp-form", user: @smtp) |> render_submit()

      assert Accounts.smtp_configured?()
      assert has_element?(lv, "#ai_form")
    end

    test "SMTP: sem preencher não avança (só com Pular)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/onboarding")
      advance(lv, 1)

      lv |> form("#smtp-form", user: %{smtp_host: ""}) |> render_submit()

      assert has_element?(lv, "#smtp-form")
      refute Accounts.smtp_configured?()
      advance(lv, 1)
      assert has_element?(lv, "#ai_form")
    end

    test "SMTP falhando no teste não salva nem avança", %{conn: conn} do
      expect(Grana.Mailer, :send_email, fn _email, _config -> {:error, :econnrefused} end)
      {:ok, lv, _html} = live(conn, ~p"/onboarding")
      advance(lv, 1)

      html = lv |> form("#smtp-form", user: @smtp) |> render_submit()

      assert html =~ "nada foi salvo"
      assert has_element?(lv, "#smtp-form")
    end

    test "LLM: sem chave não avança e mostra o erro", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/onboarding")
      advance(lv, 2)

      lv |> form("#ai_form", user: %{ai_model: "gemini-2.5-flash"}) |> render_submit()

      assert has_element?(lv, "#ai-api-key-error", "informe a chave")
      assert has_element?(lv, "#ai_form")
    end

    test "Open Finance: Continuar fica bloqueado até ter credenciais", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/onboarding")
      advance(lv, 3)

      assert has_element?(lv, "button#onboarding-next[disabled]")
      assert has_element?(lv, "#onboarding-skip")

      Grana.OpenFinanceFixtures.with_pluggy_credentials(user)
      {:ok, lv, _html} = live(conn, ~p"/onboarding")
      advance(lv, 3)
      refute has_element?(lv, "button#onboarding-next[disabled]")
    end
  end
end
