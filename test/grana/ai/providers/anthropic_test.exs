defmodule Grana.AI.Providers.AnthropicTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Grana.AI.Providers.Anthropic

  @config %{provider: "anthropic", name: "Claude", api_key: "sk-ant", model: "claude-x"}

  @ok %{"content" => [%{"type" => "text", "text" => "ok"}], "stop_reason" => "end_turn"}

  defp ok, do: {:ok, %Req.Response{status: 200, body: @ok}}

  defp err(status, message),
    do: {:ok, %Req.Response{status: status, body: %{"error" => %{"message" => message}}}}

  test "envia chave, versão e mensagem no formato da Anthropic" do
    expect(Req, :post, fn url, opts ->
      assert url == "https://api.anthropic.com/v1/messages"
      assert {"x-api-key", "sk-ant"} in opts[:headers]
      assert {"anthropic-version", "2023-06-01"} in opts[:headers]

      assert %{
               "model" => "claude-x",
               "max_tokens" => 2048,
               "temperature" => 0.3,
               "messages" => [%{role: "user", content: [%{type: "text", text: "oi"}]}]
             } = opts[:json]

      ok()
    end)

    config = Map.merge(@config, %{temperature: 0.3, max_output_tokens: 2048})
    assert {:ok, @ok} = Anthropic.generate_content("oi", config)
  end

  test "usa um max_tokens padrão quando o chamador não define" do
    expect(Req, :post, fn _url, opts ->
      assert opts[:json]["max_tokens"] == 8192
      ok()
    end)

    Anthropic.generate_content("oi", @config)
  end

  test "remove o temperature se o modelo o recusar" do
    expect(Req, :post, 2, fn _url, opts ->
      if Map.has_key?(opts[:json], "temperature"),
        do: err(400, "`temperature` is deprecated for this model."),
        else: ok()
    end)

    assert {:ok, _} = Anthropic.generate_content("oi", Map.put(@config, :temperature, 0.5))
  end

  test "PDF vira bloco document e imagem vira bloco image" do
    expect(Req, :post, 2, fn _url, opts ->
      [%{content: [attachment, %{type: "text"}]}] = opts[:json]["messages"]
      send(self(), {:attachment, attachment})
      ok()
    end)

    Anthropic.generate_content_with_file("QUJD", "application/pdf", "extraia", @config)

    assert_received {:attachment,
                     %{
                       type: "document",
                       source: %{type: "base64", media_type: "application/pdf", data: "QUJD"}
                     }}

    Anthropic.generate_content_with_file("QUJD", "image/png", "extraia", @config)
    assert_received {:attachment, %{type: "image"}}
  end

  test "erros viram mensagens amigáveis" do
    stub(Req, :post, fn _url, _opts -> err(401, "invalid x-api-key") end)
    assert {:error, msg} = Anthropic.generate_content("oi", @config)
    assert msg =~ "Chave de API inválida para Claude"

    stub(Req, :post, fn _url, _opts -> err(529, "overloaded") end)
    assert {:error, msg} = Anthropic.generate_content("oi", @config)
    assert msg =~ "indisponível"

    stub(Req, :post, fn _url, _opts -> err(400, "prompt is too long") end)

    assert {:error, "Erro da API (400): prompt is too long"} =
             Anthropic.generate_content("oi", @config)

    stub(Req, :post, fn _url, _opts -> {:error, %Req.TransportError{reason: :timeout}} end)

    assert {:error, "A requisição demorou demais" <> _} =
             Anthropic.generate_content("oi", @config)
  end
end
