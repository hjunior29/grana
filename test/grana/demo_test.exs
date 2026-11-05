defmodule Grana.DemoTest do
  use Grana.BackupCase, async: false

  import Grana.AccountsFixtures

  alias Grana.Accounts
  alias Grana.Accounts.User
  alias Grana.Analyses
  alias Grana.Banking
  alias Grana.Chat
  alias Grana.Demo
  alias Grana.Demo.Dataset

  @today ~D[2026-11-05]

  setup do
    Application.put_env(:grana, :demo, true)
    on_exit(fn -> Application.put_env(:grana, :demo, false) end)
  end

  describe "reset!/1" do
    test "recreates the shared account with a year of fictitious statements" do
      user = Demo.reset!(@today)

      assert user.demo
      assert user.onboarded_at
      assert Demo.user().id == user.id
      refute Accounts.setup_required?()

      statements = Banking.list_statements(user.id)
      assert length(statements) == length(Dataset.statements(@today))
      assert Enum.all?(statements, &(&1.status == "completed"))

      transactions = Banking.list_transactions(user.id)
      assert length(transactions) > 400
      assert Enum.all?(transactions, &(Date.compare(&1.date, @today) != :gt))
    end

    test "card bills and transfers between the holder's accounts count as neither income nor spending" do
      user = Demo.reset!(@today)
      transactions = Banking.list_transactions(user.id)

      for prefix <- ["Pagamento de fatura", "Pagamento recebido", "TRANSFERENCIA PIX DES: MARINA"] do
        matching = Enum.filter(transactions, &String.starts_with?(&1.description, prefix))
        assert matching != [], prefix
        assert Enum.all?(matching, & &1.is_internal_transfer), prefix
      end
    end

    test "categorizes almost everything, leaving a few for the visitor" do
      user = Demo.reset!(@today)
      uncategorized = Enum.find(Banking.list_categories(user.id), &(&1.name == "Sem Categoria"))

      left =
        user.id
        |> Banking.list_transactions()
        |> Enum.filter(&(&1.category_id == uncategorized.id and not &1.is_internal_transfer))

      assert left != []
      assert Enum.all?(left, &(&1.description =~ ~r/FEIRA|Pix/i))
    end

    test "comes with rules, goals, saved searches and the AI examples" do
      user = Demo.reset!(@today)

      assert length(Banking.list_category_rules(user.id)) >= 10
      assert length(Banking.list_financial_goals(user.id)) == 5
      assert length(Banking.list_saved_searches(user.id)) == 3

      for date <- [@today, Date.shift(@today, month: -1)] do
        analysis = Analyses.latest(user.id, date.year, date.month)
        assert analysis.ai_model == nil
        refute Analyses.stale?(analysis)
        assert analysis.result_json["resumo"] =~ "R$"
      end

      [conversation] = Chat.list_conversations(user.id)
      conversation = Chat.get_conversation(user.id, conversation.id)
      assert Enum.map(conversation.messages, & &1.role) == ~w(user assistant user assistant)
    end

    test "starts over from the base data on every boot" do
      first = Demo.reset!(@today)
      count = length(Banking.list_transactions(first.id))
      Banking.delete_statements(Enum.map(Banking.list_statements(first.id), & &1.id), first.id)

      second = Demo.reset!(@today)

      assert Repo.aggregate(User, :count) == 1
      assert length(Banking.list_transactions(second.id)) == count
    end

    test "the account opens with the credentials shown on the login" do
      user = Demo.reset!(@today)
      %{email: email, password: password} = Demo.credentials()

      assert Accounts.get_user_by_email_and_password(email, password).id == user.id
    end

    test "refuses to wipe an instance that has a real owner" do
      owner = user_fixture()

      assert_raise RuntimeError, ~r/GRANA_DEMO=true numa instância que tem dono/, fn ->
        Demo.reset!(@today)
      end

      assert Repo.get(User, owner.id)
    end
  end

  describe "Dataset" do
    test "the same day always gives the same files" do
      assert Dataset.statements(@today) == Dataset.statements(@today)
    end

    test "names read like real ones, with no placeholder words" do
      for %{filename: filename, content: content} <- Dataset.statements(@today),
          do: refute(content =~ ~r/exemplo|modelo/i, filename)
    end

    test "only fictitious people and companies appear" do
      allowed =
        MapSet.new(~w(MARINA CARLOS BEATRIZ IMOBILIARIA EMPRESA SP BCO BANCO))

      names =
        @today
        |> Dataset.statements()
        |> Enum.flat_map(fn %{content: content} ->
          Regex.scan(~r/(?:Pix - |DES: |REM: )([A-Z][A-Z]+)/, content, capture: :all_but_first)
        end)
        |> List.flatten()
        |> MapSet.new()

      assert MapSet.subset?(names, allowed), inspect(MapSet.difference(names, allowed))
    end
  end

  test "allow/1 blocks only in the demo" do
    assert Demo.allow(:ai) == {:error, :demo}
    Application.put_env(:grana, :demo, false)
    assert Demo.allow(:ai) == :ok
  end
end
