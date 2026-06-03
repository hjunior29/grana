defmodule Grana.Banking.Parsers.BradescoFaturaTest do
  use ExUnit.Case, async: true

  alias Grana.Banking.Parsers.BradescoFatura

  test "parses fatura transactions" do
    csv = """
    Data: 15/02/2026 11:00:04\r\rSituação da Fatura: PAGO\r\rHELDER JUNIOR ;;; 5976\r\rData;Histórico;Valor(US\$);Valor(R\$);\r\r05/02;TIMES OFFICE 1/3;0,00;156,00\r\r04/02;DROGASIL 1419 ;0,00;105,80\r\rTotal da fatura em Real: ;;;261,80
    """

    result = BradescoFatura.parse(csv)
    assert length(result) == 2
  end

  test "all transactions are debit" do
    csv = """
    Data: 15/02/2026 11:00:04\r\rData;Histórico;Valor(US\$);Valor(R\$);\r\r02/02;FITNESS LAND ;0,00;120,00\r\r02/02;DROGASIL 2515 ;0,00;226,49
    """

    result = BradescoFatura.parse(csv)
    assert Enum.all?(result, &(&1.type == "debit"))
    assert Enum.all?(result, fn txn -> Decimal.compare(txn.amount, 0) == :lt end)
  end

  test "extracts year from header" do
    csv = """
    Data: 15/02/2026 11:00:04\r\rData;Histórico;Valor(US\$);Valor(R\$);\r\r04/02;OBSIDIAN ;5,00;27,55
    """

    [txn] = BradescoFatura.parse(csv)
    assert txn.date == ~D[2026-02-04]
  end

  test "skips summary and metadata lines" do
    csv = """
    Data: 15/02/2026 11:00:04\r\rSituação da Fatura: PAGO\r\rHELDER JUNIOR ;;; 5976\r\rData;Histórico;Valor(US\$);Valor(R\$);\r\r02/02;DROGASIL 2515 ;0,00;226,49\r\rTotal da fatura em Real: ;;;226,49\r\rResumo das Despesas;Real\r\rSaldo Anterior;0,00;
    """

    result = BradescoFatura.parse(csv)
    assert length(result) == 1
    assert hd(result).description == "DROGASIL 2515"
  end

  test "parses full example file" do
    content = File.read!("test/support/fixtures/examples/fatura-bradesco.csv")
    result = BradescoFatura.parse(content)
    assert length(result) == 6
    assert Enum.all?(result, &(&1.date != nil))
    assert Enum.all?(result, &(&1.amount != nil))
    assert Enum.all?(result, &(&1.type == "debit"))
  end

  test "handles latin-1 encoded files" do
    content = File.read!("test/support/fixtures/examples/fatura-bradesco.csv")
    refute String.valid?(content)
    result = BradescoFatura.parse(content)
    assert result != []
  end

  test "lançamento de dezembro em fatura de fevereiro fica no ano anterior" do
    # Cabeçalho da fatura: 15/02/2026 (mês de referência = fevereiro)
    csv = """
    Data: 15/02/2026 11:00:04\r\rData;Histórico;Valor(US\$);Valor(R\$);\r\r20/12;COMPRA DE DEZEMBRO ;0,00;100,00\r\r04/02;COMPRA DE FEVEREIRO ;0,00;50,00
    """

    result = BradescoFatura.parse(csv)
    dez = Enum.find(result, &String.contains?(&1.description, "DEZEMBRO"))
    fev = Enum.find(result, &String.contains?(&1.description, "FEVEREIRO"))

    # Dezembro (mês 12 > 2) cai no ano anterior; fevereiro fica no ano da fatura.
    assert dez.date == ~D[2025-12-20]
    assert fev.date == ~D[2026-02-04]
  end
end
