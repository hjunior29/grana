defmodule GranaWeb.PreferencesTest do
  use GranaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Grana.AccountsFixtures

  alias Grana.Accounts

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "o padrão é tema do sistema e estilo default", %{user: user} do
    assert user.theme == "system"
    assert user.visual_style == "default"
  end

  test "o toggle de tema nas configurações grava no servidor", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    lv |> element(~s|.theme-toggle [data-phx-theme="dark"]|) |> render_click()

    assert Accounts.get_user!(user.id).theme == "dark"
  end

  test "o toggle de estilo grava no servidor", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    lv |> element(~s|#visual-style-toggle [data-phx-visual-style="signal"]|) |> render_click()

    assert Accounts.get_user!(user.id).visual_style == "signal"
  end

  test "valores inválidos são ignorados", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    render_hook(lv, "set_preference", %{"theme" => "neon", "visual_style" => "x"})

    assert Accounts.get_user!(user.id).theme == "system"
  end

  test "o root layout renderiza a preferência do usuário", %{conn: conn, user: user} do
    {:ok, _} = Accounts.update_user_preferences(user, %{theme: "dark", visual_style: "bossa"})

    document = conn |> get(~p"/users/settings") |> html_response(200) |> LazyHTML.from_document()

    assert LazyHTML.query(document, ~s|html[data-server-theme="dark"]|) |> Enum.count() == 1

    assert LazyHTML.query(document, ~s|html[data-server-visual-style="bossa"]|) |> Enum.count() ==
             1
  end

  test "sem login o root layout não força preferência", %{conn: _} do
    ensure_owner(%{})

    document =
      build_conn() |> get(~p"/users/log-in") |> html_response(200) |> LazyHTML.from_document()

    assert LazyHTML.query(document, "html[data-server-theme]") |> Enum.count() == 0
  end

  test "a etapa de aparência do onboarding persiste as escolhas", %{conn: conn, user: user} do
    user |> Ecto.Changeset.change(onboarded_at: nil) |> Grana.Repo.update!()
    {:ok, lv, _html} = live(conn, ~p"/onboarding")

    assert has_element?(lv, "#visual-style-toggle")
    lv |> element(~s|#visual-style-toggle [data-phx-visual-style="papel"]|) |> render_click()
    lv |> element(~s|.theme-toggle [data-phx-theme="light"]|) |> render_click()

    user = Accounts.get_user!(user.id)
    assert user.visual_style == "papel"
    assert user.theme == "light"
  end

  test "o toggle da landing (visitante) não tenta salvar", %{conn: _} do
    ensure_owner(%{})
    {:ok, lv, _html} = live(build_conn(), ~p"/")

    assert has_element?(lv, ".theme-toggle")
    refute render(lv) =~ "set_preference"
  end
end
