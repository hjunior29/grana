defmodule Grana.Banking.Parsers.BradescoPdfTest do
  use ExUnit.Case, async: true

  alias Grana.Banking.Parsers.BradescoPdf

  @layout File.read!("test/support/fixtures/pdf/extrato-bradesco-layout.txt")

  describe "parse/1 com o extrato real (output do pdftotext -layout)" do
    setup do
      {:ok, txns: BradescoPdf.parse(@layout)}
    end

    test "extrai todas as transações do extrato (sem a duplicata da recap)", %{txns: txns} do
      assert length(txns) == 34
    end

    test "captura o Docto como identifier", %{txns: txns} do
      assert Enum.all?(txns, &(&1.identifier != nil))

      pix = Enum.find(txns, &(&1.description == "PIX QR CODE DINAMICO - Fulano Moreira Basto"))
      assert pix.identifier == "1332274"
    end

    test "remove transação re-listada na folha 'Últimos Lançamentos'", %{txns: txns} do
      # A folha 2 e a folha 3 listam o mesmo RENTAB (Docto 8606144, 0,01) em
      # 12/02; só uma deve sobrar.
      rentab_12 =
        Enum.filter(
          txns,
          &(&1.date == ~D[2026-02-12] and &1.description == "RENTAB.INVEST FACILCRED")
        )

      assert length(rentab_12) == 1
    end

    test "reconcilia: saldo acumulado bate com o saldo impresso em cada folha" do
      assert BradescoPdf.reconcile(@layout) == :ok
    end

    test "reconcile detecta um saldo/valor lido errado (rede de segurança)" do
      # Corrompe um saldo impresso mantendo o alinhamento das colunas.
      corrupted = String.replace(@layout, "15.890,37", "15.890,99")
      assert {:error, issues} = BradescoPdf.reconcile(corrupted)
      assert issues != []
    end

    test "toda transação tem data, tipo válido e valor não-zero", %{txns: txns} do
      assert Enum.all?(txns, &(&1.date != nil))
      assert Enum.all?(txns, &(&1.type in ["credit", "debit"]))
      refute Enum.any?(txns, &Decimal.equal?(&1.amount, 0))
    end

    test "crédito é positivo e débito é negativo", %{txns: txns} do
      assert Enum.all?(txns, fn t ->
               case t.type do
                 "credit" -> Decimal.compare(t.amount, 0) == :gt
                 "debit" -> Decimal.compare(t.amount, 0) == :lt
               end
             end)
    end

    test "ignora saldo inicial (COD. LANC.) e subtotais (Total)", %{txns: txns} do
      descriptions = Enum.map(txns, & &1.description)
      refute Enum.any?(descriptions, &String.contains?(&1, "COD. LANC"))
      refute Enum.any?(descriptions, &String.starts_with?(&1, "Total"))
    end

    test "não contamina descrições com rodapé/cabeçalho da página", %{txns: txns} do
      descriptions = Enum.map(txns, & &1.description)

      for noise <- ["Bradesco Celular", "Nome:", "Folha", "Agência", "Extrato de"] do
        refute Enum.any?(descriptions, &String.contains?(&1, noise)),
               "descrição contaminada com #{inspect(noise)}"
      end
    end

    test "junta descrição multi-linha incluindo a contraparte (DES:/REM:)", %{txns: txns} do
      assert pix = Enum.find(txns, &(&1.description == "PIX QR CODE DINAMICO - Fulano Moreira Basto"))
      assert pix.type == "debit"
      assert Decimal.equal?(pix.amount, Decimal.new("-60.00"))
      assert pix.date == ~D[2026-02-06]

      assert cobranca =
               Enum.find(txns, &(&1.description == "PAGTO ELETRON COBRANCA - NU PAGAMENTOS SA"))

      assert cobranca.type == "debit"
      assert Decimal.equal?(cobranca.amount, Decimal.new("-4612.79"))
    end

    test "valor na coluna Crédito vira crédito positivo", %{txns: txns} do
      assert b3 = Enum.find(txns, &String.starts_with?(&1.description, "PGTO DE RENDIMENTO - B3"))
      assert b3.type == "credit"
      assert Decimal.equal?(b3.amount, Decimal.new("19.00"))
      assert b3.date == ~D[2026-02-06]
    end

    test "herda a data do bloco anterior quando ausente e lê folhas seguintes", %{txns: txns} do
      # Transações da folha 3 ("Últimos Lançamentos"), datas 12-13/02.
      dates = txns |> Enum.map(& &1.date) |> Enum.uniq()
      assert ~D[2026-02-13] in dates

      kinea = Enum.find(txns, &(&1.description == "PGTO DE RENDIMENTO - B3 - FII KINEA"))
      assert kinea.date == ~D[2026-02-13]
      assert kinea.type == "credit"
    end
  end

  describe "parse/1 com entradas degeneradas" do
    test "texto vazio devolve lista vazia" do
      assert BradescoPdf.parse("") == []
    end

    test "texto sem cabeçalho reconhecível devolve lista vazia" do
      assert BradescoPdf.parse("qualquer coisa\nsem tabela\n") == []
    end
  end
end
