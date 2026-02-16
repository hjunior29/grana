defmodule GranaiWeb.StatementsLiveTest do
  use GranaiWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders statements page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/statements")
    assert html =~ "Extratos"
    assert html =~ "Nenhum extrato encontrado"
  end

  test "shows page description", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/statements")
    assert html =~ "Gerencie seus extratos bancários importados"
  end

  test "redirects unauthenticated users", %{conn: _conn} do
    conn = build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/statements")
  end
end
