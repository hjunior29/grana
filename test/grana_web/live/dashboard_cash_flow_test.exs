defmodule GranaWeb.DashboardCashFlowTest do
  use GranaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Grana.BankingFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    salary = category_fixture(user, %{name: "Freela", kind: "income", color: "#22c55e"})
    food = category_fixture(user, %{name: "Feira", color: "#f97316"})
    invest = category_fixture(user, %{name: "Cofrinho", kind: "investment"})

    rows = [
      %{
        date: ~D[2026-03-05],
        description: "SALARIO",
        amount: "5000.00",
        type: "credit",
        category_id: salary.id
      },
      %{date: ~D[2026-03-10], description: "MERCADO", amount: "-800.00", category_id: food.id},
      %{date: ~D[2026-03-12], description: "PADARIA", amount: "-200.00", category_id: food.id},
      %{date: ~D[2026-03-15], description: "CDB", amount: "-1000.00", category_id: invest.id},
      %{date: ~D[2026-03-20], description: "FARMACIA", amount: "-300.00"}
    ]

    transactions_fixture(user, rows)
    %{food: food}
  end

  defp flow(view) do
    [json] =
      view
      |> element("#cash-flow-chart")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.attribute("data-flow")

    Jason.decode!(json)
  end

  test "income flows to the categories, investments and what is left", %{conn: conn, food: food} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    assert has_element?(view, "#income-expenses-chart + * #cash-flow-card, #cash-flow-card")
    %{"sources" => sources, "targets" => targets} = flow(view)

    assert [%{"name" => "Freela", "value" => 5000.0, "color" => "#22c55e", "url" => salary_url}] =
             sources

    assert salary_url =~ "type=credit"

    assert [
             %{
               "name" => "Feira",
               "value" => 1000.0,
               "color" => "#f97316",
               "url" => food_url
             },
             %{"name" => "Sem Categoria", "value" => 300.0},
             %{"name" => "Investimentos", "value" => 1000.0, "kind" => "investment"},
             %{"name" => "Sobra", "value" => 2700.0, "kind" => "surplus"}
           ] = targets

    assert food_url =~ "category_id=#{food.id}"
    assert food_url =~ "date_from=2026-03-01"
  end

  test "spending past the income shows up as a deficit source", %{conn: conn, user: user} do
    transactions_fixture(user, [
      %{date: ~D[2026-03-22], description: "VIAGEM", amount: "-4000.00"}
    ])

    {:ok, view, _html} = live(conn, ~p"/dashboard")
    %{"sources" => sources, "targets" => targets} = flow(view)

    assert [
             %{"name" => "Freela"},
             %{"name" => "Déficit", "value" => 1300.0, "kind" => "deficit"}
           ] =
             sources

    refute Enum.any?(targets, &(&1["name"] == "Sobra"))
  end

  test "the chart leaves with the movement filter and without data", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    render_click(view, "select_txn_type", %{"txn_type" => "debit"})
    refute has_element?(view, "#cash-flow-card")

    render_click(view, "select_txn_type", %{"txn_type" => "all"})
    assert has_element?(view, "#cash-flow-card")

    render_click(view, "select_month", %{"month" => "1"})
    refute has_element?(view, "#cash-flow-card")
  end
end
