defmodule Grana.Agents.ChatToolsTest do
  use Grana.DataCase, async: true

  import Grana.AccountsFixtures
  import Grana.BankingFixtures

  alias Grana.Agents.ChatTools

  setup do
    user = user_fixture()

    transactions_fixture(user, [
      %{description: "UBER TRIP", amount: "-30.00", date: ~D[2026-03-10]},
      %{description: "UBER EATS", amount: "-45.50", date: ~D[2026-02-11]},
      %{description: "SALARIO", amount: "5000.00", type: "credit", date: ~D[2026-03-05]}
    ])

    tools = Map.new(ChatTools.all(%{user_id: user.id}), &{&1.name, &1})
    %{user: user, tools: tools}
  end

  defp call(tools, name, args \\ %{}) do
    case tools[name].function.(args, %{}) do
      {:ok, json} -> Jason.decode!(json)
      {:error, reason} -> {:error, reason}
    end
  end

  test "every tool has a description and a JSON schema", %{tools: tools} do
    assert map_size(tools) == 8

    for {_name, tool} <- tools do
      assert tool.description != ""
      assert %{type: "object", properties: _} = tool.parameters_schema
    end
  end

  test "get_data_overview lists what exists", %{tools: tools} do
    overview = call(tools, "get_data_overview")

    assert overview["years"] == [2026]
    assert overview["months_with_data"] == %{"2026" => [2, 3]}
    assert overview["banks"] == ["nubank"]
    assert Enum.any?(overview["categories"], &(&1["name"] == "Alimentação"))
    assert overview["today"] == Date.to_iso8601(Grana.LocalTime.today())
  end

  test "get_period_summary for a month, a year and all time", %{tools: tools} do
    march = call(tools, "get_period_summary", %{"year" => 2026, "month" => 3})
    assert march["expenses"] == "R$ 30,00"
    assert march["income"] == "R$ 5.000,00"
    assert march["free_balance"] == "R$ 4.970,00"

    assert [%{"description" => "UBER TRIP", "amount" => "-R$ 30,00", "bank" => "nubank"}] =
             march["largest_expenses"]

    assert call(tools, "get_period_summary", %{"year" => 2026})["expenses"] == "R$ 75,50"
    assert call(tools, "get_period_summary")["transactions"] == 3

    only_income =
      call(tools, "get_period_summary", %{"year" => 2026, "type" => "credit", "bank" => "all"})

    assert only_income["expenses"] == "R$ 0,00"
  end

  test "get_monthly_totals goes month by month", %{tools: tools} do
    months = call(tools, "get_monthly_totals", %{"year" => 2026, "statement_type" => "extrato"})

    assert %{"month" => 2, "expenses" => "R$ 45,50"} = Enum.find(months, &(&1["month"] == 2))
    assert %{"month" => 3, "income" => "R$ 5.000,00"} = Enum.find(months, &(&1["month"] == 3))
  end

  test "search_transactions uses the advanced search syntax", %{tools: tools} do
    found = call(tools, "search_transactions", %{"query" => "uber", "limit" => 1})

    assert found["count"] == 2
    assert found["total_out"] == "R$ 75,50"
    assert found["total_in"] == "R$ 0,00"
    assert [%{"description" => "UBER TRIP"}] = found["transactions"]

    assert {:error, "Invalid query: " <> _} =
             call(tools, "search_transactions", %{"query" => "amount >"})
  end

  test "get_fixed_expenses, get_installments and get_goals answer with their shape", %{
    tools: tools,
    user: user
  } do
    assert %{"months_analyzed" => _, "fixed_expenses" => []} =
             call(tools, "get_fixed_expenses", %{"months" => 12})

    assert %{"active" => 0, "per_month" => "R$ 0,00", "items" => []} =
             call(tools, "get_installments")

    goal_fixture(user, %{type: "expense_limit", target_value: "100.00"})

    assert [%{"goal" => "expense_limit", "target" => "R$ 100,00", "current" => "R$ 30,00"}] =
             call(tools, "get_goals", %{"year" => 2026, "month" => 3})
  end
end
