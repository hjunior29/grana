defmodule Grana.Investments.TransactionTest do
  use ExUnit.Case, async: true

  alias Grana.Investments.Transaction

  describe "asset_types/0 and operations/0 delegates" do
    test "asset_types/0 delegates to Constants" do
      types = Transaction.asset_types()
      assert is_list(types)
      assert "acao" in types
    end

    test "operations/0 delegates to Constants" do
      ops = Transaction.operations()
      assert is_list(ops)
      assert "compra" in ops
    end
  end
end
