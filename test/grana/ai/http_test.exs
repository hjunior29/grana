defmodule Grana.AI.HTTPTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Grana.AI.HTTP

  test "get/3 returns the body, HTTP errors and friendly transport errors" do
    stub(Req, :get, fn _url, _opts -> {:ok, %Req.Response{status: 200, body: %{"data" => []}}} end)

    assert {:ok, %{"data" => []}} = HTTP.get("https://x", [])

    stub(Req, :get, fn _url, _opts -> {:ok, %Req.Response{status: 401, body: %{}}} end)
    assert {:http_error, 401, %{}} = HTTP.get("https://x", [])

    stub(Req, :get, fn _url, _opts -> {:error, %Req.TransportError{reason: :timeout}} end)
    assert {:error, "A requisição demorou demais" <> _} = HTTP.get("https://x", [])

    stub(Req, :get, fn _url, _opts -> {:error, %Req.TransportError{reason: :nxdomain}} end)
    assert {:error, "Não foi possível conectar" <> _} = HTTP.get("https://x", [])

    stub(Req, :get, fn _url, _opts -> {:error, :closed} end)
    assert {:error, "Falha na conexão" <> _} = HTTP.get("https://x", [])
  end

  test "friendly_error/3 explains each status" do
    assert HTTP.friendly_error(401, %{}, "OpenAI") =~ "Chave de API inválida para OpenAI"
    assert HTTP.friendly_error(403, %{}, "OpenAI") =~ "não tem permissão"

    assert HTTP.friendly_error(404, %{"error" => "no model"}, "X") =~
             "não encontrado em X: no model"

    assert HTTP.friendly_error(404, %{}, "X") =~ "não encontrado em X."
    assert HTTP.friendly_error(429, %{}, "X") =~ "Limite de requisições"
    assert HTTP.friendly_error(503, %{}, "X") =~ "X está indisponível"
    assert HTTP.friendly_error(418, %{"message" => "teapot"}, "X") == "Erro da API (418): teapot"
    assert HTTP.friendly_error(418, "?", "X") =~ "código 418"
  end

  test "message/1 reads the error of every provider format" do
    assert HTTP.message(%{"error" => %{"message" => "a"}}) == "a"
    assert HTTP.message(%{"error" => "b"}) == "b"
    assert HTTP.message(%{"message" => "c"}) == "c"
    assert HTTP.message(nil) == nil
  end
end
