defmodule GranaWeb.HealthControllerTest do
  use GranaWeb.ConnCase, async: true

  test "GET /health responde ok sem sessão", %{conn: conn} do
    conn = get(conn, ~p"/health")
    assert json_response(conn, 200) == %{"status" => "ok"}
  end
end
