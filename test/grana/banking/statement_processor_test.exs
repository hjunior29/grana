defmodule Grana.Banking.StatementProcessorTest do
  use Grana.DataCase

  alias Grana.Banking
  alias Grana.Banking.StatementProcessor

  import Grana.AccountsFixtures

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
