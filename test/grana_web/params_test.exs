defmodule GranaWeb.ParamsTest do
  use ExUnit.Case, async: true

  alias GranaWeb.Params

  describe "to_int/2" do
    test "returns integer as-is" do
      assert Params.to_int(42) == 42
      assert Params.to_int(0) == 0
      assert Params.to_int(-5) == -5
    end

    test "parses valid integer string" do
      assert Params.to_int("123") == 123
      assert Params.to_int("0") == 0
      assert Params.to_int("-10") == -10
    end

    test "returns default for invalid string" do
      assert Params.to_int("abc", -1) == -1
      assert Params.to_int("", -1) == -1
      assert Params.to_int("1.5", -1) == 1
    end

    test "returns nil by default for invalid input" do
      assert Params.to_int("invalid") == nil
    end

    test "parses string with trailing non-digit chars" do
      assert Params.to_int("42px") == 42
    end

    test "handles atom input" do
      assert Params.to_int(:foo, -1) == -1
    end
  end
end
