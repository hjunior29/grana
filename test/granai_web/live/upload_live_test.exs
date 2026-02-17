defmodule GranaiWeb.UploadLiveTest do
  use GranaiWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders upload page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/upload")
    assert html =~ "Upload"
    assert html =~ "Nubank"
    assert html =~ "Bradesco"
  end

  test "shows page description", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/upload")
    assert html =~ "Importe e gerencie seus extratos e faturas"
  end

  test "selecting bank shows type selection", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/upload")
    html = view |> element("button[phx-value-bank=nubank]") |> render_click()
    assert html =~ "Extrato"
    assert html =~ "Fatura"
  end

  test "redirects unauthenticated users", %{conn: _conn} do
    conn = build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/upload")
  end
end
