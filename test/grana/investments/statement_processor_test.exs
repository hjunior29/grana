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

  describe "error paths" do
    test "erro para arquivo vazio", %{user: user} do
      assert {:error, _msg} = StatementProcessor.process("", "gcb", user.id, "empty.csv")
    end

    test "erro para conteúdo inválido (non-CSV)", %{user: user} do
      assert {:error, _msg} =
               StatementProcessor.process("not a csv file", "gcb", user.id, "bad.csv")
    end

    test "erro quando B3 recebe CSV (formato incorreto)", %{user: user} do
      assert {:error, msg} =
               StatementProcessor.process(
                 "data,ativo,valor\n10/01/2026,PETR4,-100",
                 "b3",
                 user.id,
                 "wrong.csv"
               )

      assert msg =~ "B3" or msg =~ "CSV" or msg =~ "XLSX"
    end

    test "erro quando GCB recebe XLSX", %{user: user} do
      assert {:error, msg} =
               StatementProcessor.process("fake xlsx content", "gcb", user.id, "wrong.xlsx")

      assert msg =~ "GCB" or msg =~ "XLSX" or msg =~ "CSV"
    end

    test "erro ao importar extrato já existente (todas deduplicadas)", %{
      user: user,
      content: content
    } do
      {:ok, _} = StatementProcessor.process(content, "gcb", user.id, "gcb.csv")

      assert {:error, _msg} = StatementProcessor.process(content, "gcb", user.id, "gcb2.csv")
    end
  end
end
