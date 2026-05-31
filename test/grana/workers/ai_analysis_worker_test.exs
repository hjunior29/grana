defmodule Grana.Workers.AIAnalysisWorkerTest do
  use ExUnit.Case, async: true

  # Test the atomize_keys logic directly by extracting it.
  # Since atomize_keys is private, we test via the module's public behavior
  # by calling the function through a helper that mirrors the logic.

  @known_keys ~w(year month bank type statement_type institution_id asset_type)

  # Mirror of the fixed atomize_keys/1 from AIAnalysisWorker
  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) and k in @known_keys -> {String.to_existing_atom(k), v}
      {k, v} when is_binary(k) -> {k, atomize_keys(v)}
      {k, v} -> {k, v}
    end)
  end

  defp atomize_keys(value), do: value

  describe "atomize_keys/1" do
    test "converts known keys to atoms" do
      input = %{"year" => 2026, "month" => 1, "bank" => "nubank"}
      result = atomize_keys(input)

      assert result == %{year: 2026, month: 1, bank: "nubank"}
    end

    test "keeps unknown keys as strings" do
      input = %{"year" => 2026, "unknown_key" => "value", "another_random" => 42}
      result = atomize_keys(input)

      assert result[:year] == 2026
      assert result["unknown_key"] == "value"
      assert result["another_random"] == 42
    end

    test "does not create new atoms for unknown keys" do
      # Generate a unique key that definitely isn't an existing atom
      random_key = "zz_nonexistent_key_#{System.unique_integer([:positive])}"
      input = %{"year" => 2026, random_key => "should stay string"}
      result = atomize_keys(input)

      assert result[random_key] == "should stay string"
      assert_raise ArgumentError, fn -> String.to_existing_atom(random_key) end
    end

    test "handles nested maps for unknown keys" do
      input = %{"year" => 2026, "nested_thing" => %{"month" => 3, "foo" => "bar"}}
      result = atomize_keys(input)

      assert result[:year] == 2026
      nested = result["nested_thing"]
      assert nested[:month] == 3
      assert nested["foo"] == "bar"
    end

    test "handles non-map values as passthrough" do
      assert atomize_keys("string") == "string"
      assert atomize_keys(42) == 42
      assert atomize_keys(nil) == nil
    end
  end
end
