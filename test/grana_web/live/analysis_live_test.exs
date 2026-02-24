defmodule GranaWeb.AnalysisLiveTest do
  use GranaWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders analysis page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/analysis")
    assert html =~ "Análise"
    assert html =~ "Insights inteligentes sobre suas finanças"
  end

  test "shows filter controls", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/analysis")
    assert html =~ "Pergunte algo sobre suas finanças"
    assert html =~ "Analisar com IA"
  end

  test "shows empty history", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/analysis")
    assert html =~ "Nenhuma análise ainda"
  end

  test "redirects unauthenticated users", %{conn: _conn} do
    conn = build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/analysis")
  end
end
