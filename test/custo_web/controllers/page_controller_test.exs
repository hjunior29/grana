defmodule CustoWeb.PageControllerTest do
  use CustoWeb.ConnCase

  test "GET / shows landing page", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Controle total"
  end
end
