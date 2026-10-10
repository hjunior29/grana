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

  test "percorre as etapas com Continuar", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/onboarding")

    for _ <- 1..5, do: lv |> element("#onboarding-next") |> render_click()

    assert has_element?(lv, "#onboarding-finish")
  end

  test "etapa de IA salva a chave", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/onboarding")
    for _ <- 1..2, do: lv |> element("#onboarding-skip") |> render_click()

    assert has_element?(lv, "#ai_form")

    lv
    |> form("#ai_form", user: %{ai_model: "gemini-2.5-flash", ai_api_key: "chave-secreta"})
    |> render_submit()

    assert Accounts.get_user!(user.id).ai_api_key == "chave-secreta"
  end

  test "etapa Open Finance mostra o card de credenciais", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/onboarding")
    for _ <- 1..3, do: lv |> element("#onboarding-skip") |> render_click()

    assert has_element?(lv, "#open-finance-settings")
  end

  test "importar CSV enfileira o job", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/onboarding")
    for _ <- 1..4, do: lv |> element("#onboarding-skip") |> render_click()

    csv = file_input(lv, "#import-form", :import, [%{name: "export.csv", content: "a,b\n1,2\n"}])
    render_upload(csv, "export.csv")
    lv |> form("#import-form") |> render_submit()

    assert has_element?(lv, "#import-result")
    assert [_job] = Grana.Repo.all(Oban.Job)
  end

  test "Pular tudo marca o onboarding como concluído e vai ao painel", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/onboarding")

    lv |> element("#onboarding-skip-all") |> render_click()
    assert_redirect(lv, ~p"/dashboard")

    assert Accounts.get_user!(user.id).onboarded_at
  end

  test "Ir para o painel na última etapa conclui o onboarding", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/onboarding")
    for _ <- 1..5, do: lv |> element("#onboarding-next") |> render_click()

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
