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

  describe "etapa LLM" do
    use Mimic

    setup :set_mimic_global

    test "sem provedor, o Continuar fica bloqueado (só Pular)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/onboarding")
      advance(lv, 2)

      assert has_element?(lv, "#onboarding h1", "LLM")
      assert has_element?(lv, "#ai-no-providers")
      assert has_element?(lv, "button#onboarding-next[disabled]")

      advance(lv, 1)
      assert has_element?(lv, "#open-finance-settings")
    end

    test "cadastrar um provedor libera o Continuar", %{conn: conn, user: user} do
      stub(Grana.AI.Models, :list, fn _ -> {:ok, [%{id: "claude-x", name: "Claude X"}]} end)
      {:ok, lv, _html} = live(conn, ~p"/onboarding")
      advance(lv, 2)

      lv |> element("#ai-add-provider") |> render_click()

      lv
      |> form("#ai-provider-form", provider: %{kind: "anthropic", api_key: "sk-ant"})
      |> render_submit()

      refute has_element?(lv, "button#onboarding-next[disabled]")
      assert Accounts.get_user!(user.id).ai_model == "claude-x"

      lv |> element("#onboarding-next") |> render_click()
      assert has_element?(lv, "#open-finance-settings")
    end

    test "provedor do .env aparece, com a tag, sem expor a chave", %{conn: conn} do
      Application.put_env(:grana, :ai_env_keys, %{"openai" => "sk-do-env"})
      on_exit(fn -> Application.delete_env(:grana, :ai_env_keys) end)
      stub(Grana.AI.Models, :list, fn _ -> {:ok, [%{id: "gpt-5-mini", name: "gpt-5-mini"}]} end)

      {:ok, lv, _html} = live(conn, ~p"/onboarding")
      advance(lv, 2)
      html = render_async(lv)

      refute html =~ "sk-do-env"
      assert has_element?(lv, "#ai-provider-env\\:openai .badge", ".env")
      refute has_element?(lv, "button#onboarding-next[disabled]")
    end
  end

  test "etapa de email mostra o card de SMTP", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/onboarding")
    lv |> element("#onboarding-skip") |> render_click()

    assert has_element?(lv, "#smtp-settings")
  end

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
      assert_email_sent(subject: "Seu email no Grana está funcionando")
      refute Accounts.smtp_configured?()
      assert has_element?(lv, "#smtp-form")
    end

    test "SMTP: Continuar testa, salva e avança", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/onboarding")
      advance(lv, 1)

      assert has_element?(lv, ~s|button#onboarding-next[form="smtp-form"]|)
      lv |> form("#smtp-form", user: @smtp) |> render_submit()

      assert Accounts.smtp_configured?()
      assert has_element?(lv, "#ai-providers")
    end

    test "SMTP: sem preencher não avança (só com Pular)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/onboarding")
      advance(lv, 1)

      lv |> form("#smtp-form", user: %{smtp_host: ""}) |> render_submit()

      assert has_element?(lv, "#smtp-form")
      refute Accounts.smtp_configured?()
      advance(lv, 1)
      assert has_element?(lv, "#ai-providers")
    end

    test "SMTP falhando no teste não salva nem avança", %{conn: conn} do
      expect(Grana.Mailer, :send_email, fn _email, _config -> {:error, :econnrefused} end)
      {:ok, lv, _html} = live(conn, ~p"/onboarding")
      advance(lv, 1)

      html = lv |> form("#smtp-form", user: @smtp) |> render_submit()

      assert html =~ "nada foi salvo"
      assert has_element?(lv, "#smtp-form")
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
