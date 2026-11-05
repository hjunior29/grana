defmodule GranaWeb.StatementsLiveTest do
  use GranaWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "without data there is no history tab nor its empty list", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/upload?tab=historico")

    refute has_element?(view, "button[phx-value-tab=historico]")
    refute has_element?(view, "#statements-empty")
  end

  test "shows page description", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/upload")
    assert html =~ "Importe e gerencie seus extratos e faturas"
  end

  test "redirects unauthenticated users", %{conn: _conn} do
    conn = build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/upload")
  end
end
