defmodule Grana.AI.Providers.OpenAITest do
  use ExUnit.Case, async: false
  use Mimic

  alias Grana.AI.Providers.OpenAI

  @config %{
    provider: "openai",
    name: "OpenAI",
    api_key: "sk-test",
    model: "gpt-x",
    receive_timeout: 5_000
  }

  @ok %{
    "choices" => [%{"message" => %{"content" => "ok"}, "finish_reason" => "stop"}]
  }

  defp ok(body \\ @ok), do: {:ok, %Req.Response{status: 200, body: body}}

  defp err(status, message),
    do: {:ok, %Req.Response{status: status, body: %{"error" => %{"message" => message}}}}

  test "envia o prompt, a chave e os parâmetros no formato da OpenAI" do
    expect(Req, :post, fn url, opts ->
      assert url == "https://api.openai.com/v1/chat/completions"
      assert {"authorization", "Bearer sk-test"} in opts[:headers]
      assert opts[:receive_timeout] == 5_000

      assert %{
               "model" => "gpt-x",
               "messages" => [%{role: "user", content: "oi"}],
               "temperature" => 0.2,
               "max_completion_tokens" => 100
             } = opts[:json]

      ok()
    end)

    config = Map.merge(@config, %{temperature: 0.2, max_output_tokens: 100})
    assert {:ok, @ok} = OpenAI.generate_content("oi", config)
  end

  test "serviço compatível usa o base_url e max_tokens, e funciona sem chave" do
    expect(Req, :post, fn url, opts ->
      assert url == "http://localhost:11434/v1/chat/completions"
      assert opts[:headers] == []
      assert %{"max_tokens" => 50} = opts[:json]
      refute Map.has_key?(opts[:json], "max_completion_tokens")
      ok()
    end)

    config = %{
      provider: "openai_compatible",
      model: "llama3",
      api_key: nil,
      base_url: "http://localhost:11434/v1/",
      max_output_tokens: 50
    }

    assert {:ok, _} = OpenAI.generate_content("oi", config)
  end

  test "se a API recusa o temperature, refaz o pedido sem ele (modelos de raciocínio)" do
    expect(Req, :post, 2, fn _url, opts ->
      if Map.has_key?(opts[:json], "temperature"),
        do: err(400, "Unsupported value: 'temperature' does not support 0.1 with this model."),
        else: ok()
    end)

    assert {:ok, _} = OpenAI.generate_content("oi", Map.put(@config, :temperature, 0.1))
  end

  test "se a API pede max_completion_tokens, troca o nome do parâmetro" do
    expect(Req, :post, 2, fn _url, opts ->
      if Map.has_key?(opts[:json], "max_tokens") do
        err(400, "Unsupported parameter: 'max_tokens'. Use 'max_completion_tokens' instead.")
      else
        assert opts[:json]["max_completion_tokens"] == 10
        ok()
      end
    end)

    config = %{@config | provider: "openai_compatible"} |> Map.put(:max_output_tokens, 10)
    assert {:ok, _} = OpenAI.generate_content("oi", config)
  end

  test "erro 400 que não é de parâmetro vira mensagem da API" do
    stub(Req, :post, fn _url, _opts -> err(400, "context length exceeded") end)

    assert {:error, "Erro da API (400): context length exceeded"} =
             OpenAI.generate_content("oi", @config)
  end

  test "mensagens amigáveis para 401, 429 e 503" do
    stub(Req, :post, fn _url, _opts -> err(401, "bad key") end)
    assert {:error, msg} = OpenAI.generate_content("oi", @config)
    assert msg =~ "Chave de API inválida para OpenAI"

    stub(Req, :post, fn _url, _opts -> err(429, "slow down") end)
    assert {:error, msg} = OpenAI.generate_content("oi", @config)
    assert msg =~ "Limite de requisições"

    stub(Req, :post, fn _url, _opts -> err(503, "x") end)
    assert {:error, msg} = OpenAI.generate_content("oi", @config)
    assert msg =~ "indisponível"
  end

  test "timeout e conexão recusada" do
    stub(Req, :post, fn _url, _opts -> {:error, %Req.TransportError{reason: :timeout}} end)
    assert {:error, "A requisição demorou demais" <> _} = OpenAI.generate_content("oi", @config)

    stub(Req, :post, fn _url, _opts -> {:error, %Req.TransportError{reason: :econnrefused}} end)
    assert {:error, "Não foi possível conectar" <> _} = OpenAI.generate_content("oi", @config)

    stub(Req, :post, fn _url, _opts -> {:error, :boom} end)
    assert {:error, "Falha na conexão" <> _} = OpenAI.generate_content("oi", @config)
  end

  test "PDF vai como arquivo e imagem como image_url" do
    expect(Req, :post, 2, fn _url, opts ->
      [%{content: [%{type: "text", text: "extraia"}, attachment]}] = opts[:json]["messages"]
      send(self(), {:attachment, attachment})
      ok()
    end)

    OpenAI.generate_content_with_file("QUJD", "application/pdf", "extraia", @config)

    assert_received {:attachment,
                     %{type: "file", file: %{file_data: "data:application/pdf;base64,QUJD"}}}

    OpenAI.generate_content_with_file("QUJD", "image/png", "extraia", @config)

    assert_received {:attachment,
                     %{type: "image_url", image_url: %{url: "data:image/png;base64,QUJD"}}}
  end
end
