defmodule GranaWeb.RateLimitTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias GranaWeb.RateLimit

  describe "client_ip/1" do
    test "prefere o header Fly-Client-IP (setado pelo proxy do Fly)" do
      conn =
        conn(:post, "/users/log-in")
        |> put_req_header("fly-client-ip", "203.0.113.7")
        |> put_req_header("x-forwarded-for", "1.2.3.4")

      assert RateLimit.client_ip(conn) == "203.0.113.7"
    end

    test "sem Fly-Client-IP, usa o último IP de X-Forwarded-For (o do proxy de borda)" do
      conn =
        conn(:post, "/users/log-in")
        |> put_req_header("x-forwarded-for", "198.51.100.9, 203.0.113.7")

      assert RateLimit.client_ip(conn) == "203.0.113.7"
    end

    test "sem headers de proxy, cai para o remote_ip" do
      conn = %{conn(:post, "/users/log-in") | remote_ip: {198, 51, 100, 23}}
      assert RateLimit.client_ip(conn) == "198.51.100.23"
    end

    test "clientes diferentes resolvem para IPs diferentes (buckets não colapsam)" do
      a = conn(:post, "/") |> put_req_header("fly-client-ip", "10.0.0.1")
      b = conn(:post, "/") |> put_req_header("fly-client-ip", "10.0.0.2")
      assert RateLimit.client_ip(a) != RateLimit.client_ip(b)
    end
  end
end
