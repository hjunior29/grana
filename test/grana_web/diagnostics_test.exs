defmodule GranaWeb.DiagnosticsTest do
  use GranaWeb.ConnCase

  import Grana.AccountsFixtures

  test "/admin/oban e /admin/errors pedem login", %{conn: conn} do
    setup_owner()

    for path <- ["/admin/oban", "/admin/errors"] do
      assert redirected_to(get(conn, path)) == ~p"/users/log-in"
    end
  end

  # O Oban Web não sobe sem o Oban.Met (desligado em test); o painel de erros
  # prova que o dono comum, sem ADMIN_EMAIL, passa pela autorização.
  test "o dono logado acessa o painel de erros", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())

    assert html_response(get(conn, "/admin/errors"), 200)
  end

  defp setup_owner, do: user_fixture()
end
