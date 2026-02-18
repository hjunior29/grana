defmodule Granai.Banking.AIAnalyzerTest do
  use Granai.DataCase, async: false

  import Granai.AccountsFixtures

  alias Granai.Banking.AIAnalyzer

  describe "analyze_with_filters/3" do
    test "returns error when no API key is configured" do
      user = user_fixture()

      assert {:error, :no_api_key} =
               AIAnalyzer.analyze_with_filters(user.id, %{year: 2025, month: 1})
    end
  end
end
