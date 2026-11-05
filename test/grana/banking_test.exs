defmodule Grana.BankingTest do
  use Grana.DataCase

  alias Grana.Banking

  import Grana.AccountsFixtures

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "categories" do
    test "ensure_default_categories creates system categories", %{user: user} do
      categories = Banking.ensure_default_categories(user.id)
      assert length(categories) >= 13

      names = Enum.map(categories, & &1.name)
      assert "Alimentação" in names
      assert "Sem Categoria" in names
      assert "Transferências" in names
    end

    test "ensure_default_categories is idempotent", %{user: user} do
      cats1 = Banking.ensure_default_categories(user.id)
      cats2 = Banking.ensure_default_categories(user.id)
      assert length(cats1) == length(cats2)
    end

    test "list_categories returns user and system categories", %{user: user} do
      Banking.ensure_default_categories(user.id)
      categories = Banking.list_categories(user.id)
      assert length(categories) >= 13
    end

    test "get_uncategorized_category returns the uncategorized category", %{user: user} do
      Banking.ensure_default_categories(user.id)
      cat = Banking.get_uncategorized_category(user.id)
      assert cat.name == "Sem Categoria"
    end
  end

  describe "bank_statements" do
    test "create_statement creates a statement", %{user: user} do
      {:ok, stmt} =
        Banking.create_statement(%{
          bank: "nubank",
          filename: "test.csv",
          user_id: user.id
        })

      assert stmt.bank == "nubank"
      assert stmt.filename == "test.csv"
      assert stmt.status == "processing"
    end

    test "list_statements returns user statements", %{user: user} do
      Banking.create_statement(%{bank: "nubank", filename: "a.csv", user_id: user.id})
      Banking.create_statement(%{bank: "bradesco", filename: "b.csv", user_id: user.id})

      statements = Banking.list_statements(user.id)
      assert length(statements) == 2
    end

    test "delete_statement removes statement and transactions", %{user: user} do
      {:ok, stmt} =
        Banking.create_statement(%{bank: "nubank", filename: "test.csv", user_id: user.id})

      Banking.ensure_default_categories(user.id)
      uncat = Banking.get_uncategorized_category(user.id)

      Banking.bulk_insert_transactions([
        %{
          date: ~D[2026-01-01],
          description: "Test",
          amount: Decimal.new("-10.00"),
          type: "debit",
          bank_statement_id: stmt.id,
          user_id: user.id,
          category_id: uncat.id
        }
      ])

      {:ok, _} = Banking.delete_statement(stmt)
      assert Banking.list_statements(user.id) == []
      assert Banking.list_transactions(user.id) == []
    end
  end

  describe "transactions" do
    setup %{user: user} do
      Banking.ensure_default_categories(user.id)

      {:ok, stmt} =
        Banking.create_statement(%{bank: "nubank", filename: "test.csv", user_id: user.id})

      uncat = Banking.get_uncategorized_category(user.id)
      food_cat = Enum.find(Banking.list_categories(user.id), &(&1.name == "Alimentação"))

      %{statement: stmt, uncat: uncat, food_cat: food_cat}
    end

    test "bulk_insert_transactions inserts multiple transactions", %{
      user: user,
      statement: stmt,
      uncat: uncat
    } do
      entries =
        Enum.map(1..5, fn i ->
          %{
            date: Date.new!(2026, 1, i),
            description: "Transaction #{i}",
            amount: Decimal.new("-#{i * 10}.00"),
            type: "debit",
            bank_statement_id: stmt.id,
            user_id: user.id,
            category_id: uncat.id
          }
        end)

      {count, _} = Banking.bulk_insert_transactions(entries)
      assert count == 5
    end

    test "list_transactions returns transactions with preloads", %{
      user: user,
      statement: stmt,
      uncat: uncat
    } do
      Banking.bulk_insert_transactions([
        %{
          date: ~D[2026-01-15],
          description: "Test",
          amount: Decimal.new("-50.00"),
          type: "debit",
          bank_statement_id: stmt.id,
          user_id: user.id,
          category_id: uncat.id
        }
      ])

      [txn] = Banking.list_transactions(user.id)
      assert txn.category != nil
      assert txn.bank_statement != nil
    end

    test "list_transactions filters by uncategorized", %{
      user: user,
      statement: stmt,
      uncat: uncat,
      food_cat: food_cat
    } do
      Banking.bulk_insert_transactions([
        %{
          date: ~D[2026-01-01],
          description: "Uncategorized",
          amount: Decimal.new("-10.00"),
          type: "debit",
          bank_statement_id: stmt.id,
          user_id: user.id,
          category_id: uncat.id
        },
        %{
          date: ~D[2026-01-02],
          description: "Food",
          amount: Decimal.new("-20.00"),
          type: "debit",
          bank_statement_id: stmt.id,
          user_id: user.id,
          category_id: food_cat.id
        }
      ])

      uncategorized = Banking.list_transactions(user.id, uncategorized: true)
      assert length(uncategorized) == 1
      assert Enum.at(uncategorized, 0).description == "Uncategorized"
    end

    test "list_transactions filters by search", %{
      user: user,
      statement: stmt,
      uncat: uncat
    } do
      Banking.bulk_insert_transactions([
        %{
          date: ~D[2026-01-01],
          description: "Supermercado ABC",
          amount: Decimal.new("-50.00"),
          type: "debit",
          bank_statement_id: stmt.id,
          user_id: user.id,
          category_id: uncat.id
        },
        %{
          date: ~D[2026-01-02],
          description: "Restaurante XYZ",
          amount: Decimal.new("-30.00"),
          type: "debit",
          bank_statement_id: stmt.id,
          user_id: user.id,
          category_id: uncat.id
        }
      ])

      results = Banking.list_transactions(user.id, search: "supermercado")
      assert length(results) == 1
    end

    test "update_transaction changes category", %{
      user: user,
      statement: stmt,
      uncat: uncat,
      food_cat: food_cat
    } do
      Banking.bulk_insert_transactions([
        %{
          date: ~D[2026-01-01],
          description: "Test",
          amount: Decimal.new("-10.00"),
          type: "debit",
          bank_statement_id: stmt.id,
          user_id: user.id,
          category_id: uncat.id
        }
      ])

      [txn] = Banking.list_transactions(user.id)
      {:ok, updated} = Banking.update_transaction(txn, %{category_id: food_cat.id})
      assert updated.category_id == food_cat.id
    end

    test "list_transactions_paginated sorts by requested column", %{
      user: user,
      statement: stmt,
      uncat: uncat
    } do
      Banking.bulk_insert_transactions([
        %{
          date: ~D[2026-01-02],
          description: "Beta",
          amount: Decimal.new("-20.00"),
          type: "debit",
          bank_statement_id: stmt.id,
          user_id: user.id,
          category_id: uncat.id
        },
        %{
          date: ~D[2026-01-01],
          description: "Alpha",
          amount: Decimal.new("-50.00"),
          type: "debit",
          bank_statement_id: stmt.id,
          user_id: user.id,
          category_id: uncat.id
        }
      ])

      {by_description, 2} =
        Banking.list_transactions_paginated(user.id,
          sort_by: "description",
          sort_dir: "asc"
        )

      assert Enum.map(by_description, & &1.description) == ["Alpha", "Beta"]

      {by_amount, 2} =
        Banking.list_transactions_paginated(user.id,
          sort_by: "amount",
          sort_dir: "desc"
        )

      assert Enum.map(by_amount, & &1.description) == ["Alpha", "Beta"]
    end

    test "set_transaction_recurring_mode creates a rule from transaction merchant", %{
      user: user,
      statement: stmt,
      uncat: uncat
    } do
      Banking.bulk_insert_transactions([
        %{
          date: ~D[2024-01-01],
          description: "PIX QR CODE DINAMICO - SPOTIFY",
          amount: Decimal.new("-21.90"),
          type: "debit",
          bank_statement_id: stmt.id,
          user_id: user.id,
          category_id: uncat.id
        }
      ])

      [txn] = Banking.list_transactions(user.id)

      assert {:ok, rule} = Banking.set_transaction_recurring_mode(user.id, txn.id, "fixed")
      assert rule.pattern == "spotify"
      assert rule.mode == "fixed"

      statuses = Banking.recurring_statuses(user.id, [txn])
      assert Map.fetch!(statuses, txn.id).status == "fixed"
    end
  end

  describe "delete_statements/2 authorization" do
    test "delete_statements with correct user_id deletes the statements", %{user: user} do
      {:ok, stmt} =
        Banking.create_statement(%{bank: "nubank", filename: "test.csv", user_id: user.id})

      assert {1, _} = Banking.delete_statements([stmt.id], user.id)
      assert Banking.list_statements(user.id) == []
    end

    test "delete_statements with wrong user_id does not delete the statements", %{user: user} do
      other_user = user_fixture()

      {:ok, stmt} =
        Banking.create_statement(%{bank: "nubank", filename: "test.csv", user_id: user.id})

      assert {0, _} = Banking.delete_statements([stmt.id], other_user.id)
      assert length(Banking.list_statements(user.id)) == 1
    end

    test "get_statement! with wrong user_id raises", %{user: user} do
      other_user = user_fixture()

      {:ok, stmt} =
        Banking.create_statement(%{bank: "nubank", filename: "test.csv", user_id: user.id})

      assert_raise Ecto.NoResultsError, fn ->
        Banking.get_statement!(stmt.id, other_user.id)
      end
    end
  end

  describe "category_rules" do
    test "create_category_rule creates a rule", %{user: user} do
      Banking.ensure_default_categories(user.id)
      food_cat = Enum.find(Banking.list_categories(user.id), &(&1.name == "Alimentação"))

      {:ok, rule} =
        Banking.create_category_rule(%{
          pattern: "supermercado",
          user_id: user.id,
          category_id: food_cat.id
        })

      assert rule.pattern == "supermercado"
    end

    test "categorize_transaction matches rules", %{user: user} do
      Banking.ensure_default_categories(user.id)
      food_cat = Enum.find(Banking.list_categories(user.id), &(&1.name == "Alimentação"))

      Banking.create_category_rule(%{
        pattern: "padaria xpto",
        user_id: user.id,
        category_id: food_cat.id
      })

      result = Banking.categorize_transaction("Padaria XPTO Centro", user.id)
      assert result == food_cat.id
    end

    test "categorize_transaction uses default rules when no custom rule matches", %{user: user} do
      Banking.ensure_default_categories(user.id)
      food_cat = Enum.find(Banking.list_categories(user.id), &(&1.name == "Alimentação"))

      result = Banking.categorize_transaction("Compra no débito - SUPERMERCADO GREGORIO", user.id)
      assert result == food_cat.id
    end

    test "categorize_transaction returns uncategorized for unknown", %{user: user} do
      Banking.ensure_default_categories(user.id)
      uncat = Banking.get_uncategorized_category(user.id)

      result = Banking.categorize_transaction("XYZABC123 Random Description", user.id)
      assert result == uncat.id
    end

    test "categorize_transactions loads rules once for multiple descriptions", %{user: user} do
      Banking.ensure_default_categories(user.id)
      food_cat = Enum.find(Banking.list_categories(user.id), &(&1.name == "Alimentação"))
      health_cat = Enum.find(Banking.list_categories(user.id), &(&1.name == "Saúde"))

      Banking.create_category_rule(%{
        pattern: "padaria xpto",
        user_id: user.id,
        category_id: food_cat.id
      })

      Banking.create_category_rule(%{
        pattern: "drogasil",
        user_id: user.id,
        category_id: health_cat.id
      })

      result =
        Banking.categorize_transactions(
          ["Padaria XPTO Centro", "DROGASIL Loja 123", "XYZABC Unknown"],
          user.id
        )

      assert result["Padaria XPTO Centro"] == food_cat.id
      assert result["DROGASIL Loja 123"] == health_cat.id
      uncat = Banking.get_uncategorized_category(user.id)
      assert result["XYZABC Unknown"] == uncat.id
    end

    test "categorize_transactions returns same results as individual calls", %{user: user} do
      Banking.ensure_default_categories(user.id)
      food_cat = Enum.find(Banking.list_categories(user.id), &(&1.name == "Alimentação"))

      Banking.create_category_rule(%{
        pattern: "padaria xpto",
        user_id: user.id,
        category_id: food_cat.id
      })

      descriptions = ["Padaria XPTO Centro", "SUPERMERCADO GREGORIO", "Random thing"]

      batch_result = Banking.categorize_transactions(descriptions, user.id)

      for desc <- descriptions do
        individual = Banking.categorize_transaction(desc, user.id)
        assert batch_result[desc] == individual
      end
    end
  end

  describe "detect_internal_transfers" do
    test "detect_internal_transfers is atomic - all updates succeed together", %{user: user} do
      Banking.ensure_default_categories(user.id)
      uncat = Banking.get_uncategorized_category(user.id)

      {:ok, extrato_stmt} =
        Banking.create_statement(%{
          bank: "nubank",
          filename: "extrato.csv",
          statement_type: "extrato",
          user_id: user.id
        })

      {:ok, _fatura} =
        Banking.create_statement(%{
          bank: "nubank",
          filename: "fatura.csv",
          statement_type: "fatura",
          period_start: ~D[2026-01-01],
          period_end: ~D[2026-01-31],
          user_id: user.id
        })

      Banking.bulk_insert_transactions([
        %{
          date: ~D[2026-01-10],
          description: "Pagamento de fatura cartao",
          amount: Decimal.new("-500.00"),
          type: "debit",
          bank_statement_id: extrato_stmt.id,
          user_id: user.id,
          category_id: uncat.id
        },
        %{
          date: ~D[2026-01-15],
          description: "Compra normal",
          amount: Decimal.new("-50.00"),
          type: "debit",
          bank_statement_id: extrato_stmt.id,
          user_id: user.id,
          category_id: uncat.id
        }
      ])

      result = Banking.detect_internal_transfers(user.id)
      assert result == :ok

      transactions = Banking.list_transactions(user.id)
      cc_payment = Enum.find(transactions, &(&1.description == "Pagamento de fatura cartao"))
      normal = Enum.find(transactions, &(&1.description == "Compra normal"))

      assert cc_payment.is_internal_transfer == true
      assert normal.is_internal_transfer == false
    end

    test "detect_internal_transfers returns :ok on success", %{user: user} do
      assert Banking.detect_internal_transfers(user.id) == :ok
    end

    test "marca 'GASTOS CARTAO DE CREDITO' do extrato como transferência interna", %{user: user} do
      Banking.ensure_default_categories(user.id)
      uncat = Banking.get_uncategorized_category(user.id)

      {:ok, extrato} =
        Banking.create_statement(%{
          bank: "bradesco",
          filename: "e.csv",
          statement_type: "extrato",
          user_id: user.id
        })

      {:ok, _fatura} =
        Banking.create_statement(%{
          bank: "bradesco",
          filename: "f.csv",
          statement_type: "fatura",
          period_start: ~D[2026-05-01],
          period_end: ~D[2026-05-31],
          user_id: user.id
        })

      Banking.bulk_insert_transactions([
        %{
          date: ~D[2026-05-10],
          description: "GASTOS CARTAO DE CREDITO",
          amount: Decimal.new("-1200.00"),
          type: "debit",
          bank_statement_id: extrato.id,
          user_id: user.id,
          category_id: uncat.id
        }
      ])

      assert Banking.detect_internal_transfers(user.id) == :ok
      assert [txn] = Banking.list_transactions(user.id)
      assert txn.is_internal_transfer == true
    end
  end

  describe "monthly_summary" do
    test "returns summary with income and expenses", %{user: user} do
      Banking.ensure_default_categories(user.id)
      food_cat = Enum.find(Banking.list_categories(user.id), &(&1.name == "Alimentação"))

      {:ok, stmt} =
        Banking.create_statement(%{bank: "nubank", filename: "test.csv", user_id: user.id})

      Banking.bulk_insert_transactions([
        %{
          date: ~D[2026-01-10],
          description: "Salary",
          amount: Decimal.new("5000.00"),
          type: "credit",
          bank_statement_id: stmt.id,
          user_id: user.id,
          category_id: food_cat.id
        },
        %{
          date: ~D[2026-01-15],
          description: "Groceries",
          amount: Decimal.new("-200.00"),
          type: "debit",
          bank_statement_id: stmt.id,
          user_id: user.id,
          category_id: food_cat.id
        }
      ])

      summary = Banking.monthly_summary(user.id, 2026, 1)
      assert Decimal.compare(summary.total_income, Decimal.new("5000.00")) == :eq
      assert Decimal.compare(summary.total_expenses, Decimal.new("200.00")) == :eq
      assert summary.transaction_count == 2

      assert [%{category: %{name: "Alimentação"}, total: income, count: 1}] =
               summary.income_by_category

      assert Decimal.compare(income, Decimal.new("5000.00")) == :eq
    end

    test "subtracts refunds, separates investments, excludes internal transfers", %{user: user} do
      Banking.ensure_default_categories(user.id)
      cats = Banking.list_categories(user.id)
      food = Enum.find(cats, &(&1.name == "Alimentação"))
      invest = Enum.find(cats, &(&1.kind == "investment"))

      {:ok, stmt} =
        Banking.create_statement(%{bank: "nubank", filename: "test.csv", user_id: user.id})

      base = %{bank_statement_id: stmt.id, user_id: user.id, date: ~D[2026-02-10]}

      Banking.bulk_insert_transactions([
        Map.merge(base, %{
          description: "Salário",
          amount: Decimal.new("5000.00"),
          type: "credit",
          category_id: food.id
        }),
        Map.merge(base, %{
          description: "Mercado",
          amount: Decimal.new("-200.00"),
          type: "debit",
          category_id: food.id
        }),
        Map.merge(base, %{
          description: "Estorno compra",
          amount: Decimal.new("50.00"),
          type: "credit",
          category_id: food.id
        }),
        Map.merge(base, %{
          description: "Aporte CDB",
          amount: Decimal.new("-300.00"),
          type: "debit",
          category_id: invest.id
        }),
        Map.merge(base, %{
          description: "Transferência interna",
          amount: Decimal.new("-1000.00"),
          type: "debit",
          category_id: food.id,
          is_internal_transfer: true
        })
      ])

      summary = Banking.monthly_summary(user.id, 2026, 2)

      # income exclui o estorno (que é tratado como refund)
      assert Decimal.equal?(summary.total_income, Decimal.new("5000.00"))
      # despesa bruta 200 menos estorno 50
      assert Decimal.equal?(summary.total_expenses, Decimal.new("150.00"))
      assert Decimal.equal?(summary.total_investments, Decimal.new("300.00"))
      assert summary.internal_count == 1
      assert summary.refund_count == 1
      assert Decimal.equal?(summary.balance, Decimal.new("4550.00"))

      # não retém a lista completa em memória; expõe só os tops
      refute Map.has_key?(summary, :transactions)
      assert Map.has_key?(summary, :top_expenses)

      # #4: a soma da pizza (by_category) bate com o card "Despesas" (líquido de estornos)
      by_category_total =
        Enum.reduce(summary.by_category, Decimal.new(0), fn %{total: t}, acc ->
          Decimal.add(acc, t)
        end)

      assert Decimal.equal?(by_category_total, summary.total_expenses)

      # #2: Top Despesas/Receitas não vazam transferências internas, estornos nem investimentos
      top_expense_descriptions = Enum.map(summary.top_expenses, & &1.description)
      assert "Mercado" in top_expense_descriptions
      refute "Transferência interna" in top_expense_descriptions
      refute "Aporte CDB" in top_expense_descriptions

      top_income_descriptions = Enum.map(summary.top_income, & &1.description)
      assert "Salário" in top_income_descriptions
      refute "Estorno compra" in top_income_descriptions
    end
  end

  describe "create_financial_goal/1 category ownership" do
    test "rejects a category owned by another user", %{user: user} do
      other = user_fixture()
      Banking.ensure_default_categories(other.id)
      other_cat = hd(Banking.list_categories(other.id))

      assert {:error, changeset} =
               Banking.create_financial_goal(%{
                 "type" => "category_limit",
                 "target_value" => "100",
                 "user_id" => user.id,
                 "category_id" => other_cat.id
               })

      assert changeset.errors[:category_id]
    end

    test "accepts a category owned by the user", %{user: user} do
      Banking.ensure_default_categories(user.id)
      cat = hd(Banking.list_categories(user.id))

      assert {:ok, _goal} =
               Banking.create_financial_goal(%{
                 "type" => "category_limit",
                 "target_value" => "100",
                 "user_id" => user.id,
                 "category_id" => cat.id
               })
    end
  end

  describe "list_active_installments/2 isolamento (IDOR)" do
    test "não vaza parcelas de outro usuário com o mesmo installment_group_id", %{user: user} do
      other = user_fixture()
      # group_id é hash de descrição+total → idêntico entre usuários
      group_id = Grana.Banking.Parsers.InstallmentParser.generate_group_id("netflix", 3)

      {:ok, s1} = Banking.create_statement(%{bank: "nubank", filename: "a.csv", user_id: user.id})

      {:ok, s2} =
        Banking.create_statement(%{bank: "nubank", filename: "b.csv", user_id: other.id})

      inst = fn uid, sid ->
        %{
          date: ~D[2026-01-10],
          description: "Netflix",
          amount: Decimal.new("-30.00"),
          type: "debit",
          bank_statement_id: sid,
          user_id: uid,
          installment_current: 1,
          installment_total: 3,
          installment_group_id: group_id
        }
      end

      Banking.bulk_insert_transactions([inst.(user.id, s1.id)])
      Banking.bulk_insert_transactions([inst.(other.id, s2.id)])

      result = Banking.list_active_installments(user.id)
      assert length(result) == 1
      assert Enum.all?(result, &(&1.user_id == user.id))
    end
  end

  describe "category_belongs_to_user?/2" do
    test "verdadeiro só para categoria do próprio usuário", %{user: user} do
      other = user_fixture()
      Banking.ensure_default_categories(user.id)
      Banking.ensure_default_categories(other.id)

      own = hd(Banking.list_categories(user.id))
      foreign = hd(Banking.list_categories(other.id))

      assert Banking.category_belongs_to_user?(own.id, user.id)
      refute Banking.category_belongs_to_user?(foreign.id, user.id)
      refute Banking.category_belongs_to_user?(-1, user.id)
    end
  end
end
