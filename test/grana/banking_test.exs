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
    end
  end
end
