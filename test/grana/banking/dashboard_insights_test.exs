defmodule Grana.Banking.DashboardInsightsTest do
  use Grana.DataCase, async: true

  import Grana.AccountsFixtures
  import Grana.BankingFixtures

  alias Grana.Banking
  alias Grana.Banking.{CategoryRule, InternalTransferRule}

  setup do
    %{user: user_fixture()}
  end

  defp dec(value), do: Decimal.new(value)

  describe "period_trend/4" do
    test "a month compares with the previous one and averages the months before it", %{
      user: user
    } do
      transactions_fixture(user, [
        %{date: ~D[2025-12-10], amount: "-300.00"},
        %{date: ~D[2026-01-10], amount: "-100.00"},
        %{date: ~D[2026-01-05], amount: "1000.00", type: "credit", description: "SALARIO"},
        %{date: ~D[2026-02-10], amount: "-200.00"},
        %{date: ~D[2026-03-10], amount: "-999.00"}
      ])

      trend = Banking.period_trend(user.id, 2026, 2)

      assert trend.previous.label == "Janeiro/2026"
      assert Decimal.equal?(trend.previous.expenses, dec("100.00"))
      assert Decimal.equal?(trend.previous.income, dec("1000.00"))

      # December and January (the selected month and later ones stay out).
      assert trend.average.months == 2
      assert Decimal.equal?(trend.average.expenses, dec("200.00"))
      assert Decimal.equal?(trend.average.income, dec("500.00"))
    end

    test "January compares with December of the year before", %{user: user} do
      transactions_fixture(user, [%{date: ~D[2025-12-10], amount: "-80.00"}])

      trend = Banking.period_trend(user.id, 2026, 1)

      assert trend.previous.label == "Dezembro/2025"
      assert Decimal.equal?(trend.previous.expenses, dec("80.00"))
    end

    test "with no history there is nothing to compare", %{user: user} do
      transactions_fixture(user, [%{date: ~D[2026-02-10], amount: "-200.00"}])

      trend = Banking.period_trend(user.id, 2026, 2)

      assert Decimal.equal?(trend.previous.expenses, 0)
      assert trend.average == nil
    end

    test "a year compares with the whole year before, without average", %{user: user} do
      transactions_fixture(user, [
        %{date: ~D[2025-03-10], amount: "-100.00"},
        %{date: ~D[2025-09-10], amount: "-50.00"},
        %{date: ~D[2026-03-10], amount: "-10.00"}
      ])

      trend = Banking.period_trend(user.id, 2026, nil)

      assert trend.previous.label == "2025"
      assert Decimal.equal?(trend.previous.expenses, dec("150.00"))
      assert trend.average == nil
    end
  end

  describe "merchant_spending/3" do
    test "groups the period's expenses by merchant, biggest total first", %{user: user} do
      food = category_fixture(user, %{name: "Delivery"})
      investment = category_fixture(user, %{name: "Corretora", kind: "investment"})

      transactions_fixture(user, [
        %{
          description: "IFOOD *RESTAURANTE",
          amount: "-40.00",
          date: ~D[2026-03-02],
          category_id: food.id
        },
        %{
          description: "IFOOD *RESTAURANTE",
          amount: "-60.00",
          date: ~D[2026-03-09],
          category_id: food.id
        },
        %{description: "LOJA X 2/10", amount: "-300.00", date: ~D[2026-03-05]},
        %{description: "LOJA X 3/10", amount: "-300.00", date: ~D[2026-03-25]},
        %{
          description: "CORRETORA ABC",
          amount: "-900.00",
          date: ~D[2026-03-06],
          category_id: investment.id
        },
        %{description: "SALARIO", amount: "5000.00", type: "credit", date: ~D[2026-03-01]},
        %{description: "IFOOD *RESTAURANTE", amount: "-70.00", date: ~D[2026-04-01]}
      ])

      assert [loja, ifood] = Banking.merchant_spending(user.id, {:month, 2026, 3})

      # Every installment of a purchase is the same merchant.
      assert %{name: "LOJA X", count: 2} = loja
      assert Decimal.equal?(loja.total, dec("600.00"))

      assert %{name: "IFOOD *RESTAURANTE", count: 2, category: %{name: "Delivery"}} = ifood
      assert Decimal.equal?(ifood.average, dec("50.00"))

      assert [_, %{count: 3}] = Banking.merchant_spending(user.id, {:year, 2026})
      assert length(Banking.merchant_spending(user.id, :total)) == 2
    end

    test "internal transfers stay out", %{user: user} do
      [txn] =
        transactions_fixture(user, [%{description: "PIX MINHA CONTA", date: ~D[2026-03-02]}])

      Banking.update_transaction(txn, %{is_internal_transfer: true})

      assert Banking.merchant_spending(user.id, {:month, 2026, 3}) == []
    end
  end

  describe "pending_fixed_expenses/2" do
    test "fixed expenses charged last month but not yet in this one", %{user: user} do
      today = Grana.LocalTime.today()
      this_month = Date.beginning_of_month(today)
      months = for n <- 1..3, do: Date.shift(this_month, month: -n)

      transactions_fixture(
        user,
        Enum.flat_map(months, fn month ->
          [
            %{description: "ACADEMIA FORTE", amount: "-120.00", date: Date.add(month, 9)},
            %{description: "STREAMING TV", amount: "-40.00", date: Date.add(month, 4)}
          ]
        end) ++ [%{description: "STREAMING TV", amount: "-40.00", date: this_month}]
      )

      assert [%{name: "ACADEMIA FORTE", typical_day: 10} = academia] =
               Banking.pending_fixed_expenses(user.id, today)

      assert Decimal.equal?(academia.avg_amount, dec("120.00"))
    end
  end

  describe "goals" do
    test "in the current month, a spending limit says how much is left a day", %{user: user} do
      today = Grana.LocalTime.today()
      transactions_fixture(user, [%{date: Date.beginning_of_month(today), amount: "-400.00"}])
      goal_fixture(user, %{type: "expense_limit", target_value: "1000.00"})
      goal_fixture(user, %{type: "income_goal", target_value: "500.00"})

      progress = Banking.goals_progress(user.id, today.year, today.month, today)
      limit = Enum.find(progress, &(&1.goal.type == "expense_limit"))
      income = Enum.find(progress, &(&1.goal.type == "income_goal"))
      days_left = Date.days_in_month(today) - today.day + 1

      assert limit.pace.days_left == days_left
      assert limit.pace.day_pct == Float.round(today.day / Date.days_in_month(today) * 100, 1)
      assert Decimal.equal?(limit.pace.remaining, dec("600.00"))

      assert Decimal.equal?(
               limit.pace.daily,
               dec("600.00") |> Decimal.div(days_left) |> Decimal.round(2)
             )

      # Income goals get the needle, but no daily quota.
      assert income.pace.daily == nil
    end

    test "an exceeded limit has no quota and another month has no pace", %{user: user} do
      today = Grana.LocalTime.today()
      transactions_fixture(user, [%{date: Date.beginning_of_month(today), amount: "-1500.00"}])
      goal_fixture(user, %{type: "expense_limit", target_value: "1000.00"})

      assert [%{pace: %{daily: nil, remaining: nil}}] =
               Banking.goals_progress(user.id, today.year, today.month, today)

      assert [%{pace: nil}] = Banking.goals_progress(user.id, 2020, 1, today)
    end

    test "goals_history/4 tells each of the months before whether the goal was met", %{
      user: user
    } do
      cat = category_fixture(user, %{name: "Mercado"})

      transactions_fixture(user, [
        %{date: ~D[2026-01-10], amount: "-800.00"},
        %{date: ~D[2026-02-10], amount: "-1200.00", category_id: cat.id},
        %{date: ~D[2026-02-10], amount: "1000.00", type: "credit", description: "SALARIO"},
        %{date: ~D[2026-04-10], amount: "-50.00"}
      ])

      limit = goal_fixture(user, %{type: "expense_limit", target_value: "1000.00"})
      income = goal_fixture(user, %{type: "income_goal", target_value: "900.00"})

      category =
        goal_fixture(user, %{type: "category_limit", target_value: "100.00", category_id: cat.id})

      history = Banking.goals_history(user.id, 2026, 4, 4)

      assert Enum.map(history[limit.id], &{&1.month, &1.status}) == [
               {12, :no_data},
               {1, :met},
               {2, :missed},
               {3, :no_data}
             ]

      assert Enum.map(history[income.id], & &1.status) == [:no_data, :missed, :met, :no_data]
      assert Enum.map(history[category.id], & &1.status) == [:no_data, :met, :missed, :no_data]
      assert %{year: 2025, value: nil} = hd(history[limit.id])
      assert Decimal.equal?(Enum.at(history[limit.id], 2).value, dec("1200.00"))
    end
  end

  describe "learned rules" do
    test "category rules of one category can be listed and removed", %{user: user} do
      cat = category_fixture(user)
      other = category_fixture(user)
      b = category_rule_fixture(user, cat, %{pattern: "bbb"})
      category_rule_fixture(user, cat, %{pattern: "aaa"})
      category_rule_fixture(user, other, %{pattern: "ccc"})

      assert Enum.map(Banking.category_rules(user.id, cat.id), & &1.pattern) == ["aaa", "bbb"]

      assert {:ok, 1} = Banking.delete_category_rule(user.id, b.id)
      assert {:ok, 0} = Banking.delete_category_rule(user_fixture().id, b.id)
      assert Enum.map(Banking.category_rules(user.id, cat.id), & &1.pattern) == ["aaa"]
      refute Repo.get(CategoryRule, b.id)
    end

    test "removing an internal transfer rule recalculates its transactions", %{user: user} do
      [txn] =
        transactions_fixture(user, [
          %{description: "Transferência enviada pelo Pix - JOAO SILVA", date: ~D[2026-03-02]}
        ])

      {:ok, :rule} = Banking.set_transaction_internal(user.id, txn.id, true)
      assert Repo.reload!(txn).is_internal_transfer
      [rule] = Banking.list_internal_transfer_rules(user.id)

      assert {:ok, 0} = Banking.delete_internal_transfer_rule(user_fixture().id, rule.id)
      assert Repo.get(InternalTransferRule, rule.id)

      assert {:ok, 1} = Banking.delete_internal_transfer_rule(user.id, rule.id)
      assert Banking.list_internal_transfer_rules(user.id) == []
      refute Repo.reload!(txn).is_internal_transfer
    end
  end
end
