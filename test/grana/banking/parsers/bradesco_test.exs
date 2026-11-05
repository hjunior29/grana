defmodule Grana.Banking.Parsers.BradescoTest do
  use ExUnit.Case, async: true

  alias Grana.Banking.Parsers.Bradesco

  @sample_csv """
  Extrato de: Ag: 1234 | Conta: 98765-4;;;;;
  Data;Histórico;Docto.;Crédito (R$);Débito (R$);Saldo (R$)
  05/02/2026;COD. LANC. 0;0;0,00; ;14.284,23
  06/02/2026;PGTO DE RENDIMENTO - B3*;8162;17,00; ;14.301,23
  06/02/2026;PIX QR CODE DINAMICO;2000111; ;50,00;14.251,23
  ;;;;;
  Filtro de resultados;;;;;
  """

  test "parses valid CSV content and ignores zero-value lines" do
    result = Bradesco.parse(@sample_csv)
    assert length(result) == 2
  end

  test "parses date correctly" do
    [first | _] = Bradesco.parse(@sample_csv)
    assert first.date == ~D[2026-02-06]
  end

  test "parses credit amount" do
    [credit | _] = Bradesco.parse(@sample_csv)
    assert credit.type == "credit"
    assert Decimal.compare(credit.amount, Decimal.new("17.00")) == :eq
  end

  test "parses row with both credit and debit into two transactions" do
    csv = """
    Header;;;;;
    Data;Histórico;Docto.;Crédito (R$);Débito (R$);Saldo (R$)
    09/02/2026;TRANSFERENCIA MISTA;101;100,00;50,00;10.000,00
    """

    [credit, debit] = Bradesco.parse(csv)
    assert credit.type == "credit"
    assert Decimal.compare(credit.amount, Decimal.new("100.00")) == :eq
    assert debit.type == "debit"
    assert Decimal.compare(debit.amount, Decimal.new("-50.00")) == :eq
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
    09/02/2026;PAGTO ELETRON  COBRANCA;8; ;4.105,38;10.195,85
    """

    [txn] = Bradesco.parse(csv)
    assert txn.type == "debit"
    assert Decimal.compare(Decimal.abs(txn.amount), Decimal.new("4105.38")) == :eq
  end

  test "parses full example file" do
    content = File.read!("test/support/fixtures/examples/extrato-bradesco.csv")
    result = Bradesco.parse(content)
    assert result != []
    assert Enum.all?(result, &(&1.date != nil))
    assert Enum.all?(result, &(&1.amount != nil))
  end
end
