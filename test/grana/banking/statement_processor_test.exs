defmodule Grana.Banking.StatementProcessorTest do
  use Grana.DataCase

  alias Grana.Banking
  alias Grana.Banking.StatementProcessor

  import Grana.AccountsFixtures

  setup do
    user = user_fixture()
    Banking.ensure_default_categories(user.id)
    content = File.read!("priv/examples/extrato-nubank.csv")
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
end
