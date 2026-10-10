defmodule GranaWeb.OnboardingLiveTest do
  use GranaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Grana.AccountsFixtures

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

    advance(lv, 5)
    assert has_element?(lv, "#onboarding-finish")

    lv |> element("#onboarding-back") |> render_click()
    assert has_element?(lv, "#import-form")
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

  test "importar CSV enfileira o job", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/onboarding")
    advance(lv, 4)

    csv = file_input(lv, "#import-form", :import, [%{name: "export.csv", content: "a,b\n1,2\n"}])
    render_upload(csv, "export.csv")
    lv |> form("#import-form") |> render_submit()

    assert has_element?(lv, "#import-result")
    assert [_job] = Grana.Repo.all(Oban.Job)
  end

  test "Ir para o painel na última etapa conclui o onboarding", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/onboarding")
    advance(lv, 5)

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
end
