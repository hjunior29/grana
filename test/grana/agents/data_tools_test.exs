defmodule Grana.Agents.DataToolsTest do
  use Grana.DataCase, async: true

  import Grana.AccountsFixtures
  import Grana.BankingFixtures

  alias Grana.Agents.DataTools

  setup do
    user = user_fixture()

    transactions_fixture(user, [
      %{description: "UNIMED BH", amount: "-450.00", date: ~D[2026-04-05]},
      %{description: "UBER TRIP", amount: "-30.00", date: ~D[2026-04-10]}
    ])

    %{user: user}
  end

  test "list_merchants returns the merchants with category, count and total", %{user: user} do
    tool = DataTools.list_merchants(user.id)
    {:ok, json} = tool.function.(%{"type" => "debit", "limit" => 500}, %{})

    assert [
             %{"name" => "UNIMED BH", "count" => 1, "total" => "R$ 450,00"},
             %{"name" => "UBER TRIP"}
           ] =
             Jason.decode!(json)
  end

  test "preview_query reports what a query finds, or why it is invalid", %{user: user} do
    tool = DataTools.preview_query(user.id)

    {:ok, json} = tool.function.(%{"query" => "unimed OR uber"}, %{})
    assert %{"count" => 2, "total" => "R$ 480,00", "merchants" => merchants} = Jason.decode!(json)
    assert Enum.map(merchants, & &1["description"]) |> Enum.sort() == ["UBER TRIP", "UNIMED BH"]

    assert {:error, "Invalid query: " <> _} = tool.function.(%{"query" => "amount >"}, %{})
  end
end
