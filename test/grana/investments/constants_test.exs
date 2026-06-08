defmodule Grana.Investments.ConstantsTest do
  use ExUnit.Case, async: true

  alias Grana.Investments.Constants

  describe "asset_types/0" do
    test "returns list containing expected asset types" do
      types = Constants.asset_types()
      assert is_list(types)
      assert "acao" in types
      assert "fii" in types
      assert "renda_fixa" in types
      assert "tesouro" in types
    end
  end

  describe "operations/0" do
    test "returns list containing expected operations" do
      ops = Constants.operations()
      assert is_list(ops)
      assert "compra" in ops
      assert "venda" in ops
      assert "dividendo" in ops
    end
  end

  describe "asset_type_label/1" do
    test "returns label for known type" do
      assert Constants.asset_type_label("acao") == "Ações"
      assert Constants.asset_type_label("fii") == "FII"
      assert Constants.asset_type_label("renda_fixa") == "Renda Fixa"
    end

    test "returns fallback for unknown type" do
      assert Constants.asset_type_label("unknown") == "—"
    end
  end

  describe "operation_label/1" do
    test "returns label for known operation" do
      assert Constants.operation_label("compra") == "Compra"
      assert Constants.operation_label("venda") == "Venda"
      assert Constants.operation_label("dividendo") == "Dividendo"
    end

    test "returns op itself for unknown operation" do
      assert Constants.operation_label("unknown_op") == "unknown_op"
    end
  end

  describe "asset_type_color/1" do
    test "returns hex color for known type" do
      color = Constants.asset_type_color("acao")
      assert color =~ ~r/^#[0-9A-Fa-f]{6}$/
    end

    test "returns default color for unknown type" do
      assert Constants.asset_type_color("unknown") == "#9CA3AF"
    end
  end

  describe "asset_type_badge/1" do
    test "returns badge class for known type" do
      assert Constants.asset_type_badge("acao") =~ "badge-"
    end

    test "returns ghost badge for unknown type" do
      assert Constants.asset_type_badge("unknown") == "badge-ghost"
    end
  end

  describe "sub-lists" do
    test "buy_sell_ops contains compra and venda" do
      ops = Constants.buy_sell_ops()
      assert "compra" in ops
      assert "venda" in ops
    end

    test "dividend_ops contains dividend operations" do
      ops = Constants.dividend_ops()
      assert "dividendo" in ops
      assert "jcp" in ops
    end

    test "income_ops_csv is a comma-separated string" do
      csv = Constants.income_ops_csv()
      assert is_binary(csv)
      assert String.contains?(csv, ",")
    end

    test "asset_colors returns map with hex values" do
      colors = Constants.asset_colors()
      assert is_map(colors)

      Enum.each(colors, fn {_type, color} ->
        assert color =~ ~r/^#/
      end)
    end
  end
end
