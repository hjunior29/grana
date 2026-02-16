defmodule GranaiWeb.TransactionsLiveTest do
  use GranaiWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders transactions page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/transactions")
    assert html =~ "Transações"
    assert html =~ "Nenhuma transação encontrada"
  end

  test "shows page description", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/transactions")
    assert html =~ "Visualize e gerencie todas as suas transações"
  end

  test "shows filter panel", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/transactions")
    assert html =~ "Todas"
    assert html =~ "Sem Categoria"
    assert html =~ "Limpar filtros"
    assert html =~ "Todos os bancos"
    assert html =~ "Todos os tipos"
  end

  test "shows transaction count", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/transactions")
    assert html =~ "transação(ões) encontrada(s)"
  end

  test "redirects unauthenticated users", %{conn: _conn} do
    conn = build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/transactions")
  end
end
