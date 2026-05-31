defmodule Grana.Investments.ParsersTest do
  use ExUnit.Case, async: true

  alias Grana.Investments.Parsers.{B3Xlsx, GcbCsv, GenericCsv}
  alias Grana.Investments.Constants

  defp assert_valid_transactions(transactions) do
    assert is_list(transactions)
    assert transactions != []

    for t <- transactions do
      assert match?(%Date{}, t.date)
      assert t.operation in Constants.operations()
      assert match?(%Decimal{}, t.total_amount)
      assert is_binary(t.asset_name) or is_nil(t.asset_name)
    end
  end

  describe "B3Xlsx.parse/1" do
    test "parseia o XLSX de exemplo da B3" do
      content = File.read!("priv/examples/extrato-b3.xlsx")
      assert {transactions, warnings} = B3Xlsx.parse(content)
      assert is_list(warnings)
      assert_valid_transactions(transactions)
    end

    test "conteúdo inválido não derruba o processo" do
      assert {:error, _reason} = B3Xlsx.parse("isto não é um xlsx")
    end
  end

  describe "GcbCsv.parse/1" do
    test "parseia o CSV de exemplo da GCB" do
      content = File.read!("priv/examples/extrato-gcb.csv")
      assert {transactions, warnings} = GcbCsv.parse(content)
      assert is_list(warnings)
      assert_valid_transactions(transactions)
    end
  end

  describe "GenericCsv.parse/1" do
    test "detecta colunas e parseia um CSV genérico (data; ativo; valor)" do
      csv = """
      data;ativo;valor
      10/01/2026;PETR4;-1.000,00
      11/01/2026;HGLG11;500,00
      """

      assert {transactions, warnings} = GenericCsv.parse(csv)
      assert is_list(warnings)
      assert length(transactions) == 2
      assert Enum.all?(transactions, &match?(%Decimal{}, &1.total_amount))
      assert Enum.all?(transactions, &(&1.operation in Constants.operations()))
    end

    test "CSV sem colunas reconhecíveis retorna erro" do
      assert {:error, _msg} = GenericCsv.parse("foo;bar\n1;2")
    end
  end
end
