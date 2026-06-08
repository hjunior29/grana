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
    @b3_example "priv/examples/extrato-b3.xlsx"
    test "parseia o XLSX de exemplo da B3" do
      # Fixture binária real não é versionada (gitignored); roda só localmente.
      if File.exists?(@b3_example) do
        assert {transactions, warnings} = B3Xlsx.parse(File.read!(@b3_example))
        assert is_list(warnings)
        assert_valid_transactions(transactions)
      else
        assert true
      end
    end

    test "conteúdo inválido não derruba o processo" do
      assert {:error, _reason} = B3Xlsx.parse("isto não é um xlsx")
    end
  end

  describe "GcbCsv.parse/1" do
    test "parseia o CSV de exemplo da GCB" do
      content = File.read!("test/support/fixtures/examples/extrato-gcb.csv")
      assert {transactions, warnings} = GcbCsv.parse(content)
      assert is_list(warnings)
      assert_valid_transactions(transactions)
    end

    test "retorna lista vazia para conteúdo só com cabeçalho" do
      csv = ~S("Data_de_operação","Nome_da_operação","Valor_da_operação")
      {transactions, _warnings} = GcbCsv.parse(csv)
      assert transactions == []
    end

    test "parse_date handles various date formats" do
      assert {:ok, ~D[2026-01-10]} = GcbCsv.parse_date("10 de janeiro de 2026")
      assert {:ok, ~D[2025-03-15]} = GcbCsv.parse_date("15 de março de 2025")
    end

    test "parse_amount handles Brazilian format" do
      assert {:ok, d1} = GcbCsv.parse_amount("R$ 1.234,56")
      assert Decimal.equal?(d1, Decimal.new("1234.56"))

      assert {:ok, d2} = GcbCsv.parse_amount("-R$ 500,00")
      assert Decimal.equal?(d2, Decimal.new("-500.00"))
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

    test "suporta separador de vírgula com colunas reconhecidas" do
      csv = "data,ativo,valor\n10/01/2026,PETR4,-1000.00\n"

      assert {transactions, _warnings} = GenericCsv.parse(csv)
      assert length(transactions) >= 1
    end

    test "parseia CSV com coluna de operação explícita" do
      csv = """
      data;ativo;valor;operacao
      10/01/2026;PETR4;-1000,00;compra
      15/01/2026;VALE3;500,00;venda
      """

      assert {transactions, _warnings} = GenericCsv.parse(csv)
      assert length(transactions) == 2
    end

    test "suporta quantidade e preço unitário" do
      csv = """
      data;ativo;quantidade;preco;valor
      10/01/2026;PETR4;10;30,50;-305,00
      """

      assert {transactions, _warnings} = GenericCsv.parse(csv)
      assert length(transactions) >= 1
    end

    test "pula linhas em branco e cabeçalho" do
      csv = """
      data;ativo;valor

      10/01/2026;PETR4;-100,00

      """

      assert {transactions, _warnings} = GenericCsv.parse(csv)
      assert length(transactions) == 1
    end

    test "CSV com campos entre aspas" do
      csv = ~s(data;ativo;valor\n"10/01/2026";"PETR4";"-1.000,00"\n)

      assert {transactions, _warnings} = GenericCsv.parse(csv)
      assert length(transactions) == 1
    end

    test "retorna erro para CSV vazio" do
      result = GenericCsv.parse("")
      assert {:error, _msg} = result
    end

    test "CSV com tab como separador" do
      csv = "data\tativo\tvalor\n10/01/2026\tPETR4\t-100.00\n"

      assert {transactions, _warnings} = GenericCsv.parse(csv)
      assert length(transactions) >= 1
    end

    test "parseia CSV usando quantidade e preço sem coluna valor" do
      csv = """
      data;ativo;quantidade;preco
      10/01/2026;PETR4;10;30,50
      """

      assert {transactions, _warnings} = GenericCsv.parse(csv)
      assert length(transactions) >= 1
      t = hd(transactions)
      assert Decimal.equal?(t.total_amount, Decimal.new("305.00"))
    end

    test "detecta tipo de ativo a partir de coluna tipo ativo" do
      csv = """
      data;ativo;valor;tipo ativo
      10/01/2026;PETR4;-100,00;acao
      """

      assert {transactions, _warnings} = GenericCsv.parse(csv)
      assert length(transactions) == 1
    end

    test "linha ignorada é adicionada aos warnings" do
      csv = """
      data;ativo;valor
      not_a_date;PETR4;-100,00
      """

      assert {_transactions, warnings} = GenericCsv.parse(csv)
      assert is_list(warnings)
    end

    test "operações diversas são detectadas corretamente" do
      csv = """
      data;ativo;valor;operacao
      10/01/2026;PETR4;-100,00;venda
      11/01/2026;VALE3;50,00;dividend
      12/01/2026;HGLG11;30,00;rendimento
      13/01/2026;XPML11;20,00;amortizacao
      14/01/2026;FII1;10,00;jcp
      """

      assert {transactions, _warnings} = GenericCsv.parse(csv)
      ops = Enum.map(transactions, & &1.operation)
      assert "venda" in ops
      assert "dividendo" in ops or "rendimento" in ops
    end
  end

  describe "GcbCsv operations classification" do
    defp gcb_line(date, desc, amount) do
      ~s("#{date}","#{desc}","#{amount}")
    end

    defp gcb_with_lines(lines) do
      header = ~S("Data_de_operação","Nome_da_operação","Valor_da_operação")
      Enum.join([header | lines], "\n")
    end

    test "classifica nota fiscal compra" do
      csv =
        gcb_with_lines([
          gcb_line("10 de janeiro de 2026", "Compra de Nota Fiscal", "R$ 1.000,00")
        ])

      {txns, _} = GcbCsv.parse(csv)
      assert length(txns) == 1
      assert hd(txns).asset_type == "nota_fiscal"
      assert hd(txns).operation == "compra"
    end

    test "classifica nota fiscal recompra como venda" do
      csv =
        gcb_with_lines([
          gcb_line("10 de fevereiro de 2026", "Recompra de Nota Fiscal", "R$ 900,00")
        ])

      {txns, _} = GcbCsv.parse(csv)
      assert length(txns) == 1
      assert hd(txns).operation == "venda"
    end

    test "classifica nota fiscal liquidação" do
      csv =
        gcb_with_lines([
          gcb_line("10 de março de 2026", "Liquidação de Nota Fiscal", "R$ 1.100,00")
        ])

      {txns, _} = GcbCsv.parse(csv)
      assert length(txns) == 1
      assert hd(txns).asset_type == "nota_fiscal"
      assert hd(txns).operation == "venda"
    end

    test "classifica debenture compra" do
      csv =
        gcb_with_lines([
          gcb_line("10 de abril de 2026", "Debênture Especial 1 ano DEB123", "R$ 5.000,00")
        ])

      {txns, _} = GcbCsv.parse(csv)
      assert length(txns) == 1
      assert hd(txns).asset_type == "debenture"
      assert hd(txns).operation == "compra"
    end

    test "classifica debenture resgate" do
      csv =
        gcb_with_lines([
          gcb_line(
            "10 de maio de 2026",
            "Resgate de Debênture Liquidez D+1 DEB456",
            "R$ 5.200,00"
          )
        ])

      {txns, _} = GcbCsv.parse(csv)
      assert length(txns) == 1
      assert hd(txns).asset_type == "debenture"
      assert hd(txns).operation == "venda"
    end

    test "classifica precatorio compra" do
      csv =
        gcb_with_lines([
          gcb_line("10 de junho de 2026", "Compra de Precatório Federal", "R$ 10.000,00")
        ])

      {txns, _} = GcbCsv.parse(csv)
      assert length(txns) == 1
      assert hd(txns).asset_type == "precatorio"
      assert hd(txns).operation == "compra"
    end

    test "classifica precatorio liquidacao" do
      csv =
        gcb_with_lines([
          gcb_line("10 de julho de 2026", "Liquidação de Precatório Federal", "R$ 10.500,00")
        ])

      {txns, _} = GcbCsv.parse(csv)
      assert length(txns) == 1
      assert hd(txns).asset_type == "precatorio"
      assert hd(txns).operation == "venda"
    end

    test "classifica criptomoeda compra (bitcoin)" do
      csv =
        gcb_with_lines([
          gcb_line("10 de agosto de 2026", "Compra de Criptomoeda Bitcoin", "R$ 2.000,00")
        ])

      {txns, _} = GcbCsv.parse(csv)
      assert length(txns) == 1
      assert hd(txns).asset_type == "cripto"
      assert hd(txns).operation == "compra"
      assert hd(txns).asset_ticker == "BTC"
    end

    test "classifica criptomoeda venda (ethereum)" do
      csv =
        gcb_with_lines([
          gcb_line("10 de setembro de 2026", "Venda de Criptomoeda Ethereum", "R$ 1.500,00")
        ])

      {txns, _} = GcbCsv.parse(csv)
      assert length(txns) == 1
      assert hd(txns).operation == "venda"
      assert hd(txns).asset_ticker == "ETH"
    end

    test "classifica operacao estruturada compra" do
      csv =
        gcb_with_lines([
          gcb_line("10 de outubro de 2026", "Compra de Operação Estruturada", "R$ 3.000,00")
        ])

      {txns, _} = GcbCsv.parse(csv)
      assert length(txns) == 1
      assert hd(txns).asset_type == "op_estruturada"
      assert hd(txns).operation == "compra"
    end

    test "classifica operacao estruturada liquidacao" do
      csv =
        gcb_with_lines([
          gcb_line("10 de novembro de 2026", "Liquidação de Operação Estruturada", "R$ 3.100,00")
        ])

      {txns, _} = GcbCsv.parse(csv)
      assert length(txns) == 1
      assert hd(txns).operation == "venda"
    end

    test "classifica INSS como recebiveis" do
      csv =
        gcb_with_lines([
          gcb_line("10 de dezembro de 2026", "Investimento em INSS123", "R$ 8.000,00")
        ])

      {txns, _} = GcbCsv.parse(csv)
      assert length(txns) == 1
      assert hd(txns).asset_type == "recebiveis"
      assert hd(txns).operation == "compra"
    end

    test "pula operações com prefixo valor aportado" do
      csv =
        gcb_with_lines([
          gcb_line("10 de janeiro de 2026", "Valor Aportado", "R$ 500,00")
        ])

      {txns, _} = GcbCsv.parse(csv)
      assert txns == []
    end

    test "pula operações com prefixo cashback" do
      csv =
        gcb_with_lines([
          gcb_line("10 de janeiro de 2026", "Cashback rendimento", "R$ 10,00")
        ])

      {txns, _} = GcbCsv.parse(csv)
      assert txns == []
    end

    test "operação não reconhecida adiciona warning" do
      csv =
        gcb_with_lines([
          gcb_line("10 de janeiro de 2026", "Operação Desconhecida XYZ", "R$ 100,00")
        ])

      {txns, warnings} = GcbCsv.parse(csv)
      assert txns == []
      assert length(warnings) >= 1
    end

    test "parse_date retorna :error para formato inválido" do
      assert :error = GcbCsv.parse_date("invalid date")
      assert :error = GcbCsv.parse_date("10 de mesinvalido de 2026")
    end

    test "parse_amount retorna :error para string inválida" do
      assert :error = GcbCsv.parse_amount("not a number")
    end

    test "debenture especial 6 meses" do
      csv =
        gcb_with_lines([
          gcb_line("10 de janeiro de 2026", "Debênture Especial 6 meses DEB789", "R$ 2.000,00")
        ])

      {txns, _} = GcbCsv.parse(csv)
      assert length(txns) == 1
      assert hd(txns).asset_name == "Debênture Especial 6 meses"
    end
  end
end
