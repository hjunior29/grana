defmodule Grana.Banking.StatementProcessorTest do
  use Grana.DataCase

  alias Grana.Banking
  alias Grana.Banking.StatementProcessor

  import Grana.AccountsFixtures
  import Grana.BankingFixtures, only: [transaction_fixture: 2]
  import Grana.OpenFinanceFixtures

  setup do
    user = user_fixture()
    Banking.ensure_default_categories(user.id)
    content = File.read!("test/support/fixtures/examples/extrato-nubank.csv")
    %{user: user, content: content}
  end

  test "importa transações e cria o statement (sem chave de IA usa regras)", %{
    user: user,
    content: content
  } do
    assert {:ok, result} =
             StatementProcessor.process(content, "nubank", "extrato", user.id, "extrato.csv")

    assert result.transaction_count > 0
    assert length(Banking.list_statements(user.id)) == 1
    assert length(Banking.list_transactions(user.id)) == result.transaction_count
  end

  test "reprocessar o mesmo arquivo não duplica (rollback transacional)", %{
    user: user,
    content: content
  } do
    {:ok, r1} = StatementProcessor.process(content, "nubank", "extrato", user.id, "extrato.csv")

    # Mesmo arquivo/filename/período → unique constraint → rollback → erro.
    assert {:error, _msg} =
             StatementProcessor.process(content, "nubank", "extrato", user.id, "extrato.csv")

    # Nenhuma transação ou statement a mais.
    assert length(Banking.list_transactions(user.id)) == r1.transaction_count
    assert length(Banking.list_statements(user.id)) == 1
  end

  test "o upload vence o Open Finance no período que cobre", %{user: user, content: content} do
    account = account_fixture(connection_fixture(user))

    statement =
      open_finance_statement_fixture(account, %{
        period_start: ~D[2026-01-01],
        period_end: ~D[2026-01-20]
      })

    covered = transaction_fixture(user, %{bank_statement_id: statement.id, date: ~D[2026-01-05]})
    later = transaction_fixture(user, %{bank_statement_id: statement.id, date: ~D[2026-01-20]})

    # Mesma data/descrição/valor de uma linha do arquivo: não pode derrubar a do upload.
    {1, _} =
      Banking.bulk_insert_transactions([
        %{
          date: ~D[2026-01-03],
          description: "Compra no débito - MERCADO EXEMPLO",
          amount: Decimal.new("-8.78"),
          type: "debit",
          bank_statement_id: statement.id,
          user_id: user.id
        }
      ])

    {:ok, result} =
      StatementProcessor.process(content, "nubank", "extrato", user.id, "extrato.csv")

    refute Grana.Repo.get(Grana.Banking.Transaction, covered.id)
    assert Grana.Repo.get(Grana.Banking.Transaction, later.id)

    uploaded = Banking.list_transactions(user.id, statement_type: "extrato")
    assert Enum.count(uploaded, &(&1.description =~ "MERCADO EXEMPLO")) == 1
    assert length(uploaded) == result.transaction_count + 1
  end

  test "o que foi ajustado à mão no Open Finance passa para o upload que o substitui", %{
    user: user
  } do
    account = account_fixture(connection_fixture(user))

    statement =
      open_finance_statement_fixture(account, %{
        period_start: ~D[2026-02-01],
        period_end: ~D[2026-02-28]
      })

    moradia = Enum.find(Banking.list_categories(user.id), &(&1.name == "Moradia"))
    lazer = Enum.find(Banking.list_categories(user.id), &(&1.name == "Lazer"))

    {4, _} =
      Banking.bulk_insert_transactions([
        # Recategorized by hand: two days before the upload's date, same amount.
        of_row(user, statement, ~D[2026-02-03], "BOLETO QWERTY", "-100.00",
          category_id: moradia.id
        ),
        # Marked by hand as an internal transfer.
        of_row(user, statement, ~D[2026-02-08], "PIX JOAO", "-250.00", internal_override: true),
        # The upload already has its own category: it stays.
        of_row(user, statement, ~D[2026-02-07], "FARMACIA", "-55.90", category_id: lazer.id),
        # Same date, other amount: does not match.
        of_row(user, statement, ~D[2026-02-05], "OUTRA", "-99.00", category_id: lazer.id)
      ])

    content = """
    Data,Valor,Identificador,Descrição
    05/02/2026,-100.00,id-1,Boleto pago - ZQWX SERVICOS
    06/02/2026,-250.00,id-2,Transferencia enviada pelo Pix - JOAO TESTE
    07/02/2026,-55.90,id-3,Compra no débito - FARMACIA ALFA
    07/02/2026,-12.00,id-4,Compra no débito - LOJA SEM PAR
    """

    {:ok, _} = StatementProcessor.process(content, "nubank", "extrato", user.id, "fev.csv")

    uploaded =
      user.id
      |> Banking.list_transactions(statement_type: "extrato")
      |> Enum.filter(&(&1.bank_statement.source == "upload"))
      |> Map.new(&{&1.description, &1})

    uncategorized = Banking.get_uncategorized_category(user.id)

    assert uploaded["Boleto pago - ZQWX SERVICOS"].category_id == moradia.id

    pix = uploaded["Transferencia enviada pelo Pix - JOAO TESTE"]
    assert pix.internal_override == true
    assert pix.is_internal_transfer == true

    assert uploaded["Compra no débito - FARMACIA ALFA"].category.name == "Saúde"
    assert uploaded["Compra no débito - LOJA SEM PAR"].category_id == uncategorized.id
    assert uploaded["Compra no débito - LOJA SEM PAR"].internal_override == nil
  end

  defp of_row(user, statement, date, description, amount, extra) do
    Map.merge(
      %{
        date: date,
        description: description,
        amount: Decimal.new(amount),
        type: "debit",
        bank_statement_id: statement.id,
        user_id: user.id
      },
      Map.new(extra)
    )
  end

  test "isolamento: o statement importado pertence ao usuário", %{user: user, content: content} do
    other = user_fixture()
    {:ok, _} = StatementProcessor.process(content, "nubank", "extrato", user.id, "extrato.csv")

    assert Banking.list_statements(other.id) == []
    assert length(Banking.list_statements(user.id)) == 1
  end

  describe "other banks and types" do
    test "imports bradesco extrato", %{user: user} do
      content = File.read!("test/support/fixtures/examples/extrato-bradesco.csv")

      assert {:ok, result} =
               StatementProcessor.process(content, "bradesco", "extrato", user.id, "bradesco.csv")

      assert result.transaction_count > 0
    end

    test "imports nubank fatura", %{user: user} do
      content = File.read!("test/support/fixtures/examples/fatura-nubank.csv")

      assert {:ok, result} =
               StatementProcessor.process(content, "nubank", "fatura", user.id, "fatura.csv")

      assert result.transaction_count > 0
    end

    test "imports bradesco fatura", %{user: user} do
      content = File.read!("test/support/fixtures/examples/fatura-bradesco.csv")

      assert {:ok, result} =
               StatementProcessor.process(
                 content,
                 "bradesco",
                 "fatura",
                 user.id,
                 "fatura-bradesco.csv"
               )

      assert result.transaction_count > 0
    end

    test "returns error for empty file content", %{user: user} do
      result = StatementProcessor.process("", "nubank", "extrato", user.id, "empty.csv")
      assert {:error, _msg} = result
    end

    test "returns error for invalid CSV content", %{user: user} do
      result =
        StatementProcessor.process("not a csv at all", "nubank", "extrato", user.id, "bad.csv")

      assert {:error, _msg} = result
    end

    test "returns error for outro bank with CSV", %{user: user} do
      result =
        StatementProcessor.process(
          "data,descricao,valor\n10/01/2026,LOJA,-100",
          "outro",
          "extrato",
          user.id,
          "outro.csv"
        )

      assert {:error, msg} = result
      assert msg =~ "CSV" or msg =~ "suportado" or msg =~ "PDF"
    end

    test "duplicate statement returns error", %{user: user, content: content} do
      {:ok, _} = StatementProcessor.process(content, "nubank", "extrato", user.id, "dup.csv")

      assert {:error, _msg} =
               StatementProcessor.process(content, "nubank", "extrato", user.id, "dup.csv")
    end
  end
end
