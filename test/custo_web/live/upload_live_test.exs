defmodule CustoWeb.UploadLiveTest do
  use CustoWeb.ConnCase

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
    assert html =~ "Importe extratos e faturas em formato CSV ou PDF"
  end

  test "selecting bank shows upload area", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/upload")
    html = view |> element("button[phx-value-bank=nubank]") |> render_click()
    assert html =~ "Arraste arquivos CSV ou PDF"
  end

  test "redirects unauthenticated users", %{conn: _conn} do
    conn = build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/upload")
  end
end
