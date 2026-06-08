defmodule Grana.AI.Providers.GeminiTest do
  use ExUnit.Case, async: false

  use Mimic

  alias Grana.AI.Providers.Gemini

  @config %{
    provider: "gemini",
    api_key: "test-key",
    model: "gemini-1.5-flash",
    receive_timeout: 5_000
  }

  @ok_body %{
    "candidates" => [
      %{"content" => %{"parts" => [%{"text" => "Análise ok"}]}, "finishReason" => "STOP"}
    ]
  }

  describe "generate_content/2" do
    test "returns ok on successful 200 response" do
      stub(Req, :post, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: @ok_body}}
      end)

      assert {:ok, body} = Gemini.generate_content("prompt", @config)
      assert get_in(body, ["candidates", Access.at(0), "finishReason"]) == "STOP"
    end

    test "returns friendly error on 400 INVALID_ARGUMENT" do
      stub(Req, :post, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 400,
           body: %{"error" => %{"status" => "INVALID_ARGUMENT"}}
         }}
      end)

      assert {:error, msg} = Gemini.generate_content("prompt", @config)
      assert msg =~ "API Key inválida"
    end

    test "returns friendly error on 403" do
      stub(Req, :post, fn _url, _opts ->
        {:ok, %Req.Response{status: 403, body: %{}}}
      end)

      assert {:error, msg} = Gemini.generate_content("prompt", @config)
      assert msg =~ "permissão"
    end

    test "returns friendly error on 429" do
      stub(Req, :post, fn _url, _opts ->
        {:ok, %Req.Response{status: 429, body: %{}}}
      end)

      assert {:error, msg} = Gemini.generate_content("prompt", @config)
      assert msg =~ "Limite"
    end

    test "returns friendly error on 500" do
      stub(Req, :post, fn _url, _opts ->
        {:ok, %Req.Response{status: 500, body: %{}}}
      end)

      assert {:error, msg} = Gemini.generate_content("prompt", @config)
      assert msg =~ "interno"
    end

    test "returns friendly error on 503" do
      stub(Req, :post, fn _url, _opts ->
        {:ok, %Req.Response{status: 503, body: %{}}}
      end)

      assert {:error, msg} = Gemini.generate_content("prompt", @config)
      assert msg =~ "indisponível"
    end

    test "returns friendly error on generic non-200 with message" do
      stub(Req, :post, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 422,
           body: %{"error" => %{"message" => "Content blocked"}}
         }}
      end)

      assert {:error, msg} = Gemini.generate_content("prompt", @config)
      assert msg =~ "422"
      assert msg =~ "Content blocked"
    end

    test "returns timeout error" do
      stub(Req, :post, fn _url, _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      assert {:error, msg} = Gemini.generate_content("prompt", @config)
      assert msg =~ "demorou demais"
    end

    test "returns connection refused error" do
      stub(Req, :post, fn _url, _opts ->
        {:error, %Req.TransportError{reason: :econnrefused}}
      end)

      assert {:error, msg} = Gemini.generate_content("prompt", @config)
      assert msg =~ "conectar"
    end

    test "returns generic connection error" do
      stub(Req, :post, fn _url, _opts ->
        {:error, %Req.TransportError{reason: :closed}}
      end)

      assert {:error, msg} = Gemini.generate_content("prompt", @config)
      assert msg =~ "Falha na conexão"
    end
  end

  describe "generate_content_with_file/4" do
    test "returns ok on successful 200 response" do
      stub(Req, :post, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: @ok_body}}
      end)

      assert {:ok, _body} =
               Gemini.generate_content_with_file(
                 Base.encode64("pdf-bytes"),
                 "application/pdf",
                 "analise este extrato",
                 @config
               )
    end

    test "returns error on API failure" do
      stub(Req, :post, fn _url, _opts ->
        {:ok, %Req.Response{status: 500, body: %{}}}
      end)

      assert {:error, _msg} =
               Gemini.generate_content_with_file(
                 Base.encode64("pdf-bytes"),
                 "application/pdf",
                 "analise este extrato",
                 @config
               )
    end
  end
end
