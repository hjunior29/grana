defmodule Grana.AI.ProviderTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Grana.AI.Provider

  describe "extract_text/1" do
    test "extracts text from well-formed response" do
      body = %{
        "candidates" => [
          %{"content" => %{"parts" => [%{"text" => "Resposta da IA"}]}}
        ]
      }

      assert Provider.extract_text(body) == "Resposta da IA"
    end

    test "returns empty string when candidates is empty" do
      assert Provider.extract_text(%{"candidates" => []}) == ""
    end

    test "returns empty string when body is empty map" do
      assert Provider.extract_text(%{}) == ""
    end

    test "returns empty string when text is nil" do
      body = %{
        "candidates" => [%{"content" => %{"parts" => [%{"text" => nil}]}}]
      }

      assert Provider.extract_text(body) == ""
    end
  end

  describe "extract_text/1 em outros formatos" do
    test "OpenAI e compatíveis" do
      assert Provider.extract_text(%{"choices" => [%{"message" => %{"content" => "oi"}}]}) == "oi"

      parts = [%{"type" => "text", "text" => "a"}, %{"type" => "x"}, %{"text" => "b"}]

      assert Provider.extract_text(%{"choices" => [%{"message" => %{"content" => parts}}]}) ==
               "ab"

      assert Provider.extract_text(%{"choices" => [%{"message" => %{"content" => nil}}]}) == ""
    end

    test "Anthropic junta os blocos de texto" do
      body = %{
        "content" => [%{"type" => "text", "text" => "um "}, %{"type" => "text", "text" => "dois"}]
      }

      assert Provider.extract_text(body) == "um dois"
    end
  end

  describe "finish_reason/1 normalizado" do
    test "OpenAI e Anthropic usam o vocabulário do Gemini" do
      assert Provider.finish_reason(%{"choices" => [%{"finish_reason" => "stop"}]}) == "STOP"

      assert Provider.finish_reason(%{"choices" => [%{"finish_reason" => "length"}]}) ==
               "MAX_TOKENS"

      assert Provider.finish_reason(%{"choices" => [%{"finish_reason" => "content_filter"}]}) ==
               "SAFETY"

      assert Provider.finish_reason(%{"choices" => [%{"finish_reason" => "tool_calls"}]}) ==
               "TOOL_CALLS"

      assert Provider.finish_reason(%{"choices" => [%{"finish_reason" => nil}]}) == nil
      assert Provider.finish_reason(%{"stop_reason" => "end_turn"}) == "STOP"
      assert Provider.finish_reason(%{"stop_reason" => "max_tokens"}) == "MAX_TOKENS"
    end
  end

  describe "delegação por tipo" do
    test "openai, openai_compatible e anthropic vão para o módulo certo" do
      stub(Grana.AI.Providers.OpenAI, :generate_content, fn _p, config ->
        {:ok, {:openai, config.provider}}
      end)

      stub(Grana.AI.Providers.Anthropic, :generate_content_with_file, fn _b, _m, _p, _c ->
        {:ok, :anthropic_file}
      end)

      assert {:ok, {:openai, "openai"}} = Provider.generate_content("p", %{provider: "openai"})

      assert {:ok, {:openai, "openai_compatible"}} =
               Provider.generate_content("p", %{provider: "openai_compatible"})

      assert {:ok, :anthropic_file} =
               Provider.generate_content_with_file("b", "application/pdf", "p", %{
                 provider: "anthropic"
               })
    end
  end

  describe "finish_reason/1" do
    test "returns the finish reason when present" do
      body = %{"candidates" => [%{"finishReason" => "STOP"}]}
      assert Provider.finish_reason(body) == "STOP"
    end

    test "returns MAX_TOKENS when truncated" do
      body = %{"candidates" => [%{"finishReason" => "MAX_TOKENS"}]}
      assert Provider.finish_reason(body) == "MAX_TOKENS"
    end

    test "returns nil when finish reason is absent" do
      assert Provider.finish_reason(%{"candidates" => [%{}]}) == nil
      assert Provider.finish_reason(%{}) == nil
    end
  end

  describe "generate_content/2 delegation" do
    test "delegates to Gemini when provider is gemini" do
      stub(Grana.AI.Providers.Gemini, :generate_content, fn _prompt, _config ->
        {:ok, %{"candidates" => [%{"content" => %{"parts" => [%{"text" => "ok"}]}}]}}
      end)

      config = %{provider: "gemini", api_key: "key", model: "gemini-1.5-flash"}
      assert {:ok, _} = Provider.generate_content("prompt", config)
    end
  end
end
