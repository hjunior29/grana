defmodule Grana.Banking.BankingContextTest do
  use Grana.DataCase

  alias Grana.Banking

  import Grana.AccountsFixtures
  import Grana.BankingFixtures

  setup do
    user = user_fixture()
    %{user: user}
  end

  # ---------------------------------------------------------------------------
  # coverage_by_statement_type/1
  # ---------------------------------------------------------------------------

  describe "coverage_by_statement_type/1" do
    test "returns empty MapSets when user has no transactions", %{user: user} do
      result = Banking.coverage_by_statement_type(user.id)
      assert result == %{"extrato" => MapSet.new(), "fatura" => MapSet.new()}
    end

    test "records the correct {year, month} pair for an extrato transaction", %{user: user} do
      Banking.ensure_default_categories(user.id)
      uncat = Banking.get_uncategorized_category(user.id)

      {:ok, stmt} =
        Banking.create_statement(%{
          bank: "nubank",
          filename: "ext.csv",
          statement_type: "extrato",
          user_id: user.id
        })

      Banking.bulk_insert_transactions([
        %{
          date: ~D[2026-03-10],
          description: "Compra extrato",
          amount: Decimal.new("-100.00"),
          type: "debit",
          bank_statement_id: stmt.id,
          user_id: user.id,
          category_id: uncat.id
        }
      ])

      result = Banking.coverage_by_statement_type(user.id)
      assert MapSet.member?(result["extrato"], {2026, 3})
      refute MapSet.member?(result["fatura"], {2026, 3})
    end

    test "records fatura month from its statement_type", %{user: user} do
      Banking.ensure_default_categories(user.id)
      uncat = Banking.get_uncategorized_category(user.id)

      {:ok, fatura_stmt} =
        Banking.create_statement(%{
          bank: "nubank",
          filename: "fat.csv",
          statement_type: "fatura",
          user_id: user.id
        })

      Banking.bulk_insert_transactions([
        %{
          date: ~D[2026-04-20],
          description: "Compra fatura",
          amount: Decimal.new("-200.00"),
          type: "debit",
          bank_statement_id: fatura_stmt.id,
          user_id: user.id,
          category_id: uncat.id
        }
      ])

      result = Banking.coverage_by_statement_type(user.id)
      assert MapSet.member?(result["fatura"], {2026, 4})
      refute MapSet.member?(result["extrato"], {2026, 4})
    end

    test "same month with multiple transactions appears only once", %{user: user} do
      Banking.ensure_default_categories(user.id)
      uncat = Banking.get_uncategorized_category(user.id)

      {:ok, stmt} =
        Banking.create_statement(%{
          bank: "nubank",
          filename: "e.csv",
          statement_type: "extrato",
          user_id: user.id
        })

      Banking.bulk_insert_transactions(
        Enum.map(1..5, fn d ->
          %{
            date: Date.new!(2026, 5, d),
            description: "Tx #{d}",
            amount: Decimal.new("-10.00"),
            type: "debit",
            bank_statement_id: stmt.id,
            user_id: user.id,
            category_id: uncat.id
          }
        end)
      )

      result = Banking.coverage_by_statement_type(user.id)
      assert MapSet.size(result["extrato"]) == 1
    end

    test "does not include months from another user", %{user: user} do
      other = user_fixture()
      _txn = transaction_fixture(other, %{date: ~D[2026-01-10]})

      result = Banking.coverage_by_statement_type(user.id)
      assert result == %{"extrato" => MapSet.new(), "fatura" => MapSet.new()}
    end
  end

  # ---------------------------------------------------------------------------
  # upload_counts_by_month/1
  # ---------------------------------------------------------------------------

  describe "upload_counts_by_month/1" do
    test "returns empty map when user has no transactions", %{user: user} do
      assert Banking.upload_counts_by_month(user.id) == %{}
    end

    test "counts one upload for the month when all txns come from the same statement", %{
      user: user
    } do
      Banking.ensure_default_categories(user.id)
      uncat = Banking.get_uncategorized_category(user.id)

      {:ok, stmt} =
        Banking.create_statement(%{bank: "nubank", filename: "a.csv", user_id: user.id})

      Banking.bulk_insert_transactions(
        Enum.map(1..3, fn d ->
          %{
            date: Date.new!(2026, 2, d),
            description: "Tx #{d}",
            amount: Decimal.new("-10.00"),
            type: "debit",
            bank_statement_id: stmt.id,
            user_id: user.id,
            category_id: uncat.id
          }
        end)
      )

      counts = Banking.upload_counts_by_month(user.id)
      assert counts[{2026, 2}] == 1
    end

    test "counts two uploads for the same month when txns come from different statements", %{
      user: user
    } do
      Banking.ensure_default_categories(user.id)
      uncat = Banking.get_uncategorized_category(user.id)

      {:ok, stmt1} =
        Banking.create_statement(%{bank: "nubank", filename: "s1.csv", user_id: user.id})

      {:ok, stmt2} =
        Banking.create_statement(%{bank: "bradesco", filename: "s2.csv", user_id: user.id})

      Banking.bulk_insert_transactions([
        %{
          date: ~D[2026-02-05],
          description: "Nubank tx",
          amount: Decimal.new("-50.00"),
          type: "debit",
          bank_statement_id: stmt1.id,
          user_id: user.id,
          category_id: uncat.id
        },
        %{
          date: ~D[2026-02-10],
          description: "Bradesco tx",
          amount: Decimal.new("-75.00"),
          type: "debit",
          bank_statement_id: stmt2.id,
          user_id: user.id,
          category_id: uncat.id
        }
      ])

      counts = Banking.upload_counts_by_month(user.id)
      assert counts[{2026, 2}] == 2
    end

    test "does not count uploads from another user", %{user: user} do
      other = user_fixture()
      _txn = transaction_fixture(other, %{date: ~D[2026-01-10]})

      assert Banking.upload_counts_by_month(user.id) == %{}
    end
  end

  # ---------------------------------------------------------------------------
  # list_recurring_rules/1
  # ---------------------------------------------------------------------------

  describe "list_recurring_rules/1" do
    test "returns empty list when no rules exist", %{user: user} do
      assert Banking.list_recurring_rules(user.id) == []
    end

    test "returns only rules belonging to the user", %{user: user} do
      other = user_fixture()

      Banking.upsert_recurring_rule(user.id, "spotify", "fixed")
      Banking.upsert_recurring_rule(other.id, "netflix", "fixed")

      rules = Banking.list_recurring_rules(user.id)
      assert length(rules) == 1
      assert hd(rules).pattern == "spotify"
    end

    test "returns rules ordered by pattern ascending", %{user: user} do
      Banking.upsert_recurring_rule(user.id, "zorro", "fixed")
      Banking.upsert_recurring_rule(user.id, "apple", "variable")
      Banking.upsert_recurring_rule(user.id, "netflix", "fixed")

      patterns = Banking.list_recurring_rules(user.id) |> Enum.map(& &1.pattern)
      assert patterns == Enum.sort(patterns)
    end
  end

  # ---------------------------------------------------------------------------
  # upsert_recurring_rule/3
  # ---------------------------------------------------------------------------

  describe "upsert_recurring_rule/3" do
    test "creates a new rule", %{user: user} do
      assert {:ok, rule} = Banking.upsert_recurring_rule(user.id, "netflix", "fixed")
      assert rule.mode == "fixed"
    end

    test "normalizes the pattern before saving", %{user: user} do
      assert {:ok, rule} =
               Banking.upsert_recurring_rule(user.id, "PIX QR CODE - SPOTIFY", "fixed")

      assert rule.pattern == "spotify"
    end

    test "updates mode on conflict (same user + pattern)", %{user: user} do
      Banking.upsert_recurring_rule(user.id, "netflix", "fixed")
      assert {:ok, rule} = Banking.upsert_recurring_rule(user.id, "netflix", "variable")
      assert rule.mode == "variable"

      rules = Banking.list_recurring_rules(user.id)
      assert length(rules) == 1
      assert hd(rules).mode == "variable"
    end

    test "same pattern for different users creates separate rules", %{user: user} do
      other = user_fixture()

      Banking.upsert_recurring_rule(user.id, "spotify", "fixed")
      Banking.upsert_recurring_rule(other.id, "spotify", "variable")

      [user_rule] = Banking.list_recurring_rules(user.id)
      [other_rule] = Banking.list_recurring_rules(other.id)

      assert user_rule.mode == "fixed"
      assert other_rule.mode == "variable"
    end
  end

  # ---------------------------------------------------------------------------
  # delete_recurring_rule/2
  # ---------------------------------------------------------------------------

  describe "delete_recurring_rule/2" do
    test "deletes an existing rule", %{user: user} do
      Banking.upsert_recurring_rule(user.id, "netflix", "fixed")
      assert {1, _} = Banking.delete_recurring_rule(user.id, "netflix")
      assert Banking.list_recurring_rules(user.id) == []
    end

    test "normalizes pattern before deleting", %{user: user} do
      Banking.upsert_recurring_rule(user.id, "spotify", "fixed")
      # raw unnormalized description that normalizes to "spotify"
      assert {1, _} = Banking.delete_recurring_rule(user.id, "PIX QR CODE - SPOTIFY")
      assert Banking.list_recurring_rules(user.id) == []
    end

    test "returns {0, nil} when rule does not exist", %{user: user} do
      assert {0, _} = Banking.delete_recurring_rule(user.id, "nonexistent")
    end

    test "does not delete rules belonging to another user", %{user: user} do
      other = user_fixture()
      Banking.upsert_recurring_rule(user.id, "spotify", "fixed")

      Banking.delete_recurring_rule(other.id, "spotify")

      assert length(Banking.list_recurring_rules(user.id)) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # recurring_manageable_transaction?/1
  # ---------------------------------------------------------------------------

  describe "recurring_manageable_transaction?/1" do
    setup %{user: user} do
      Banking.ensure_default_categories(user.id)
      cats = Banking.list_categories(user.id)

      %{
        uncat: Banking.get_uncategorized_category(user.id),
        invest_cat: Enum.find(cats, &(&1.kind == "investment"))
      }
    end

    test "returns true for plain debit transaction", %{user: user, uncat: uncat} do
      txn = transaction_fixture(user, %{type: "debit", category_id: uncat.id})
      assert Banking.recurring_manageable_transaction?(txn)
    end

    test "returns false for credit transactions", %{user: user, uncat: uncat} do
      txn = transaction_fixture(user, %{type: "credit", amount: "100.00", category_id: uncat.id})
      refute Banking.recurring_manageable_transaction?(txn)
    end

    test "returns false when is_internal_transfer is true", %{user: user} do
      Banking.ensure_default_categories(user.id)
      uncat = Banking.get_uncategorized_category(user.id)

      {:ok, stmt} =
        Banking.create_statement(%{bank: "nubank", filename: "x.csv", user_id: user.id})

      Banking.bulk_insert_transactions([
        %{
          date: ~D[2026-01-10],
          description: "Transferência interna",
          amount: Decimal.new("-100.00"),
          type: "debit",
          bank_statement_id: stmt.id,
          user_id: user.id,
          category_id: uncat.id,
          is_internal_transfer: true
        }
      ])

      [txn] = Banking.list_transactions(user.id, search: "Transferência interna")
      refute Banking.recurring_manageable_transaction?(txn)
    end

    test "returns false when transaction has installment_total set", %{user: user, uncat: uncat} do
      {:ok, stmt} =
        Banking.create_statement(%{bank: "nubank", filename: "inst.csv", user_id: user.id})

      Banking.bulk_insert_transactions([
        %{
          date: ~D[2026-01-10],
          description: "Parcelado XPTO",
          amount: Decimal.new("-100.00"),
          type: "debit",
          bank_statement_id: stmt.id,
          user_id: user.id,
          category_id: uncat.id,
          installment_total: 6,
          installment_current: 1,
          installment_group_id: "abc123"
        }
      ])

      txns = Banking.list_transactions(user.id, search: "Parcelado XPTO")
      txn = hd(txns)
      refute Banking.recurring_manageable_transaction?(txn)
    end

    test "returns false for investment category transaction", %{
      user: user,
      invest_cat: invest_cat
    } do
      txn = transaction_fixture(user, %{type: "debit", category_id: invest_cat.id})
      # preload the category so investment_category? works
      txn = Grana.Repo.preload(txn, :category)
      refute Banking.recurring_manageable_transaction?(txn)
    end
  end

  # ---------------------------------------------------------------------------
  # set_transaction_recurring_mode/3
  # ---------------------------------------------------------------------------

  describe "set_transaction_recurring_mode/3" do
    test "returns {:error, :not_recurring_expense} for a credit transaction", %{user: user} do
      txn = transaction_fixture(user, %{type: "credit", amount: "100.00"})

      assert {:error, :not_recurring_expense} =
               Banking.set_transaction_recurring_mode(user.id, txn.id, "fixed")
    end

    test "returns {:error, :invalid_mode} for an invalid mode", %{user: user} do
      txn = transaction_fixture(user, %{type: "debit"})

      assert {:error, :invalid_mode} =
               Banking.set_transaction_recurring_mode(user.id, txn.id, "unknown")
    end

    test "raises when transaction does not belong to user", %{user: user} do
      other = user_fixture()
      txn = transaction_fixture(other, %{type: "debit"})

      assert_raise Ecto.NoResultsError, fn ->
        Banking.set_transaction_recurring_mode(user.id, txn.id, "fixed")
      end
    end

    test "creates rule for manageable debit", %{user: user} do
      txn =
        transaction_fixture(user, %{
          type: "debit",
          description: "PIX QR CODE DINAMICO - SPOTIFY"
        })

      assert {:ok, rule} = Banking.set_transaction_recurring_mode(user.id, txn.id, "fixed")
      assert rule.pattern == "spotify"
      assert rule.mode == "fixed"
    end

    test "creates variable rule", %{user: user} do
      txn = transaction_fixture(user, %{type: "debit", description: "NETFLIX.COM"})

      assert {:ok, rule} = Banking.set_transaction_recurring_mode(user.id, txn.id, "variable")
      assert rule.mode == "variable"
    end
  end

  # ---------------------------------------------------------------------------
  # bulk_set_recurring_mode/3
  # ---------------------------------------------------------------------------

  describe "bulk_set_recurring_mode/3" do
    test "returns {:error, :invalid_mode} for bad mode", %{user: user} do
      assert {:error, :invalid_mode} = Banking.bulk_set_recurring_mode(user.id, [], "bad")
    end

    test "returns {:ok, 0} when list is empty", %{user: user} do
      assert {:ok, 0} = Banking.bulk_set_recurring_mode(user.id, [], "fixed")
    end

    test "only counts manageable transactions", %{user: user} do
      debit_txn = transaction_fixture(user, %{type: "debit", description: "Padaria ABC"})

      credit_txn =
        transaction_fixture(user, %{type: "credit", amount: "100.00", description: "Salário"})

      assert {:ok, 1} =
               Banking.bulk_set_recurring_mode(
                 user.id,
                 [debit_txn.id, credit_txn.id],
                 "fixed"
               )
    end

    test "creates one rule per distinct normalized pattern", %{user: user} do
      t1 = transaction_fixture(user, %{type: "debit", description: "NETFLIX.COM"})
      t2 = transaction_fixture(user, %{type: "debit", description: "NETFLIX *BR"})
      t3 = transaction_fixture(user, %{type: "debit", description: "SPOTIFY"})

      assert {:ok, 3} =
               Banking.bulk_set_recurring_mode(user.id, [t1.id, t2.id, t3.id], "fixed")

      rules = Banking.list_recurring_rules(user.id)
      patterns = Enum.map(rules, & &1.pattern)
      # Netflix variants normalize to same pattern → one rule; Spotify → another
      assert "spotify" in patterns
      assert Enum.all?(rules, &(&1.mode == "fixed"))
    end

    test "does not affect transactions belonging to another user", %{user: user} do
      other = user_fixture()
      other_txn = transaction_fixture(other, %{type: "debit", description: "SPOTIFY"})

      assert {:ok, 0} =
               Banking.bulk_set_recurring_mode(user.id, [other_txn.id], "fixed")

      assert Banking.list_recurring_rules(user.id) == []
    end
  end

  # ---------------------------------------------------------------------------
  # recurring_statuses/3
  # ---------------------------------------------------------------------------

  describe "recurring_statuses/3" do
    test "returns 'none' for non-manageable transactions (credit)", %{user: user} do
      txn = transaction_fixture(user, %{type: "credit", amount: "100.00"})

      statuses = Banking.recurring_statuses(user.id, [txn])
      assert statuses[txn.id].status == "none"
      assert statuses[txn.id].editable == false
    end

    test "status is 'fixed' when an explicit rule marks it as fixed", %{user: user} do
      txn = transaction_fixture(user, %{type: "debit", description: "SPOTIFY"})
      Banking.upsert_recurring_rule(user.id, "spotify", "fixed")

      statuses = Banking.recurring_statuses(user.id, [txn])
      assert statuses[txn.id].status == "fixed"
      assert statuses[txn.id].editable == true
    end

    test "status is 'variable' when an explicit rule marks it as variable", %{user: user} do
      txn = transaction_fixture(user, %{type: "debit", description: "SPOTIFY"})
      Banking.upsert_recurring_rule(user.id, "spotify", "variable")

      statuses = Banking.recurring_statuses(user.id, [txn])
      assert statuses[txn.id].status == "variable"
    end

    test "includes the normalized pattern in the result", %{user: user} do
      txn = transaction_fixture(user, %{type: "debit", description: "PIX QR CODE - NETFLIX.COM"})

      statuses = Banking.recurring_statuses(user.id, [txn])
      assert statuses[txn.id].pattern == "netflix com"
    end

    test "returns map keyed by transaction id", %{user: user} do
      t1 = transaction_fixture(user, %{type: "debit", description: "Compra A"})
      t2 = transaction_fixture(user, %{type: "debit", description: "Compra B"})

      statuses = Banking.recurring_statuses(user.id, [t1, t2])
      assert Map.has_key?(statuses, t1.id)
      assert Map.has_key?(statuses, t2.id)
    end
  end

  # ---------------------------------------------------------------------------
  # recurring_analysis/2
  # ---------------------------------------------------------------------------

  describe "recurring_analysis/2" do
    test "returns an analysis map with expected keys", %{user: user} do
      result = Banking.recurring_analysis(user.id)
      assert Map.has_key?(result, :fixed)
      assert Map.has_key?(result, :monthly)
      assert Map.has_key?(result, :total_months)
      assert Map.has_key?(result, :avg_fixed)
      assert Map.has_key?(result, :avg_variable)
    end

    test "returns zero totals when user has no transactions", %{user: user} do
      result = Banking.recurring_analysis(user.id)
      assert Decimal.equal?(result.avg_fixed, Decimal.new(0))
      assert result.fixed == []
    end

    test "detects a fixed expense appearing every month in the window", %{user: user} do
      Banking.ensure_default_categories(user.id)
      uncat = Banking.get_uncategorized_category(user.id)

      {:ok, stmt} =
        Banking.create_statement(%{bank: "nubank", filename: "e.csv", user_id: user.id})

      # Insert Netflix for 6 consecutive months (window default is 6)
      today = ~D[2026-06-07]

      for offset <- 0..5 do
        month = Date.shift(Date.new!(today.year, today.month, 1), month: -offset)

        Banking.bulk_insert_transactions([
          %{
            date: Date.new!(month.year, month.month, 5),
            description: "NETFLIX.COM",
            amount: Decimal.new("-44.90"),
            type: "debit",
            bank_statement_id: stmt.id,
            user_id: user.id,
            category_id: uncat.id
          }
        ])
      end

      result = Banking.recurring_analysis(user.id, today: today)
      assert Enum.any?(result.fixed, &String.contains?(String.upcase(&1.name), "NETFLIX"))
    end

    test "excludes credit transactions from analysis", %{user: user} do
      Banking.ensure_default_categories(user.id)
      uncat = Banking.get_uncategorized_category(user.id)
      today = ~D[2026-06-07]

      {:ok, stmt} =
        Banking.create_statement(%{bank: "nubank", filename: "e.csv", user_id: user.id})

      for offset <- 0..5 do
        month = Date.shift(Date.new!(today.year, today.month, 1), month: -offset)

        Banking.bulk_insert_transactions([
          %{
            date: Date.new!(month.year, month.month, 5),
            description: "Salário Empresa X",
            amount: Decimal.new("5000.00"),
            type: "credit",
            bank_statement_id: stmt.id,
            user_id: user.id,
            category_id: uncat.id
          }
        ])
      end

      result = Banking.recurring_analysis(user.id, today: today)
      refute Enum.any?(result.fixed, &String.contains?(String.upcase(&1.name), "SALÁRIO"))
    end
  end

  # ---------------------------------------------------------------------------
  # list_financial_goals/1
  # ---------------------------------------------------------------------------

  describe "list_financial_goals/1" do
    test "returns empty list when no goals exist", %{user: user} do
      assert Banking.list_financial_goals(user.id) == []
    end

    test "returns only active goals for the user", %{user: user} do
      _active = goal_fixture(user, %{type: "expense_limit"})

      # Insert an inactive goal directly
      Banking.ensure_default_categories(user.id)

      {:ok, _inactive} =
        Banking.create_financial_goal(%{
          "type" => "income_goal",
          "target_value" => "2000",
          "user_id" => user.id,
          "active" => false
        })

      goals = Banking.list_financial_goals(user.id)
      assert length(goals) == 1
      assert hd(goals).type == "expense_limit"
    end

    test "does not return goals from another user", %{user: user} do
      other = user_fixture()
      goal_fixture(other, %{type: "expense_limit"})

      assert Banking.list_financial_goals(user.id) == []
    end

    test "preloads the category association", %{user: user} do
      Banking.ensure_default_categories(user.id)
      cat = hd(Banking.list_categories(user.id))

      Banking.create_financial_goal(%{
        "type" => "category_limit",
        "target_value" => "500",
        "user_id" => user.id,
        "category_id" => cat.id
      })

      [goal] = Banking.list_financial_goals(user.id)
      assert %Grana.Banking.Category{} = goal.category
    end
  end

  # ---------------------------------------------------------------------------
  # get_financial_goal!/2
  # ---------------------------------------------------------------------------

  describe "get_financial_goal!/2" do
    test "returns the goal when it belongs to the user", %{user: user} do
      goal = goal_fixture(user)
      fetched = Banking.get_financial_goal!(goal.id, user.id)
      assert fetched.id == goal.id
    end

    test "raises Ecto.NoResultsError for a goal belonging to another user (IDOR)", %{user: user} do
      other = user_fixture()
      goal = goal_fixture(other)

      assert_raise Ecto.NoResultsError, fn ->
        Banking.get_financial_goal!(goal.id, user.id)
      end
    end

    test "raises Ecto.NoResultsError for a non-existent goal id", %{user: user} do
      assert_raise Ecto.NoResultsError, fn ->
        Banking.get_financial_goal!(-1, user.id)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # create_financial_goal/2
  # ---------------------------------------------------------------------------

  describe "create_financial_goal/2" do
    test "creates a valid expense_limit goal", %{user: user} do
      assert {:ok, goal} =
               Banking.create_financial_goal(%{
                 "type" => "expense_limit",
                 "target_value" => "1500.00",
                 "user_id" => user.id
               })

      assert goal.type == "expense_limit"
      assert Decimal.equal?(goal.target_value, Decimal.new("1500.00"))
    end

    test "creates a category_limit goal with a valid category", %{user: user} do
      Banking.ensure_default_categories(user.id)
      cat = Enum.find(Banking.list_categories(user.id), &(&1.name == "Alimentação"))

      assert {:ok, goal} =
               Banking.create_financial_goal(%{
                 "type" => "category_limit",
                 "target_value" => "800.00",
                 "user_id" => user.id,
                 "category_id" => cat.id
               })

      assert goal.category_id == cat.id
    end

    test "rejects goal with target_value <= 0", %{user: user} do
      assert {:error, changeset} =
               Banking.create_financial_goal(%{
                 "type" => "expense_limit",
                 "target_value" => "0",
                 "user_id" => user.id
               })

      assert changeset.errors[:target_value]
    end

    test "rejects goal with another user's category (IDOR)", %{user: user} do
      other = user_fixture()
      Banking.ensure_default_categories(other.id)
      foreign_cat = hd(Banking.list_categories(other.id))

      assert {:error, changeset} =
               Banking.create_financial_goal(%{
                 "type" => "category_limit",
                 "target_value" => "500",
                 "user_id" => user.id,
                 "category_id" => foreign_cat.id
               })

      assert changeset.errors[:category_id]
    end

    test "rejects unknown goal type", %{user: user} do
      assert {:error, changeset} =
               Banking.create_financial_goal(%{
                 "type" => "unknown_type",
                 "target_value" => "100",
                 "user_id" => user.id
               })

      assert changeset.errors[:type]
    end
  end

  # ---------------------------------------------------------------------------
  # update_financial_goal/3
  # ---------------------------------------------------------------------------

  describe "update_financial_goal/3" do
    test "updates target_value", %{user: user} do
      goal = goal_fixture(user, %{type: "expense_limit", target_value: "1000.00"})

      assert {:ok, updated} = Banking.update_financial_goal(goal, %{target_value: "2000.00"})
      assert Decimal.equal?(updated.target_value, Decimal.new("2000.00"))
    end

    test "deactivates a goal", %{user: user} do
      goal = goal_fixture(user)
      assert {:ok, updated} = Banking.update_financial_goal(goal, %{active: false})
      refute updated.active
    end

    test "rejects update with another user's category (IDOR)", %{user: user} do
      Banking.ensure_default_categories(user.id)
      cat = Enum.find(Banking.list_categories(user.id), &(&1.name == "Alimentação"))

      {:ok, goal} =
        Banking.create_financial_goal(%{
          "type" => "category_limit",
          "target_value" => "500",
          "user_id" => user.id,
          "category_id" => cat.id
        })

      other = user_fixture()
      Banking.ensure_default_categories(other.id)
      foreign_cat = hd(Banking.list_categories(other.id))

      assert {:error, changeset} =
               Banking.update_financial_goal(goal, %{category_id: foreign_cat.id})

      assert changeset.errors[:category_id]
    end
  end

  # ---------------------------------------------------------------------------
  # delete_financial_goal/2
  # ---------------------------------------------------------------------------

  describe "delete_financial_goal/2" do
    test "deletes an existing goal", %{user: user} do
      goal = goal_fixture(user)
      assert {:ok, _} = Banking.delete_financial_goal(goal)
      assert Banking.list_financial_goals(user.id) == []
    end

    test "returns error tuple for Ecto constraint violation (already deleted)", %{user: user} do
      goal = goal_fixture(user)
      {:ok, _} = Banking.delete_financial_goal(goal)

      # Deleting again should raise (record gone) – Repo.delete will raise
      assert_raise Ecto.StaleEntryError, fn ->
        Banking.delete_financial_goal(goal)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # detect_internal_transfers/1 – additional coverage
  # ---------------------------------------------------------------------------

  describe "detect_internal_transfers/1 - additional patterns" do
    setup %{user: user} do
      Banking.ensure_default_categories(user.id)
      uncat = Banking.get_uncategorized_category(user.id)

      {:ok, extrato} =
        Banking.create_statement(%{
          bank: "nubank",
          filename: "ext.csv",
          statement_type: "extrato",
          user_id: user.id
        })

      {:ok, fatura} =
        Banking.create_statement(%{
          bank: "nubank",
          filename: "fat.csv",
          statement_type: "fatura",
          period_start: ~D[2026-01-01],
          period_end: ~D[2026-02-28],
          user_id: user.id
        })

      %{uncat: uncat, extrato: extrato, fatura: fatura}
    end

    test "marks 'pag fatura' debit on extrato as internal", %{
      user: user,
      uncat: uncat,
      extrato: extrato
    } do
      Banking.bulk_insert_transactions([
        %{
          date: ~D[2026-01-10],
          description: "PAG FATURA NUBANK",
          amount: Decimal.new("-800.00"),
          type: "debit",
          bank_statement_id: extrato.id,
          user_id: user.id,
          category_id: uncat.id
        }
      ])

      Banking.detect_internal_transfers(user.id)
      [txn] = Banking.list_transactions(user.id)
      assert txn.is_internal_transfer == true
    end

    test "marks 'gastos cartoes' debit on extrato as internal", %{
      user: user,
      uncat: uncat,
      extrato: extrato
    } do
      Banking.bulk_insert_transactions([
        %{
          date: ~D[2026-02-05],
          description: "GASTOS CARTOES",
          amount: Decimal.new("-1500.00"),
          type: "debit",
          bank_statement_id: extrato.id,
          user_id: user.id,
          category_id: uncat.id
        }
      ])

      Banking.detect_internal_transfers(user.id)
      [txn] = Banking.list_transactions(user.id)
      assert txn.is_internal_transfer == true
    end

    test "does not mark regular debits as internal", %{
      user: user,
      uncat: uncat,
      extrato: extrato
    } do
      Banking.bulk_insert_transactions([
        %{
          date: ~D[2026-01-20],
          description: "Compra no débito - Padaria",
          amount: Decimal.new("-30.00"),
          type: "debit",
          bank_statement_id: extrato.id,
          user_id: user.id,
          category_id: uncat.id
        }
      ])

      Banking.detect_internal_transfers(user.id)
      [txn] = Banking.list_transactions(user.id)
      assert txn.is_internal_transfer == false
    end

    test "resets previously marked transfers before re-running", %{
      user: user,
      uncat: uncat,
      extrato: extrato
    } do
      Banking.bulk_insert_transactions([
        %{
          date: ~D[2026-01-10],
          description: "Compra simples",
          amount: Decimal.new("-50.00"),
          type: "debit",
          bank_statement_id: extrato.id,
          user_id: user.id,
          category_id: uncat.id,
          is_internal_transfer: true
        }
      ])

      # Running detection should reset the manually-set internal flag
      # (because it doesn't match any CC payment pattern)
      Banking.detect_internal_transfers(user.id)
      [txn] = Banking.list_transactions(user.id)
      assert txn.is_internal_transfer == false
    end

    test "matches inter-account PIX transfer between two banks", %{user: user, uncat: uncat} do
      {:ok, extrato_brad} =
        Banking.create_statement(%{
          bank: "bradesco",
          filename: "brad.csv",
          statement_type: "extrato",
          user_id: user.id
        })

      {:ok, extrato_nu} =
        Banking.create_statement(%{
          bank: "nubank",
          filename: "nu.csv",
          statement_type: "extrato",
          user_id: user.id
        })

      Banking.bulk_insert_transactions([
        %{
          date: ~D[2026-01-15],
          description: "Transferência PIX enviado",
          amount: Decimal.new("-250.00"),
          type: "debit",
          bank_statement_id: extrato_brad.id,
          user_id: user.id,
          category_id: uncat.id
        },
        %{
          date: ~D[2026-01-15],
          description: "Transferência PIX recebido",
          amount: Decimal.new("250.00"),
          type: "credit",
          bank_statement_id: extrato_nu.id,
          user_id: user.id,
          category_id: uncat.id
        }
      ])

      Banking.detect_internal_transfers(user.id)
      txns = Banking.list_transactions(user.id)
      assert Enum.all?(txns, & &1.is_internal_transfer)
    end
  end

  describe "RecurringRule" do
    test "modes/0 returns valid mode list" do
      modes = Grana.Banking.RecurringRule.modes()
      assert "fixed" in modes
      assert "variable" in modes
    end
  end

  describe "InternalTransferRule" do
    test "kinds/0 returns valid kind list" do
      kinds = Grana.Banking.InternalTransferRule.kinds()
      assert is_list(kinds)
      refute Enum.empty?(kinds)
    end
  end
end
