defmodule GranaWeb.SetupGateTest do
  use GranaWeb.ConnCase, async: false

  describe "com a instância sem dono" do
    test "redireciona toda rota do app para /setup", %{conn: conn} do
      for path <- ["/users/log-in", "/dashboard", "/onboarding", "/admin/oban"] do
        assert redirected_to(get(conn, path)) == "/setup"
      end
    end

    test "não bloqueia /health nem os webhooks", %{conn: conn} do
      assert json_response(get(conn, "/health"), 200)

      conn = post(conn, "/webhooks/pluggy", %{})
      refute conn.status in [301, 302]
    end

    test "a landing continua acessível", %{conn: conn} do
      assert html_response(get(conn, "/"), 200) =~ "hero-install"
    end

    test "/setup responde", %{conn: conn} do
      assert html_response(get(conn, "/setup"), 200) =~ "setup-code-form"
    end
  end

  describe "com dono" do
    setup :ensure_owner

    test "/setup deixa de existir", %{conn: conn} do
      assert response(get(conn, "/setup"), 404)
    end

    test "as demais rotas funcionam normalmente", %{conn: conn} do
      assert html_response(get(conn, "/users/log-in"), 200)
    end
  end

  describe "cache do estado de setup" do
    setup do
      Application.put_env(:grana, :cache_setup_state, true)
      Grana.Accounts.invalidate_setup_cache()

      on_exit(fn ->
        Application.put_env(:grana, :cache_setup_state, false)
        Grana.Accounts.invalidate_setup_cache()
      end)
    end

    test "guarda o resultado até ser invalidado" do
      assert Grana.Accounts.setup_required?()
      Grana.AccountsFixtures.user_fixture()
      assert Grana.Accounts.setup_required?()

      Grana.Accounts.invalidate_setup_cache()
      refute Grana.Accounts.setup_required?()
    end
  end
end
