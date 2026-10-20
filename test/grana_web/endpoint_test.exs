defmodule GranaWeb.EndpointTest do
  # Changes the endpoint config and the proxy trust for the whole node.
  use GranaWeb.ConnCase, async: false

  @moduletag :capture_log

  @endpoint GranaWeb.Endpoint

  setup do
    config = Application.get_env(:grana, @endpoint)
    @endpoint.config_change([{@endpoint, Keyword.put(config, :check_origin, :conn)}], [])
    Application.put_env(:grana, :trust_proxy_headers, true)

    on_exit(fn ->
      Application.delete_env(:grana, :trust_proxy_headers)
      @endpoint.config_change([{@endpoint, config}], [])
    end)
  end

  defp longpoll(conn, origin, headers) do
    headers
    |> Enum.reduce(conn, fn {name, value}, conn -> put_req_header(conn, name, value) end)
    |> put_req_header("origin", origin)
    |> Map.put(:host, "grana.example.com")
    |> get("/live/longpoll?vsn=2.0.0")
    |> json_response(200)
  end

  test "LiveView connects behind an HTTPS proxy and on the local network", %{conn: conn} do
    behind_proxy = longpoll(conn, "https://grana.example.com", [{"x-forwarded-proto", "https"}])
    assert behind_proxy["status"] == 410

    local_network = longpoll(build_conn(), "http://grana.example.com", [])
    assert local_network["status"] == 410
  end

  test "a page from another origin still cannot open the socket", %{conn: conn} do
    other = longpoll(conn, "https://evil.example.com", [{"x-forwarded-proto", "https"}])
    assert other["status"] == 403
  end
end
