defmodule GranaWeb.PageControllerTest do
  use GranaWeb.ConnCase

  test "GET / shows landing page", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Controle total"
  end
end
