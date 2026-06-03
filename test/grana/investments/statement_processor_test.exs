defmodule Grana.Investments.StatementProcessorTest do
  use Grana.DataCase

  alias Grana.Investments
  alias Grana.Investments.StatementProcessor

  import Grana.AccountsFixtures

  setup do
    user = user_fixture()
    content = File.read!("test/support/fixtures/examples/extrato-gcb.csv")
    %{user: user, content: content}
  end

  test "importa transações e cria o statement da GCB", %{user: user, content: content} do
    assert {:ok, result} = StatementProcessor.process(content, "gcb", user.id, "gcb.csv")
    assert result.transaction_count > 0
    assert length(Investments.list_statements(user.id)) == 1
  end

  test "reprocessar não duplica (dedup das transações)", %{user: user, content: content} do
    {:ok, _r1} = StatementProcessor.process(content, "gcb", user.id, "gcb.csv")

    assert {:error, _msg} = StatementProcessor.process(content, "gcb", user.id, "gcb.csv")
    assert length(Investments.list_statements(user.id)) == 1
  end

  test "isolamento: o statement pertence ao usuário", %{user: user, content: content} do
    other = user_fixture()
    {:ok, _} = StatementProcessor.process(content, "gcb", user.id, "gcb.csv")

    assert Investments.list_statements(other.id) == []
  end
end
