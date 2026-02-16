defmodule Custo.Banking.AIAnalyzerTest do
  use Custo.DataCase, async: false

  alias Custo.Banking.AIAnalyzer

  describe "analyze_month/3" do
    test "returns error when no API key is configured" do
      original_config = Application.get_env(:custo, :gemini_api_key)
      original_env = System.get_env("GEMINI_API_KEY")

      Application.put_env(:custo, :gemini_api_key, nil)
      System.delete_env("GEMINI_API_KEY")

      on_exit(fn ->
        Application.put_env(:custo, :gemini_api_key, original_config)

        case original_env do
          nil -> :ok
          val -> System.put_env("GEMINI_API_KEY", val)
        end
      end)

      assert {:error, "GEMINI_API_KEY not configured"} =
               AIAnalyzer.analyze_month(0, 2025, 1)
    end
  end
end
