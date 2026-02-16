defmodule CustoWeb.AnalysisLiveTest do
  use CustoWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders analysis page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/analysis")
    assert html =~ "Análise"
    assert html =~ "Obtenha insights inteligentes"
  end

  test "shows filter controls", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/analysis")
    assert html =~ "Configurar Análise"
    assert html =~ "Analisar"
    assert html =~ "Ano todo"
  end

  test "shows empty history", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/analysis")
    assert html =~ "Nenhuma transação encontrada"
  end

  test "redirects unauthenticated users", %{conn: _conn} do
    conn = build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/analysis")
  end
end
