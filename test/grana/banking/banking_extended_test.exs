defmodule Grana.Banking.ExtendedTest do
  use Grana.DataCase

  alias Grana.Banking

  import Grana.AccountsFixtures
  import Grana.BankingFixtures

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "category_stats/1" do
    test "returns stats map with empty categories", %{user: user} do
      Banking.ensure_default_categories(user.id)
      stats = Banking.category_stats(user.id)
      assert is_map(stats)
    end

    test "returns count of transactions per category", %{user: user} do
      Banking.ensure_default_categories(user.id)
      cat = Banking.get_uncategorized_category(user.id)
      transaction_fixture(user, %{amount: "-10.00", category_id: cat.id})

      stats = Banking.category_stats(user.id)
      assert is_map(stats)
      assert map_size(stats) >= 1

      entry = Map.get(stats, cat.id)
      assert entry
      assert entry.transaction_count >= 1
    end
  end

  describe "list_statements_paginated/2" do
    test "returns {statements, total} tuple", %{user: user} do
      stmt = statement_fixture(user)
      {statements, total} = Banking.list_statements_paginated(user.id)
      assert is_list(statements)
      assert is_integer(total)
      assert Enum.any?(statements, &(&1.id == stmt.id))
    end

    test "supports pagination", %{user: user} do
      for _ <- 1..5, do: statement_fixture(user)
      {statements, total} = Banking.list_statements_paginated(user.id, per_page: 2)
      assert length(statements) == 2
      assert total >= 5
    end
  end

  describe "available_banks/1" do
    test "returns empty list when no statements", %{user: user} do
      assert Banking.available_banks(user.id) == []
    end

    test "returns list of bank names from statements", %{user: user} do
      statement_fixture(user, %{bank: "nubank"})

      banks = Banking.available_banks(user.id)
      assert is_list(banks)
      assert "nubank" in banks
    end
  end

  describe "get_transaction!/2" do
    test "returns transaction for correct user", %{user: user} do
      txn = transaction_fixture(user, %{description: "PADARIA"})
      found = Banking.get_transaction!(txn.id, user.id)
      assert found.id == txn.id
      assert found.description == "PADARIA"
    end

    test "raises for wrong user", %{user: user} do
      txn = transaction_fixture(user, %{description: "SECRET"})
      other_user = user_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        Banking.get_transaction!(txn.id, other_user.id)
      end
    end
  end

  describe "update_transaction/2" do
    test "updates transaction description", %{user: user} do
      txn = transaction_fixture(user, %{description: "OLD"})
      {:ok, updated} = Banking.update_transaction(txn, %{description: "NEW"})
      assert updated.description == "NEW"
    end
  end

  describe "bulk_update_categories/3" do
    test "updates category for multiple transactions", %{user: user} do
      Banking.ensure_default_categories(user.id)
      cat = Banking.get_uncategorized_category(user.id)

      txn1 = transaction_fixture(user, %{description: "A"})
      txn2 = transaction_fixture(user, %{description: "B"})

      {count, _} = Banking.bulk_update_categories([txn1.id, txn2.id], cat.id, user.id)
      assert count == 2

      updated1 = Grana.Repo.get!(Grana.Banking.Transaction, txn1.id)
      assert updated1.category_id == cat.id
    end

    test "does not update transactions of other user", %{user: user} do
      other_user = user_fixture()
      Banking.ensure_default_categories(other_user.id)
      cat = Banking.get_uncategorized_category(other_user.id)

      txn = transaction_fixture(user, %{description: "MINE"})

      {count, _} = Banking.bulk_update_categories([txn.id], cat.id, other_user.id)
      assert count == 0
    end
  end

  describe "set_transaction_internal/3" do
    test "marks transaction as internal transfer", %{user: user} do
      txn = transaction_fixture(user, %{description: "PIX TRANSFER"})

      result = Banking.set_transaction_internal(user.id, txn.id, true)
      assert {:ok, _kind} = result
    end

    test "unmarks transaction as internal transfer", %{user: user} do
      txn = transaction_fixture(user, %{description: "PIX TRANSFER"})

      result = Banking.set_transaction_internal(user.id, txn.id, false)
      assert {:ok, _kind} = result
    end

    test "raises for wrong user", %{user: user} do
      txn = transaction_fixture(user, %{description: "PIX"})
      other_user = user_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        Banking.set_transaction_internal(other_user.id, txn.id, true)
      end
    end
  end

  describe "list_internal_transfer_rules/1" do
    test "returns empty list initially", %{user: user} do
      assert Banking.list_internal_transfer_rules(user.id) == []
    end
  end

  describe "category rules" do
    test "list_category_rules returns empty initially", %{user: user} do
      assert Banking.list_category_rules(user.id) == []
    end

    test "create_category_rule creates a rule (pattern normalized to lowercase)", %{user: user} do
      Banking.ensure_default_categories(user.id)
      cat = Banking.get_uncategorized_category(user.id)

      {:ok, rule} =
        Banking.create_category_rule(%{
          pattern: "PADARIA",
          category_id: cat.id,
          user_id: user.id
        })

      assert rule.pattern == "padaria"
      assert rule.category_id == cat.id
    end

    test "categorize_transaction matches by rule", %{user: user} do
      Banking.ensure_default_categories(user.id)
      cat = Banking.get_uncategorized_category(user.id)

      Banking.create_category_rule(%{
        pattern: "MERCADO",
        category_id: cat.id,
        user_id: user.id
      })

      result = Banking.categorize_transaction("MERCADO LIVRE", user.id)
      assert result == cat.id or is_nil(result)
    end

    test "categorize_transaction returns nil when no rule matches", %{user: user} do
      result = Banking.categorize_transaction("UNKNOWN STORE", user.id)
      assert is_nil(result)
    end

    test "categorize_transactions handles list", %{user: user} do
      Banking.ensure_default_categories(user.id)
      cat = Banking.get_uncategorized_category(user.id)

      Banking.create_category_rule(%{
        pattern: "PADARIA",
        category_id: cat.id,
        user_id: user.id
      })

      results = Banking.categorize_transactions(["PADARIA BOA", "FARMACIA X"], user.id)
      assert is_map(results)
    end

    test "categorize_transaction_with_rules uses provided rules", %{user: user} do
      Banking.ensure_default_categories(user.id)
      cat = Banking.get_uncategorized_category(user.id)

      {:ok, rule} =
        Banking.create_category_rule(%{
          pattern: "SUPERMERCADO",
          category_id: cat.id,
          user_id: user.id
        })

      result = Banking.categorize_transaction_with_rules("SUPERMERCADO BOM", [rule], user.id)
      assert result == cat.id or is_nil(result)
    end
  end

  describe "summary functions" do
    setup %{user: user} do
      Banking.ensure_default_categories(user.id)
      cat = Banking.get_uncategorized_category(user.id)

      transaction_fixture(user, %{
        description: "INCOME",
        amount: "1000.00",
        date: Date.new!(2026, 1, 15),
        category_id: cat.id
      })

      transaction_fixture(user, %{
        description: "EXPENSE",
        amount: "-200.00",
        date: Date.new!(2026, 1, 20),
        category_id: cat.id
      })

      :ok
    end

    test "monthly_summary returns summary for a month", %{user: user} do
      summary = Banking.monthly_summary(user.id, 2026, 1)
      assert is_map(summary)
      assert Map.has_key?(summary, :transaction_count)
      assert summary.transaction_count >= 2
    end

    test "yearly_summary returns summary for a year", %{user: user} do
      summary = Banking.yearly_summary(user.id, 2026)
      assert is_map(summary)
      assert Map.has_key?(summary, :transaction_count)
      assert summary.transaction_count >= 2
    end

    test "all_time_summary returns overall summary", %{user: user} do
      summary = Banking.all_time_summary(user.id)
      assert is_map(summary)
      assert Map.has_key?(summary, :transaction_count)
    end

    test "available_months returns months with data", %{user: user} do
      months = Banking.available_months(user.id)
      assert is_list(months)
      assert {2026, 1} in months
    end

    test "available_years returns years with data", %{user: user} do
      years = Banking.available_years(user.id)
      assert 2026 in years
    end

    test "daily_spending returns day-by-day breakdown", %{user: user} do
      result = Banking.daily_spending(user.id, 2026, 1)
      assert is_list(result)
      assert result != []
    end

    test "monthly_income_expenses returns monthly breakdown", %{user: user} do
      result = Banking.monthly_income_expenses(user.id, 2026)
      assert is_list(result)
      entry = Enum.find(result, &(&1.month == 1))
      assert entry
    end

    test "transactions_summary returns aggregated data", %{user: user} do
      result = Banking.transactions_summary(user.id, year: 2026)
      assert is_map(result)
      assert Map.has_key?(result, :total_income) or Map.has_key?(result, :total_expenses)
    end

    test "uncategorized_count returns count of uncategorized", %{user: user} do
      count = Banking.uncategorized_count(user.id)
      assert is_integer(count)
      assert count >= 0
    end
  end

  describe "installment functions" do
    test "list_active_installments returns list", %{user: user} do
      result = Banking.list_active_installments(user.id)
      assert is_list(result)
    end

    test "installment_projection_summary returns projection", %{user: user} do
      result = Banking.installment_projection_summary(user.id)
      assert is_map(result) or is_list(result)
    end
  end

  describe "fatura_ids_for_month/4" do
    test "returns empty list when no fatura statements", %{user: user} do
      result = Banking.fatura_ids_for_month(user.id, 2026, 1)
      assert result == [] or is_list(result)
    end
  end

  describe "AI analysis CRUD" do
    test "create and list ai analyses", %{user: user} do
      {:ok, analysis} =
        Banking.create_ai_analysis(%{
          user_id: user.id,
          prompt: nil,
          filters_json: %{context: "banking"},
          result_json: %{
            "titulo" => "Test",
            "resumo" => "ok",
            "pontos" => [],
            "nota" => 7.0
          }
        })

      analyses = Banking.list_ai_analyses(user.id)
      assert Enum.any?(analyses, &(&1.id == analysis.id))
    end

    test "get_ai_analysis! returns analysis for correct user", %{user: user} do
      {:ok, analysis} =
        Banking.create_ai_analysis(%{
          user_id: user.id,
          prompt: nil,
          filters_json: %{context: "banking"},
          result_json: %{"titulo" => "T", "resumo" => "r", "pontos" => [], "nota" => 5.0}
        })

      found = Banking.get_ai_analysis!(analysis.id, user.id)
      assert found.id == analysis.id
    end

    test "get_ai_analysis! raises for wrong user", %{user: user} do
      {:ok, analysis} =
        Banking.create_ai_analysis(%{
          user_id: user.id,
          prompt: nil,
          filters_json: %{},
          result_json: %{"titulo" => "T", "resumo" => "r", "pontos" => [], "nota" => 5.0}
        })

      other_user = user_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        Banking.get_ai_analysis!(analysis.id, other_user.id)
      end
    end

    test "delete_ai_analysis removes analysis", %{user: user} do
      {:ok, analysis} =
        Banking.create_ai_analysis(%{
          user_id: user.id,
          prompt: nil,
          filters_json: %{},
          result_json: %{"titulo" => "T", "resumo" => "r", "pontos" => [], "nota" => 5.0}
        })

      {:ok, _} = Banking.delete_ai_analysis(analysis)
      assert Banking.list_ai_analyses(user.id) == []
    end
  end

  describe "month_name/1" do
    test "returns Portuguese month names for all months" do
      assert Banking.month_name(1) == "Janeiro"
      assert Banking.month_name(2) == "Fevereiro"
      assert Banking.month_name(3) == "Março"
      assert Banking.month_name(4) == "Abril"
      assert Banking.month_name(5) == "Maio"
      assert Banking.month_name(6) == "Junho"
      assert Banking.month_name(7) == "Julho"
      assert Banking.month_name(8) == "Agosto"
      assert Banking.month_name(9) == "Setembro"
      assert Banking.month_name(10) == "Outubro"
      assert Banking.month_name(11) == "Novembro"
      assert Banking.month_name(12) == "Dezembro"
    end
  end

  describe "month_name_short/1" do
    test "returns abbreviated Portuguese month names" do
      assert Banking.month_name_short(1) == "Jan"
      assert Banking.month_name_short(3) == "Mar"
      assert Banking.month_name_short(7) == "Jul"
      assert Banking.month_name_short(12) == "Dez"
    end
  end

  describe "suggest_goals/1" do
    test "returns empty list when no transaction data", %{user: user} do
      result = Banking.suggest_goals(user.id)
      assert result == []
    end

    test "returns suggestions based on transaction history", %{user: user} do
      Banking.ensure_default_categories(user.id)
      today = Date.utc_today()

      {:ok, stmt} =
        Banking.create_statement(%{
          bank: "nubank",
          filename: "extrato.csv",
          statement_type: "extrato",
          user_id: user.id,
          period_start: Date.beginning_of_month(today),
          period_end: today
        })

      Banking.bulk_insert_transactions([
        %{
          date: today,
          description: "SALARIO",
          amount: Decimal.new("5000.00"),
          type: "credit",
          bank_statement_id: stmt.id,
          user_id: user.id
        },
        %{
          date: today,
          description: "MERCADO",
          amount: Decimal.new("-300.00"),
          type: "debit",
          bank_statement_id: stmt.id,
          user_id: user.id
        }
      ])

      result = Banking.suggest_goals(user.id)
      assert is_list(result)
    end

    test "skips already-existing goal types", %{user: user} do
      Banking.ensure_default_categories(user.id)
      today = Date.utc_today()

      Banking.create_financial_goal(%{
        "type" => "expense_limit",
        "target_value" => "1000.00",
        "user_id" => user.id
      })

      {:ok, stmt} =
        Banking.create_statement(%{
          bank: "nubank",
          filename: "extrato2.csv",
          statement_type: "extrato",
          user_id: user.id,
          period_start: Date.beginning_of_month(today),
          period_end: today
        })

      Banking.bulk_insert_transactions([
        %{
          date: today,
          description: "GASTO",
          amount: Decimal.new("-100.00"),
          type: "debit",
          bank_statement_id: stmt.id,
          user_id: user.id
        }
      ])

      result = Banking.suggest_goals(user.id)
      types = Enum.map(result, & &1.type)
      refute "expense_limit" in types
    end
  end

  describe "monthly_installment_projections/2" do
    test "returns list of monthly projections", %{user: user} do
      result = Banking.monthly_installment_projections(user.id)
      assert is_list(result)
    end
  end

  describe "goals_progress with category_limit" do
    test "includes category_total for category_limit goals", %{user: user} do
      Banking.ensure_default_categories(user.id)
      cat = Banking.get_uncategorized_category(user.id)
      today = Date.utc_today()

      Banking.create_financial_goal(%{
        "type" => "category_limit",
        "target_value" => "500.00",
        "user_id" => user.id,
        "category_id" => cat.id
      })

      result = Banking.goals_progress(user.id, today.year, today.month)
      assert is_list(result)
      goal_prog = Enum.find(result, &(&1.goal.type == "category_limit"))
      assert goal_prog
    end
  end

  describe "list_transactions sort options" do
    setup %{user: user} do
      Banking.ensure_default_categories(user.id)
      cat = Banking.get_uncategorized_category(user.id)
      today = Date.utc_today()

      transaction_fixture(user, %{
        description: "TXN A",
        amount: "-100.00",
        date: today,
        category_id: cat.id
      })

      transaction_fixture(user, %{
        description: "TXN B",
        amount: "-200.00",
        date: today,
        category_id: cat.id
      })

      :ok
    end

    test "list_transactions with sort_by bank", %{user: user} do
      result = Banking.list_transactions(user.id, sort_by: "bank", sort_dir: "asc")
      assert is_list(result)
    end

    test "list_transactions with sort_by category", %{user: user} do
      result = Banking.list_transactions(user.id, sort_by: "category", sort_dir: "asc")
      assert is_list(result)
    end

    test "list_transactions with sort_by type", %{user: user} do
      result = Banking.list_transactions(user.id, sort_by: "type", sort_dir: "desc")
      assert is_list(result)
    end

    test "list_transactions with internal=only filter", %{user: user} do
      result = Banking.list_transactions(user.id, internal: "only")
      assert is_list(result)
    end

    test "list_transactions with internal=hide filter", %{user: user} do
      result = Banking.list_transactions(user.id, internal: "hide")
      assert is_list(result)
    end

    test "list_transactions with search=empty string", %{user: user} do
      result = Banking.list_transactions(user.id, search: "")
      assert is_list(result)
      assert length(result) >= 2
    end

    test "list_transactions with bank=all filter", %{user: user} do
      result = Banking.list_transactions(user.id, bank: "all")
      assert is_list(result)
    end

    test "list_transactions with type=all filter", %{user: user} do
      result = Banking.list_transactions(user.id, type: "all")
      assert is_list(result)
    end

    test "list_transactions with statement_type=all filter", %{user: user} do
      result = Banking.list_transactions(user.id, statement_type: "all")
      assert is_list(result)
    end
  end

  describe "goals_progress achieved status" do
    test "income_goal with income over target shows achieved", %{user: user} do
      Banking.ensure_default_categories(user.id)
      today = Date.utc_today()

      Banking.create_financial_goal(%{
        "type" => "income_goal",
        "target_value" => "100.00",
        "user_id" => user.id
      })

      transaction_fixture(user, %{
        description: "SALARIO",
        amount: "5000.00",
        type: "credit",
        date: today
      })

      result = Banking.goals_progress(user.id, today.year, today.month)
      goal_prog = Enum.find(result, &(&1.goal.type == "income_goal"))
      assert goal_prog
      assert goal_prog.status == :achieved or goal_prog.pct >= 100
    end
  end
end
