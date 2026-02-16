defmodule CustoWeb.DashboardLiveTest do
  use CustoWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders dashboard page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/dashboard")
    assert html =~ "Dashboard"
    assert html =~ "Nenhuma transação encontrada"
  end

  test "shows upload button when no transactions", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/dashboard")
    assert html =~ "Upload"
  end

  test "shows period selector description", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/dashboard")
    assert html =~ "Visão geral das suas finanças"
  end

  test "redirects unauthenticated users", %{conn: _conn} do
    conn = build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/dashboard")
  end
end
