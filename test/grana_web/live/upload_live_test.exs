defmodule GranaWeb.UploadLiveTest do
  use GranaWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders upload page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/upload")
    assert html =~ "Importar"
    assert html =~ "Fatura / Extrato"
    assert html =~ "Grana (exportação)"
  end

  test "shows page description", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/upload")
    assert html =~ "Importe e gerencie seus extratos e faturas"
  end

  test "selecting banking category shows bank selection", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/upload")
    html = view |> element("button[phx-value-category=banking]") |> render_click()
    assert html =~ "Nubank"
    assert html =~ "Bradesco"
  end

  test "selecting bank shows type selection", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/upload")
    view |> element("button[phx-value-category=banking]") |> render_click()
    html = view |> element("button[phx-value-bank=nubank]") |> render_click()
    assert html =~ "Extrato"
    assert html =~ "Fatura"
  end

  test "redirects unauthenticated users", %{conn: _conn} do
    conn = build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/upload")
  end
end
