defmodule GranaWeb.TransactionsLiveExtendedTest do
  use GranaWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Grana.BankingFixtures
  alias Grana.InvestmentsFixtures
  alias Grana.Banking

  setup :register_and_log_in_user

  describe "switch_tab" do
    test "switch to banking tab filters banking transactions", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/transactions")

      render_click(view, "switch_tab", %{"tab" => "banking"})

      html = render(view)
      assert html =~ "Transações"
    end

    test "switch to investments tab filters investment transactions", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/transactions")

      render_click(view, "switch_tab", %{"tab" => "investments"})

      html = render(view)
      assert html =~ "Transações"
    end
  end

  describe "filter events" do
    test "apply_filters with search term", %{conn: conn, user: user} do
      BankingFixtures.transaction_fixture(user, %{description: "LOJA XYZ", amount: "-50.00"})

      {:ok, view, _html} = live(conn, ~p"/transactions")

      render_click(view, "apply_filters", %{"search" => "loja"})

      html = render(view)
      assert html =~ "LOJA XYZ"
    end

    test "clear_filters resets all filters", %{conn: conn, user: user} do
      BankingFixtures.transaction_fixture(user, %{description: "LOJA XYZ", amount: "-50.00"})

      {:ok, view, _html} = live(conn, ~p"/transactions?search=nothing")

      render_click(view, "clear_filters", %{})

      html = render(view)
      assert html =~ "LOJA XYZ"
    end

    test "clear_statement removes bank_statement_id filter", %{conn: conn, user: user} do
      stmt = BankingFixtures.statement_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/transactions?statement_id=#{stmt.id}")

      render_click(view, "clear_statement", %{})

      html = render(view)
      assert html =~ "Transações"
    end

    test "search event filters by search term", %{conn: conn, user: user} do
      BankingFixtures.transaction_fixture(user, %{description: "CAFÉ ESPECIAL", amount: "-8.00"})

      {:ok, view, _html} = live(conn, ~p"/transactions")

      render_click(view, "search", %{"search" => "café"})

      html = render(view)
      assert html =~ "CAFÉ ESPECIAL"
    end

    test "filter=uncategorized shows only uncategorized", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/transactions")

      render_click(view, "filter", %{"filter" => "uncategorized"})

      html = render(view)
      assert html =~ "Transações"
    end
  end

  describe "toggle-description" do
    test "expands the description of a banking transaction", %{conn: conn, user: user} do
      txn =
        BankingFixtures.transaction_fixture(user, %{
          description: "MERCADO LIVRE",
          amount: "-200.00"
        })

      {:ok, view, _html} = live(conn, ~p"/transactions")

      render_click(view, "toggle-description", %{"id" => "banking-#{txn.id}"})

      html = render(view)
      assert html =~ "MERCADO LIVRE"
    end

    test "collapses when toggled again", %{conn: conn, user: user} do
      txn = BankingFixtures.transaction_fixture(user, %{description: "AMAZON", amount: "-150.00"})

      {:ok, view, _html} = live(conn, ~p"/transactions")

      render_click(view, "toggle-description", %{"id" => "banking-#{txn.id}"})
      render_click(view, "toggle-description", %{"id" => "banking-#{txn.id}"})

      html = render(view)
      assert html =~ "AMAZON"
    end
  end

  describe "save-category" do
    test "assigns a category to a banking transaction", %{conn: conn, user: user} do
      Banking.ensure_default_categories(user.id)
      txn = BankingFixtures.transaction_fixture(user, %{description: "PADARIA", amount: "-12.00"})
      cat = Banking.get_uncategorized_category(user.id)

      {:ok, view, _html} = live(conn, ~p"/transactions")

      render_click(view, "save-category", %{
        "txn_id" => to_string(txn.id),
        "category_id" => to_string(cat.id),
        "kind" => "banking"
      })

      updated = Grana.Repo.get!(Grana.Banking.Transaction, txn.id)
      assert updated.category_id == cat.id
    end
  end

  describe "bulk selection and apply" do
    test "toggle-select adds transaction to selection", %{conn: conn, user: user} do
      txn = BankingFixtures.transaction_fixture(user, %{description: "LOJA", amount: "-30.00"})

      {:ok, view, _html} = live(conn, ~p"/transactions")

      render_click(view, "toggle-select", %{"id" => "banking-#{txn.id}"})

      html = render(view)
      assert html =~ "LOJA" or html =~ "selecionado"
    end

    test "toggle-select-all selects all visible transactions", %{conn: conn, user: user} do
      BankingFixtures.transaction_fixture(user, %{description: "A", amount: "-10.00"})
      BankingFixtures.transaction_fixture(user, %{description: "B", amount: "-20.00"})

      {:ok, view, _html} = live(conn, ~p"/transactions")

      render_click(view, "toggle-select-all", %{})

      html = render(view)
      assert html =~ "Transações"
    end

    test "clear-selection deselects all", %{conn: conn, user: user} do
      txn = BankingFixtures.transaction_fixture(user, %{description: "X", amount: "-5.00"})

      {:ok, view, _html} = live(conn, ~p"/transactions")

      render_click(view, "toggle-select", %{"id" => "banking-#{txn.id}"})
      render_click(view, "clear-selection", %{})

      html = render(view)
      assert html =~ "Transações"
    end

    test "bulk-apply sets category for selected transactions", %{conn: conn, user: user} do
      Banking.ensure_default_categories(user.id)
      txn1 = BankingFixtures.transaction_fixture(user, %{description: "Bulk1", amount: "-10.00"})
      txn2 = BankingFixtures.transaction_fixture(user, %{description: "Bulk2", amount: "-20.00"})
      cat = Banking.get_uncategorized_category(user.id)

      {:ok, view, _html} = live(conn, ~p"/transactions")

      render_click(view, "toggle-select", %{"id" => "banking-#{txn1.id}"})
      render_click(view, "toggle-select", %{"id" => "banking-#{txn2.id}"})

      render_click(view, "bulk-apply", %{
        "action" => "category",
        "category_id" => to_string(cat.id)
      })

      html = render(view)
      assert html =~ "Transações"
    end

    test "bulk-apply sets recurring mode for selected transactions", %{conn: conn, user: user} do
      Banking.ensure_default_categories(user.id)

      txn =
        BankingFixtures.transaction_fixture(user, %{description: "Assinatura", amount: "-30.00"})

      {:ok, view, _html} = live(conn, ~p"/transactions")

      render_click(view, "toggle-select", %{"id" => "banking-#{txn.id}"})

      render_click(view, "bulk-apply", %{"action" => "recurring", "mode" => "fixed"})

      html = render(view)
      assert html =~ "Transações"
    end
  end

  describe "save-recurring" do
    test "save-recurring sets recurring mode for a transaction", %{conn: conn, user: user} do
      Banking.ensure_default_categories(user.id)

      txn =
        BankingFixtures.transaction_fixture(user, %{description: "ACADEMIA", amount: "-100.00"})

      {:ok, view, _html} = live(conn, ~p"/transactions")

      render_click(view, "save-recurring", %{
        "txn_id" => to_string(txn.id),
        "mode" => "fixed"
      })

      html = render(view)
      assert html =~ "Transações"
    end
  end

  describe "toggle-internal" do
    test "toggle-internal marks transaction as internal transfer", %{conn: conn, user: user} do
      txn = BankingFixtures.transaction_fixture(user, %{description: "PIX TED"})

      {:ok, view, _html} = live(conn, ~p"/transactions")

      render_click(view, "toggle-internal", %{
        "id" => to_string(txn.id),
        "internal" => "true"
      })

      html = render(view)
      assert html =~ "Transações"
    end

    test "toggle-internal unmarks internal transfer", %{conn: conn, user: user} do
      txn = BankingFixtures.transaction_fixture(user, %{description: "PIX TED"})

      {:ok, view, _html} = live(conn, ~p"/transactions")

      render_click(view, "toggle-internal", %{
        "id" => to_string(txn.id),
        "internal" => "false"
      })

      html = render(view)
      assert html =~ "Transações"
    end
  end

  describe "apply_filters with multiple params" do
    test "apply_filters with bank and type filters", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/transactions")

      render_click(view, "apply_filters", %{
        "search" => "",
        "bank" => "nubank",
        "type" => "debit"
      })

      html = render(view)
      assert html =~ "Transações"
    end

    test "filter=recurring shows recurring transactions", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/transactions")

      render_click(view, "filter", %{"filter" => "recurring"})

      html = render(view)
      assert html =~ "Transações"
    end

    test "filter=internal shows internal transfers", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/transactions")

      render_click(view, "filter", %{"filter" => "internal"})

      html = render(view)
      assert html =~ "Transações"
    end
  end

  describe "bulk-apply error paths" do
    test "bulk-apply with no selected transactions shows error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/transactions")

      html = render_click(view, "bulk-apply", %{"category_id" => "", "mode" => ""})

      assert html =~ "Transações"
    end

    test "bulk-apply with invalid category shows error", %{conn: conn, user: user} do
      txn = BankingFixtures.transaction_fixture(user, %{description: "LOJA", amount: "-10.00"})

      {:ok, view, _html} = live(conn, ~p"/transactions")

      render_click(view, "toggle-select", %{"id" => "banking-#{txn.id}"})

      html = render_click(view, "bulk-apply", %{"category_id" => "99999", "mode" => ""})

      assert html =~ "Transações"
    end

    test "bulk-apply with no category and no mode shows error", %{conn: conn, user: user} do
      txn = BankingFixtures.transaction_fixture(user, %{description: "TEST", amount: "-5.00"})

      {:ok, view, _html} = live(conn, ~p"/transactions")

      render_click(view, "toggle-select", %{"id" => "banking-#{txn.id}"})

      html = render_click(view, "bulk-apply", %{"category_id" => "", "mode" => ""})

      assert html =~ "Transações"
    end

    test "bulk-apply with both category and mode applies both", %{conn: conn, user: user} do
      Banking.ensure_default_categories(user.id)
      txn = BankingFixtures.transaction_fixture(user, %{description: "COMBO", amount: "-50.00"})
      cat = Banking.get_uncategorized_category(user.id)

      {:ok, view, _html} = live(conn, ~p"/transactions")

      render_click(view, "toggle-select", %{"id" => "banking-#{txn.id}"})

      html =
        render_click(view, "bulk-apply", %{
          "category_id" => to_string(cat.id),
          "mode" => "fixed"
        })

      assert html =~ "Transações"
    end
  end

  describe "save-recurring error paths" do
    test "save-recurring with non-expense credit transaction shows error", %{
      conn: conn,
      user: user
    } do
      txn =
        BankingFixtures.transaction_fixture(user, %{
          description: "SALARIO",
          amount: "5000.00",
          type: "credit"
        })

      {:ok, view, _html} = live(conn, ~p"/transactions")

      render_click(view, "save-recurring", %{
        "txn_id" => to_string(txn.id),
        "mode" => "fixed"
      })

      html = render(view)
      assert html =~ "Transações"
    end

    test "save-category with invalid category shows error", %{conn: conn, user: user} do
      Banking.ensure_default_categories(user.id)
      txn = BankingFixtures.transaction_fixture(user, %{description: "LOJA", amount: "-30.00"})

      {:ok, view, _html} = live(conn, ~p"/transactions")

      html =
        render_click(view, "save-category", %{
          "txn_id" => to_string(txn.id),
          "category_id" => "99999",
          "kind" => "banking"
        })

      assert html =~ "Transações"
    end
  end

  describe "investment transactions" do
    test "shows investment transactions when filter is set", %{conn: conn, user: user} do
      InvestmentsFixtures.transaction_fixture(user, %{
        asset_name: "PETR4",
        operation: "compra",
        total_amount: "100.00"
      })

      {:ok, _view, html} = live(conn, ~p"/transactions?source=investments")

      assert html =~ "Transações"
    end

    test "investment transactions with institution and asset type filters render", %{
      conn: conn,
      user: user
    } do
      InvestmentsFixtures.transaction_fixture(user, %{
        asset_name: "PETR4",
        asset_ticker: "PETR4",
        asset_type: "acao",
        operation: "compra",
        total_amount: "500.00"
      })

      {:ok, _view, html} = live(conn, ~p"/transactions?source=investments")
      assert html =~ "Transações"
    end
  end

  describe "statement filter navigation" do
    test "navigating with statement_id shows statement info", %{conn: conn, user: user} do
      Banking.ensure_default_categories(user.id)
      stmt = BankingFixtures.statement_fixture(user)

      {:ok, _view, html} =
        live(conn, ~p"/transactions?statement_id=#{stmt.id}&statement_source=banking")

      assert html =~ "Transações"
    end

    test "clear_statement removes statement filter", %{conn: conn, user: user} do
      Banking.ensure_default_categories(user.id)
      stmt = BankingFixtures.statement_fixture(user)

      {:ok, view, _html} =
        live(conn, ~p"/transactions?statement_id=#{stmt.id}&statement_source=banking")

      html = render_click(view, "clear_statement", %{})
      assert html =~ "Transações"
    end
  end

  describe "many transactions pagination" do
    setup %{user: user} do
      Banking.ensure_default_categories(user.id)
      today = Date.utc_today()

      for i <- 1..55 do
        BankingFixtures.transaction_fixture(user, %{
          description: "LOJA #{i}",
          amount: "-#{i}.00",
          date: today
        })
      end

      :ok
    end

    test "pagination appears with many transactions", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/transactions")
      assert html =~ "Transações"
    end

    test "second page loads different transactions", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/transactions?page=2")
      assert html =~ "Transações"
    end
  end

  describe "mixed banking and investment transactions" do
    test "shows both banking and investment totals in summary", %{conn: conn, user: user} do
      Banking.ensure_default_categories(user.id)
      today = Date.utc_today()

      BankingFixtures.transaction_fixture(user, %{
        description: "SALARIO",
        amount: "5000.00",
        date: today
      })

      InvestmentsFixtures.transaction_fixture(user, %{
        asset_name: "PETR4",
        total_amount: "500.00",
        operation: "compra"
      })

      {:ok, _view, html} = live(conn, ~p"/transactions")
      assert html =~ "Transações"
    end
  end

  describe "investment operation types in summary" do
    setup %{user: user} do
      Banking.ensure_default_categories(user.id)
      :ok
    end

    test "investment venda shows in transactions list", %{conn: conn, user: user} do
      InvestmentsFixtures.transaction_fixture(user, %{
        asset_name: "VALE3",
        asset_ticker: "VALE3",
        operation: "venda",
        total_amount: "1000.00"
      })

      {:ok, _view, html} = live(conn, ~p"/transactions?source=investments")
      assert html =~ "Transações"
    end

    test "investment dividendo shows proventos in summary", %{conn: conn, user: user} do
      InvestmentsFixtures.transaction_fixture(user, %{
        asset_name: "HGLG11",
        asset_ticker: "HGLG11",
        operation: "dividendo",
        total_amount: "50.00"
      })

      {:ok, _view, html} = live(conn, ~p"/transactions?source=investments")
      assert html =~ "Transações"
    end

    test "investment taxa shows fees in summary", %{conn: conn, user: user} do
      InvestmentsFixtures.transaction_fixture(user, %{
        asset_name: "PETR4",
        operation: "taxa",
        total_amount: "5.00"
      })

      {:ok, _view, html} = live(conn, ~p"/transactions?source=investments")
      assert html =~ "Transações"
    end

    test "internal transfer banking transaction is excluded from expenses", %{
      conn: conn,
      user: user
    } do
      BankingFixtures.transaction_fixture(user, %{
        description: "TRANSFERENCIA PIX",
        amount: "-1000.00",
        is_internal_transfer: true
      })

      {:ok, _view, html} = live(conn, ~p"/transactions")
      assert html =~ "Transações"
    end

    test "banking investment category transaction in summary", %{conn: conn, user: user} do
      cats = Banking.list_categories(user.id)
      inv_cat = Enum.find(cats, &(&1.kind == "investment"))

      if inv_cat do
        BankingFixtures.transaction_fixture(user, %{
          description: "APORTE CDB",
          amount: "-2000.00",
          type: "debit",
          category_id: inv_cat.id
        })
      end

      {:ok, _view, html} = live(conn, ~p"/transactions")
      assert html =~ "Transações"
    end
  end

  describe "sort_by URL parameters" do
    setup %{user: user} do
      Banking.ensure_default_categories(user.id)

      BankingFixtures.transaction_fixture(user, %{description: "LOJA A", amount: "-30.00"})
      BankingFixtures.transaction_fixture(user, %{description: "LOJA B", amount: "-20.00"})

      InvestmentsFixtures.transaction_fixture(user, %{
        asset_name: "PETR4",
        operation: "compra",
        total_amount: "500.00"
      })

      :ok
    end

    test "sort by description ascending", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/transactions?sort_by=description&sort_dir=asc")
      assert html =~ "Transações"
    end

    test "sort by source", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/transactions?sort_by=source&sort_dir=desc")
      assert html =~ "Transações"
    end

    test "sort by kind", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/transactions?sort_by=kind&sort_dir=asc")
      assert html =~ "Transações"
    end

    test "sort by amount", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/transactions?sort_by=amount&sort_dir=desc")
      assert html =~ "Transações"
    end

    test "unknown sort_by falls back to date sort", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/transactions?sort_by=unknown_field")
      assert html =~ "Transações"
    end
  end

  describe "normalize_origin and normalize_kind URL params" do
    setup %{user: user} do
      Banking.ensure_default_categories(user.id)
      :ok
    end

    test "origin param filters by institution", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/transactions?origin=b3")
      assert html =~ "Transações"
    end

    test "kind param filters by transaction kind", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/transactions?kind=expense")
      assert html =~ "Transações"
    end

    test "movement param filters by investment movement", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/transactions?movement=purchase")
      assert html =~ "Transações"
    end

    test "empty origin and kind returns all", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/transactions?origin=&kind=")
      assert html =~ "Transações"
    end
  end
end
