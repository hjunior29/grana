defmodule Grana.Banking.Parsers.BradescoFaturaTest do
  use ExUnit.Case, async: true

  alias Grana.Banking.Parsers.BradescoFatura

  test "parses fatura transactions" do
    csv = """
    Data: 15/02/2026 11:00:04\r\rSituação da Fatura: PAGO\r\rFULANO DE TAL ;;; 0000\r\rData;Histórico;Valor(US\$);Valor(R\$);\r\r05/02;TIMES OFFICE 1/3;0,00;156,00\r\r04/02;DROGASIL 1419 ;0,00;105,80\r\rTotal da fatura em Real: ;;;261,80
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
    Data: 15/02/2026 11:00:04\r\rSituação da Fatura: PAGO\r\rFULANO DE TAL ;;; 0000\r\rData;Histórico;Valor(US\$);Valor(R\$);\r\r02/02;DROGASIL 2515 ;0,00;226,49\r\rTotal da fatura em Real: ;;;226,49\r\rResumo das Despesas;Real\r\rSaldo Anterior;0,00;
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

  test "linhas negativas (pagamento de fatura e estornos) viram credit" do
    csv = """
    Data: 15/02/2026 11:00:04\r\rData;Histórico;Valor(US\$);Valor(R\$);\r\r10/02;PAGTO. POR DEB EM C/C;0,00;-1.500,00\r\r11/02;ESTORNO DE COMPRA;0,00;-89,90\r\r12/02;COMPRA NORMAL;0,00;50,00
    """

    result = BradescoFatura.parse(csv)
    assert length(result) == 3

    pagto = Enum.find(result, &(&1.description == "PAGTO. POR DEB EM C/C"))
    assert pagto.type == "credit"
    assert Decimal.compare(pagto.amount, Decimal.new("1500.00")) == :eq

    estorno = Enum.find(result, &(&1.description == "ESTORNO DE COMPRA"))
    assert estorno.type == "credit"
    assert Decimal.compare(estorno.amount, Decimal.new("89.90")) == :eq

    compra = Enum.find(result, &(&1.description == "COMPRA NORMAL"))
    assert compra.type == "debit"
    assert Decimal.compare(compra.amount, Decimal.new("-50.00")) == :eq
  end

  test "drops the previous bill's balance and keeps its payment as a credit" do
    csv = """
    Data: 18/10/2026 11:20:18\r\rSituação da Fatura: PAGO\r\rFULANO DE TAL ;;; 0000\r\rData;Histórico;Valor(US\$);Valor(R\$);\r\r01/06;SALDO ANTERIOR ;0,00;2875,60\r\r01/06;PAGTO. POR DEB EM C/C ;0,00;-2875,60\r\r01/06;RESTAURANTE EXEMPLO ;0,00;37,20
    """

    assert [payment, purchase] = BradescoFatura.parse(csv)
    assert payment.description == "PAGTO. POR DEB EM C/C"
    assert payment.type == "credit"
    assert Decimal.equal?(payment.amount, Decimal.new("2875.60"))
    assert purchase.type == "debit"
  end

  test "dates a purchase's later installment in the month it is charged, not its own charges" do
    csv = """
    Data: 18/10/2026 11:20:18\r\rData;Histórico;Valor(US\$);Valor(R\$);\r\r26/06;ANUIDADE DIFERENCIADA 5/12;0,00;98,00\r\r20/06;Clinica Exemplo 1/4;0,00;150,00\r\r18/02;LOJA EXEMPLO CENTRO 4/5;0,00;412,30\r\r27/06;ZP*BAR EXEMPLO ;0,00;47,00
    """

    assert csv |> BradescoFatura.parse() |> Map.new(&{&1.description, &1.date}) == %{
             "ANUIDADE DIFERENCIADA" => ~D[2026-06-26],
             "Clinica Exemplo" => ~D[2026-06-20],
             "LOJA EXEMPLO CENTRO" => ~D[2026-05-18],
             "ZP*BAR EXEMPLO" => ~D[2026-06-27]
           }
  end
end
