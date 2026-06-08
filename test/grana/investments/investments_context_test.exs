defmodule Grana.Investments.ContextTest do
  use Grana.DataCase, async: true

  alias Grana.Investments

  import Grana.AccountsFixtures

  setup do
    user = user_fixture()
    inst = Investments.ensure_b3_institution(user.id)

    {:ok, stmt} =
      Investments.create_statement(%{
        filename: "test.csv",
        user_id: user.id,
        institution_id: inst.id
      })

    base_txn = %{
      user_id: user.id,
      statement_id: stmt.id,
      institution_id: inst.id,
      asset_name: "PETR4",
      asset_ticker: "PETR4",
      asset_type: "acao"
    }

    %{user: user, inst: inst, stmt: stmt, base_txn: base_txn}
  end

  describe "available_months/1" do
    test "returns empty list when no transactions", %{user: user} do
      assert Investments.available_months(user.id) == []
    end

    test "returns months with transactions", %{user: user, base_txn: base} do
      Investments.bulk_insert_transactions([
        Map.merge(base, %{
          date: ~D[2026-01-15],
          operation: "compra",
          quantity: Decimal.new(10),
          unit_price: Decimal.new(30),
          total_amount: Decimal.new(300)
        })
      ])

      months = Investments.available_months(user.id)
      assert length(months) >= 1
      assert {2026, 1} in months
    end
  end

  describe "available_years/1" do
    test "returns empty list when no transactions", %{user: user} do
      assert Investments.available_years(user.id) == []
    end

    test "returns years with transactions", %{user: user, base_txn: base} do
      Investments.bulk_insert_transactions([
        Map.merge(base, %{
          date: ~D[2025-06-10],
          operation: "compra",
          quantity: Decimal.new(5),
          unit_price: Decimal.new(20),
          total_amount: Decimal.new(100)
        }),
        Map.merge(base, %{
          date: ~D[2026-01-15],
          operation: "compra",
          quantity: Decimal.new(5),
          unit_price: Decimal.new(30),
          total_amount: Decimal.new(150)
        })
      ])

      years = Investments.available_years(user.id)
      assert 2025 in years
      assert 2026 in years
    end
  end

  describe "available_institutions/1" do
    test "returns empty when no transactions", %{user: user} do
      assert Investments.available_institutions(user.id) == []
    end

    test "returns institutions with transactions", %{user: user, inst: inst, base_txn: base} do
      Investments.bulk_insert_transactions([
        Map.merge(base, %{
          date: ~D[2026-01-15],
          operation: "compra",
          quantity: Decimal.new(10),
          unit_price: Decimal.new(30),
          total_amount: Decimal.new(300)
        })
      ])

      insts = Investments.available_institutions(user.id)
      assert Enum.any?(insts, &(&1.id == inst.id))
    end
  end

  describe "available_asset_types/1" do
    test "returns empty when no transactions", %{user: user} do
      assert Investments.available_asset_types(user.id) == []
    end

    test "returns distinct asset types", %{user: user, base_txn: base} do
      Investments.bulk_insert_transactions([
        Map.merge(base, %{
          date: ~D[2026-01-15],
          operation: "compra",
          quantity: Decimal.new(10),
          unit_price: Decimal.new(30),
          total_amount: Decimal.new(300)
        }),
        Map.merge(base, %{
          asset_name: "HGLG11",
          asset_ticker: "HGLG11",
          asset_type: "fii",
          date: ~D[2026-01-20],
          operation: "compra",
          quantity: Decimal.new(5),
          unit_price: Decimal.new(100),
          total_amount: Decimal.new(500)
        })
      ])

      types = Investments.available_asset_types(user.id)
      assert "acao" in types
      assert "fii" in types
    end
  end

  describe "available_operations/1" do
    test "returns distinct operations", %{user: user, base_txn: base} do
      Investments.bulk_insert_transactions([
        Map.merge(base, %{
          date: ~D[2026-01-15],
          operation: "compra",
          quantity: Decimal.new(10),
          unit_price: Decimal.new(30),
          total_amount: Decimal.new(300)
        }),
        Map.merge(base, %{
          date: ~D[2026-02-15],
          operation: "venda",
          quantity: Decimal.new(5),
          unit_price: Decimal.new(35),
          total_amount: Decimal.new(175)
        })
      ])

      ops = Investments.available_operations(user.id)
      assert "compra" in ops
      assert "venda" in ops
    end
  end

  describe "all_active_tickers/1" do
    test "returns empty when no transactions", %{user: user} do
      assert Investments.all_active_tickers(user.id) == []
    end

    test "returns tickers with net positive quantity", %{user: user, base_txn: base} do
      Investments.bulk_insert_transactions([
        Map.merge(base, %{
          date: ~D[2026-01-15],
          operation: "compra",
          quantity: Decimal.new(10),
          unit_price: Decimal.new(30),
          total_amount: Decimal.new(300)
        })
      ])

      tickers = Investments.all_active_tickers(user.id)
      assert "PETR4" in tickers
    end

    test "excludes tickers with zero net quantity (fully sold)", %{user: user, base_txn: base} do
      Investments.bulk_insert_transactions([
        Map.merge(base, %{
          date: ~D[2026-01-15],
          operation: "compra",
          quantity: Decimal.new(10),
          unit_price: Decimal.new(30),
          total_amount: Decimal.new(300)
        }),
        Map.merge(base, %{
          date: ~D[2026-02-15],
          operation: "venda",
          quantity: Decimal.new(10),
          unit_price: Decimal.new(35),
          total_amount: Decimal.new(350)
        })
      ])

      tickers = Investments.all_active_tickers(user.id)
      refute "PETR4" in tickers
    end
  end

  describe "all_active_tickers_global/0" do
    test "returns tickers across all users" do
      user1 = user_fixture()
      user2 = user_fixture()

      inst1 = Investments.ensure_b3_institution(user1.id)
      inst2 = Investments.ensure_b3_institution(user2.id)

      {:ok, stmt1} =
        Investments.create_statement(%{
          filename: "t1.csv",
          user_id: user1.id,
          institution_id: inst1.id
        })

      {:ok, stmt2} =
        Investments.create_statement(%{
          filename: "t2.csv",
          user_id: user2.id,
          institution_id: inst2.id
        })

      Investments.bulk_insert_transactions([
        %{
          user_id: user1.id,
          statement_id: stmt1.id,
          institution_id: inst1.id,
          asset_name: "PETR4",
          asset_ticker: "PETR4",
          asset_type: "acao",
          date: ~D[2026-01-15],
          operation: "compra",
          quantity: Decimal.new(5),
          unit_price: Decimal.new(30),
          total_amount: Decimal.new(150)
        },
        %{
          user_id: user2.id,
          statement_id: stmt2.id,
          institution_id: inst2.id,
          asset_name: "VALE3",
          asset_ticker: "VALE3",
          asset_type: "acao",
          date: ~D[2026-01-20],
          operation: "compra",
          quantity: Decimal.new(5),
          unit_price: Decimal.new(60),
          total_amount: Decimal.new(300)
        }
      ])

      tickers = Investments.all_active_tickers_global()
      assert "PETR4" in tickers
      assert "VALE3" in tickers
    end
  end

  describe "period_activity/5" do
    test "returns empty list when no transactions", %{user: user} do
      result = Investments.period_activity(user.id, "year", 2026, nil)
      assert result == []
    end

    test "total view mode groups by year", %{user: user, base_txn: base} do
      Investments.bulk_insert_transactions([
        Map.merge(base, %{
          date: ~D[2026-01-15],
          operation: "compra",
          quantity: Decimal.new(10),
          unit_price: Decimal.new(30),
          total_amount: Decimal.new(300)
        })
      ])

      result = Investments.period_activity(user.id, "total", nil, nil)
      assert is_list(result)
      assert length(result) >= 1

      [entry | _] = result
      assert Map.has_key?(entry, :key)
      assert Map.has_key?(entry, :aportes)
      assert Map.has_key?(entry, :proventos)
    end

    test "year view mode groups by month", %{user: user, base_txn: base} do
      Investments.bulk_insert_transactions([
        Map.merge(base, %{
          date: ~D[2026-01-15],
          operation: "compra",
          quantity: Decimal.new(10),
          unit_price: Decimal.new(30),
          total_amount: Decimal.new(300)
        }),
        Map.merge(base, %{
          date: ~D[2026-03-10],
          operation: "compra",
          quantity: Decimal.new(5),
          unit_price: Decimal.new(32),
          total_amount: Decimal.new(160)
        })
      ])

      result = Investments.period_activity(user.id, "year", 2026, nil)
      assert is_list(result)
      keys = Enum.map(result, & &1.key)
      assert 1 in keys
      assert 3 in keys
    end

    test "month view mode groups by day", %{user: user, base_txn: base} do
      Investments.bulk_insert_transactions([
        Map.merge(base, %{
          date: ~D[2026-01-05],
          operation: "compra",
          quantity: Decimal.new(5),
          unit_price: Decimal.new(30),
          total_amount: Decimal.new(150)
        }),
        Map.merge(base, %{
          date: ~D[2026-01-20],
          operation: "compra",
          quantity: Decimal.new(5),
          unit_price: Decimal.new(31),
          total_amount: Decimal.new(155)
        })
      ])

      result = Investments.period_activity(user.id, "month", 2026, 1)
      assert is_list(result)
      assert length(result) >= 1
    end
  end

  describe "portfolio_with_market_data/2" do
    test "returns empty portfolio when no transactions", %{user: user} do
      result = Investments.portfolio_with_market_data(user.id, allow_fetch: false)
      assert is_map(result)
      assert result.holdings == []
    end

    test "enriches holdings with cost basis when no quotes available", %{
      user: user,
      base_txn: base
    } do
      Investments.bulk_insert_transactions([
        Map.merge(base, %{
          date: ~D[2026-01-15],
          operation: "compra",
          quantity: Decimal.new(10),
          unit_price: Decimal.new(30),
          total_amount: Decimal.new(300)
        })
      ])

      result = Investments.portfolio_with_market_data(user.id, allow_fetch: false)
      assert is_map(result)

      active = Enum.filter(result.holdings, & &1.is_active)
      assert length(active) >= 1

      holding = Enum.find(active, &(&1.ticker == "PETR4"))
      assert holding
      assert Decimal.compare(holding.current_value, 0) != :eq
    end

    test "portfolio has market_value and gain_loss fields", %{user: user, base_txn: base} do
      Investments.bulk_insert_transactions([
        Map.merge(base, %{
          date: ~D[2026-01-15],
          operation: "compra",
          quantity: Decimal.new(10),
          unit_price: Decimal.new(30),
          total_amount: Decimal.new(300)
        })
      ])

      result = Investments.portfolio_with_market_data(user.id, allow_fetch: false)
      assert Map.has_key?(result, :market_value)
      assert Map.has_key?(result, :total_gain_loss)
      assert Map.has_key?(result, :has_quotes)
      assert Map.has_key?(result, :by_asset_type)
    end
  end

  describe "monthly_investments/3" do
    test "returns empty list when no transactions", %{user: user} do
      result = Investments.monthly_investments(user.id, 2026)
      assert result == []
    end

    test "returns monthly summary for the year", %{user: user, base_txn: base} do
      Investments.bulk_insert_transactions([
        Map.merge(base, %{
          date: ~D[2026-01-15],
          operation: "compra",
          quantity: Decimal.new(10),
          unit_price: Decimal.new(30),
          total_amount: Decimal.new(300)
        }),
        Map.merge(base, %{
          date: ~D[2026-03-10],
          operation: "compra",
          quantity: Decimal.new(5),
          unit_price: Decimal.new(35),
          total_amount: Decimal.new(175)
        })
      ])

      result = Investments.monthly_investments(user.id, 2026)
      assert is_list(result)
      assert length(result) >= 1

      jan_entry = Enum.find(result, &(&1.month == 1))
      assert jan_entry
      assert Decimal.compare(jan_entry.invested, 0) == :gt
    end
  end

  describe "list_proventos/1" do
    test "returns empty list when no dividend transactions", %{user: user} do
      result = Investments.list_proventos(user.id)
      assert result == []
    end

    test "returns provento transactions", %{user: user, base_txn: base} do
      Investments.bulk_insert_transactions([
        Map.merge(base, %{
          date: ~D[2026-02-10],
          operation: "dividendo",
          quantity: Decimal.new(10),
          unit_price: Decimal.new(1),
          total_amount: Decimal.new(10)
        })
      ])

      result = Investments.list_proventos(user.id)
      assert length(result) >= 1
    end
  end

  describe "upload_counts_by_month/1" do
    test "returns empty map when no transactions", %{user: user} do
      assert Investments.upload_counts_by_month(user.id) == %{}
    end

    test "returns map of {year, month} => count with transactions", %{user: user, base_txn: base} do
      Investments.bulk_insert_transactions([
        Map.merge(base, %{
          date: ~D[2026-01-15],
          operation: "compra",
          quantity: Decimal.new(10),
          unit_price: Decimal.new(30),
          total_amount: Decimal.new(300)
        })
      ])

      result = Investments.upload_counts_by_month(user.id)
      assert is_map(result)
      assert map_size(result) >= 1
    end
  end

  describe "list_institutions/1" do
    test "returns institutions sorted by name" do
      user = user_fixture()
      _b3 = Investments.ensure_b3_institution(user.id)
      _gcb = Investments.ensure_gcb_institution(user.id)

      institutions = Investments.list_institutions(user.id)
      assert is_list(institutions)
      assert length(institutions) >= 2
    end
  end

  describe "get_institution!/2" do
    test "returns institution for valid id and user", %{user: user, inst: inst} do
      found = Investments.get_institution!(inst.id, user.id)
      assert found.id == inst.id
    end

    test "raises for wrong user" do
      user = user_fixture()
      inst = Investments.ensure_b3_institution(user.id)
      other_user = user_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        Investments.get_institution!(inst.id, other_user.id)
      end
    end
  end

  describe "list_transactions_paginated/2" do
    test "returns paginated transactions", %{user: user, base_txn: base} do
      full =
        Map.merge(base, %{
          date: ~D[2026-01-01],
          operation: "compra",
          quantity: Decimal.new(1),
          unit_price: Decimal.new(100),
          total_amount: Decimal.new(100)
        })

      Investments.bulk_insert_transactions([full])

      {transactions, total} =
        Investments.list_transactions_paginated(user.id, page: 1, per_page: 10)

      assert is_list(transactions)
      assert is_integer(total)
      assert total >= 1
    end

    test "returns empty when no transactions", %{user: user} do
      {transactions, total} = Investments.list_transactions_paginated(user.id)
      assert transactions == []
      assert total == 0
    end
  end

  describe "delete_institution/1" do
    test "deletes a user-created institution" do
      user = user_fixture()

      {:ok, custom_inst} =
        Investments.create_institution(%{
          name: "My Broker",
          slug: "my_broker_#{System.unique_integer()}",
          user_id: user.id,
          is_system: false
        })

      assert {:ok, _} = Investments.delete_institution(custom_inst)
    end

    test "cannot delete system institution" do
      user = user_fixture()
      sys_inst = Investments.ensure_b3_institution(user.id)

      assert {:error, :system_institution} = Investments.delete_institution(sys_inst)
    end
  end

  describe "coverage_months/1" do
    test "returns empty MapSet when no transactions", %{user: user} do
      result = Investments.coverage_months(user.id)
      assert MapSet.size(result) == 0
    end

    test "returns set of {year, month} tuples with transactions", %{user: user, base_txn: base} do
      Investments.bulk_insert_transactions([
        Map.merge(base, %{
          date: ~D[2026-03-10],
          operation: "compra",
          quantity: Decimal.new(5),
          unit_price: Decimal.new(20),
          total_amount: Decimal.new(100)
        })
      ])

      result = Investments.coverage_months(user.id)
      assert MapSet.member?(result, {2026, 3})
    end
  end

  describe "list_statements_paginated/2" do
    test "returns {statements, total} tuple", %{user: user, inst: inst} do
      {:ok, _} =
        Investments.create_statement(%{
          filename: "extra.csv",
          user_id: user.id,
          institution_id: inst.id
        })

      {statements, total} = Investments.list_statements_paginated(user.id, page: 1, per_page: 10)
      assert is_list(statements)
      assert is_integer(total)
      assert total >= 1
    end

    test "pagination limits results", %{user: user, inst: inst} do
      for i <- 1..5 do
        Investments.create_statement(%{
          filename: "file_#{i}.csv",
          user_id: user.id,
          institution_id: inst.id
        })
      end

      {statements, total} = Investments.list_statements_paginated(user.id, page: 1, per_page: 2)
      assert length(statements) == 2
      assert total >= 5
    end
  end

  describe "investments_summary/2" do
    test "returns zeroed summary when no transactions", %{user: user} do
      result = Investments.investments_summary(user.id)
      assert is_map(result)
      assert Decimal.compare(result.total_compras, 0) == :eq
    end

    test "returns correct totals with transactions", %{user: user, base_txn: base} do
      Investments.bulk_insert_transactions([
        Map.merge(base, %{
          date: ~D[2026-05-01],
          operation: "compra",
          quantity: Decimal.new(10),
          unit_price: Decimal.new(50),
          total_amount: Decimal.new(500)
        }),
        Map.merge(base, %{
          date: ~D[2026-05-02],
          operation: "dividendo",
          quantity: Decimal.new(0),
          unit_price: Decimal.new(0),
          total_amount: Decimal.new(25)
        })
      ])

      result = Investments.investments_summary(user.id)
      assert Decimal.compare(result.total_compras, 0) == :gt
      assert Decimal.compare(result.total_proventos, 0) == :gt
    end
  end

  describe "list_transactions with filter options" do
    test "filter by amount_min and amount_max", %{user: user, base_txn: base} do
      Investments.bulk_insert_transactions([
        Map.merge(base, %{
          date: ~D[2026-06-01],
          operation: "compra",
          quantity: Decimal.new(1),
          unit_price: Decimal.new(100),
          total_amount: Decimal.new(100)
        }),
        Map.merge(base, %{
          date: ~D[2026-06-02],
          operation: "compra",
          asset_ticker: "VALE3",
          asset_name: "VALE3",
          quantity: Decimal.new(1),
          unit_price: Decimal.new(500),
          total_amount: Decimal.new(500)
        })
      ])

      small =
        Investments.list_transactions(user.id,
          amount_min: Decimal.new("50"),
          amount_max: Decimal.new("200")
        )

      assert Enum.all?(small, fn t ->
               Decimal.compare(Decimal.abs(t.total_amount), Decimal.new("200")) != :gt
             end)

      large = Investments.list_transactions(user.id, amount_min: Decimal.new("400"))

      assert Enum.all?(large, fn t ->
               Decimal.compare(Decimal.abs(t.total_amount), Decimal.new("400")) != :lt
             end)
    end

    test "filter by date range", %{user: user, base_txn: base} do
      Investments.bulk_insert_transactions([
        Map.merge(base, %{
          date: ~D[2025-01-01],
          operation: "compra",
          quantity: Decimal.new(5),
          unit_price: Decimal.new(20),
          total_amount: Decimal.new(100)
        })
      ])

      before_range =
        Investments.list_transactions(user.id, date_from: ~D[2026-01-01], date_to: ~D[2026-12-31])

      assert Enum.all?(before_range, fn t -> Date.compare(t.date, ~D[2026-01-01]) != :lt end)

      after_date = Investments.list_transactions(user.id, date_from: ~D[2025-01-01])
      assert length(after_date) >= 1

      before_date = Investments.list_transactions(user.id, date_to: ~D[2025-12-31])
      assert length(before_date) >= 1
    end

    test "filter by ticker search", %{user: user, base_txn: base} do
      Investments.bulk_insert_transactions([
        Map.merge(base, %{
          date: ~D[2026-07-01],
          operation: "compra",
          asset_ticker: "BBDC4",
          asset_name: "BRADESCO",
          quantity: Decimal.new(10),
          unit_price: Decimal.new(15),
          total_amount: Decimal.new(150)
        })
      ])

      result = Investments.list_transactions(user.id, search: "BRAD")
      assert Enum.any?(result, &(&1.asset_name =~ "BRADESCO"))
    end

    test "filter by institution_id=all returns all", %{user: user, base_txn: base} do
      full =
        Map.merge(base, %{
          date: ~D[2026-01-01],
          operation: "compra",
          quantity: Decimal.new(1),
          unit_price: Decimal.new(100),
          total_amount: Decimal.new(100)
        })

      Investments.bulk_insert_transactions([full])
      result = Investments.list_transactions(user.id, institution_id: "all")
      assert is_list(result)
      assert length(result) >= 1
    end

    test "filter by asset_type=all returns all", %{user: user, base_txn: base} do
      full =
        Map.merge(base, %{
          date: ~D[2026-01-01],
          operation: "compra",
          quantity: Decimal.new(1),
          unit_price: Decimal.new(100),
          total_amount: Decimal.new(100)
        })

      Investments.bulk_insert_transactions([full])
      result = Investments.list_transactions(user.id, asset_type: "all")
      assert is_list(result)
    end

    test "filter by operation=all returns all", %{user: user, base_txn: base} do
      full =
        Map.merge(base, %{
          date: ~D[2026-01-01],
          operation: "compra",
          quantity: Decimal.new(1),
          unit_price: Decimal.new(100),
          total_amount: Decimal.new(100)
        })

      Investments.bulk_insert_transactions([full])
      result = Investments.list_transactions(user.id, operation: "all")
      assert is_list(result)
    end

    test "filter by search empty string returns all", %{user: user, base_txn: base} do
      full =
        Map.merge(base, %{
          date: ~D[2026-01-01],
          operation: "compra",
          quantity: Decimal.new(1),
          unit_price: Decimal.new(100),
          total_amount: Decimal.new(100)
        })

      Investments.bulk_insert_transactions([full])
      result = Investments.list_transactions(user.id, search: "")
      assert is_list(result)
      assert length(result) >= 1
    end

    test "filter by ticker=all returns all", %{user: user, base_txn: base} do
      full =
        Map.merge(base, %{
          date: ~D[2026-01-01],
          operation: "compra",
          quantity: Decimal.new(1),
          unit_price: Decimal.new(100),
          total_amount: Decimal.new(100)
        })

      Investments.bulk_insert_transactions([full])
      result = Investments.list_transactions(user.id, ticker: "all")
      assert is_list(result)
    end

    test "filter by specific ticker", %{user: user, base_txn: base} do
      full =
        Map.merge(base, %{
          date: ~D[2026-01-01],
          operation: "compra",
          asset_ticker: "XYZW11",
          quantity: Decimal.new(1),
          unit_price: Decimal.new(100),
          total_amount: Decimal.new(100)
        })

      Investments.bulk_insert_transactions([full])
      result = Investments.list_transactions(user.id, ticker: "XYZW11")
      assert is_list(result)
    end

    test "filter by statement_id", %{user: user, base_txn: base, inst: inst} do
      {:ok, stmt2} =
        Investments.create_statement(%{
          filename: "other.csv",
          user_id: user.id,
          institution_id: inst.id
        })

      base2 = %{base | statement_id: stmt2.id}

      Investments.bulk_insert_transactions([
        Map.merge(base2, %{
          date: ~D[2026-08-01],
          operation: "compra",
          asset_ticker: "STMT2",
          asset_name: "STMT2 ASSET",
          quantity: Decimal.new(1),
          unit_price: Decimal.new(100),
          total_amount: Decimal.new(100)
        })
      ])

      result = Investments.list_transactions(user.id, statement_id: stmt2.id)
      assert Enum.all?(result, &(&1.statement_id == stmt2.id))
    end
  end
end
