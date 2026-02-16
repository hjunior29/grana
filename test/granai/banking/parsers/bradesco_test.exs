defmodule Granai.Banking.Parsers.BradescoTest do
  use ExUnit.Case, async: true

  alias Granai.Banking.Parsers.Bradesco

  @sample_csv """
  Extrato de: Ag: 1234 | Conta: 98765-4;;;;;
  Data;Histórico;Docto.;Crédito (R$);Débito (R$);Saldo (R$)
  05/02/2026;COD. LANC. 0;0;0,00; ;15.871,37
  06/02/2026;PGTO DE RENDIMENTO - B3*;8162;19,00; ;15.890,37
  06/02/2026;PIX QR CODE DINAMICO;1332274; ;60,00;15.830,39
  ;;;;;
  Filtro de resultados;;;;;
  """

  test "parses valid CSV content" do
    result = Bradesco.parse(@sample_csv)
    assert length(result) == 3
  end

  test "parses date correctly" do
    [_, second | _] = Bradesco.parse(@sample_csv)
    assert second.date == ~D[2026-02-06]
  end

  test "parses credit amount" do
    [_, credit | _] = Bradesco.parse(@sample_csv)
    assert credit.type == "credit"
    assert Decimal.compare(credit.amount, Decimal.new("19.00")) == :eq
  end

  test "filters metadata lines" do
    result = Bradesco.parse(@sample_csv)
    descriptions = Enum.map(result, & &1.description)
    refute Enum.any?(descriptions, &String.contains?(&1, "Filtro"))
    refute Enum.any?(descriptions, &String.contains?(&1, "Extrato"))
  end

  test "handles empty content" do
    csv = "Header;;;;;;\nData;Histórico;Docto.;Crédito;Débito;Saldo\n;;;;;;\n"
    assert Bradesco.parse(csv) == []
  end

  test "parses Brazilian number format" do
    csv = """
    Header;;;;;
    Data;Histórico;Docto.;Crédito (R$);Débito (R$);Saldo (R$)
    09/02/2026;PAGTO ELETRON  COBRANCA;8; ;4.612,79;11.093,68
    """

    [txn] = Bradesco.parse(csv)
    assert txn.type == "debit"
    assert Decimal.compare(Decimal.abs(txn.amount), Decimal.new("4612.79")) == :eq
  end

  test "parses full example file" do
    content = File.read!("priv/examples/extrato-bradesco.csv")
    result = Bradesco.parse(content)
    assert length(result) > 0
    assert Enum.all?(result, &(&1.date != nil))
    assert Enum.all?(result, &(&1.amount != nil))
  end
end
