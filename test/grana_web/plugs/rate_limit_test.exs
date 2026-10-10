defmodule GranaWeb.RateLimitTest do
  use ExUnit.Case, async: false

  import Plug.Test
  import Plug.Conn

  alias GranaWeb.RateLimit

  setup do
    on_exit(fn -> Application.delete_env(:grana, :trust_proxy_headers) end)
  end

  describe "client_ip/1" do
    test "usa o remote_ip por padrão e ignora X-Forwarded-For e Fly-Client-IP" do
      conn =
        %{conn(:post, "/users/log-in") | remote_ip: {198, 51, 100, 23}}
        |> put_req_header("x-forwarded-for", "1.2.3.4")
        |> put_req_header("fly-client-ip", "5.6.7.8")

      assert RateLimit.client_ip(conn) == "198.51.100.23"
    end

    test "com TRUST_PROXY_HEADERS usa o último IP de X-Forwarded-For" do
      Application.put_env(:grana, :trust_proxy_headers, true)

      conn =
        conn(:post, "/users/log-in")
        |> put_req_header("x-forwarded-for", "198.51.100.9, 203.0.113.7")

      assert RateLimit.client_ip(conn) == "203.0.113.7"
    end

    test "com TRUST_PROXY_HEADERS mas sem o header, cai para o remote_ip" do
      Application.put_env(:grana, :trust_proxy_headers, true)
      conn = %{conn(:post, "/") | remote_ip: {10, 0, 0, 1}}
      assert RateLimit.client_ip(conn) == "10.0.0.1"
    end
  end
end
