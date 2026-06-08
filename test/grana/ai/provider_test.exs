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
