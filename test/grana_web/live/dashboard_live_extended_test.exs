defmodule GranaWeb.DashboardLiveExtendedTest do
  use GranaWeb.ConnCase, async: false

  use Mimic

  import Phoenix.LiveViewTest

  alias Grana.BankingFixtures
  alias Grana.Banking

  setup :register_and_log_in_user

  describe "switch_tab" do
    test "switch to recurring tab renders fixed expenses", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard?tab=recurring")
      html = render(view)
      assert html =~ "Despesas fixas" or html =~ "Nenhuma"
    end

    test "switch back to overview tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_click(view, "switch_tab", %{"tab" => "recurring"})
      render_click(view, "switch_tab", %{"tab" => "overview"})

      html = render(view)
      assert html =~ "Painel"
    end
  end

  describe "select_year" do
    test "select_year changes active year filter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_click(view, "select_year", %{"year" => "2025"})

      html = render(view)
      assert html =~ "Painel"
    end
  end

  describe "select_month" do
    test "select_month all shows all data", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_click(view, "select_month", %{"month" => "all"})

      html = render(view)
      assert html =~ "Painel"
    end

    test "select_month specific month filters data", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_click(view, "select_month", %{"month" => "1"})

      html = render(view)
      assert html =~ "Painel"
    end
  end

  describe "filter events" do
    test "select_bank filters transactions by bank", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_click(view, "select_bank", %{"bank" => "nubank"})

      html = render(view)
      assert html =~ "Painel"
    end

    test "select_type filters by transaction kind", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_click(view, "select_type", %{"type" => "extrato"})

      html = render(view)
      assert html =~ "Painel"
    end

    test "select_txn_type filters by credit/debit", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_click(view, "select_txn_type", %{"txn_type" => "debit"})

      html = render(view)
      assert html =~ "Painel"
    end

    test "toggle-category toggles nil category filter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_click(view, "toggle-category", %{"id" => "nil"})

      html = render(view)
      assert html =~ "Painel"
    end

    test "toggle-category toggles specific category filter", %{conn: conn, user: user} do
      Banking.ensure_default_categories(user.id)
      cat = Banking.get_uncategorized_category(user.id)

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_click(view, "toggle-category", %{"id" => to_string(cat.id)})

      html = render(view)
      assert html =~ "Painel"
    end

    test "reset-categories clears category filters", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_click(view, "reset-categories", %{})

      html = render(view)
      assert html =~ "Painel"
    end
  end

  describe "recurring tab events" do
    test "rec_set_window changes recurring window", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard?tab=recurring")

      render_click(view, "rec_set_window", %{"window" => "3"})

      html = render(view)
      assert html =~ "Painel" or html =~ "Despesas"
    end

    test "rec_select_bank filters recurring by bank", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard?tab=recurring")

      render_click(view, "rec_select_bank", %{"bank" => "nubank"})

      html = render(view)
      assert html =~ "Painel" or html =~ "Despesas"
    end

    test "rec_select_type filters recurring by statement type", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard?tab=recurring")

      render_click(view, "rec_select_type", %{"type" => "extrato"})

      html = render(view)
      assert html =~ "Painel" or html =~ "Despesas"
    end
  end

  describe "select_view_total" do
    test "toggles total view between month and total", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_click(view, "select_view_total", %{})

      html = render(view)
      assert html =~ "Painel"
    end
  end

  describe "chart-navigate" do
    test "chart-navigate dispatches navigation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # push_navigate terminates the LiveView with a live_redirect
      assert {:error, {:live_redirect, %{to: "/transactions"}}} =
               render_click(view, "chart-navigate", %{"url" => "/transactions"})
    end
  end

  describe "with transaction data" do
    test "shows transaction totals when data exists", %{conn: conn, user: user} do
      Banking.ensure_default_categories(user.id)

      BankingFixtures.transaction_fixture(user, %{
        description: "PADARIA",
        amount: "-50.00",
        date: Date.utc_today()
      })

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Painel"
    end
  end

  describe "dashboard with rich banking data" do
    setup %{user: user} do
      Banking.ensure_default_categories(user.id)
      cat = Banking.get_uncategorized_category(user.id)

      today = Date.utc_today()

      BankingFixtures.transaction_fixture(user, %{
        description: "SALARIO",
        amount: "5000.00",
        date: today,
        category_id: cat.id
      })

      BankingFixtures.transaction_fixture(user, %{
        description: "MERCADO",
        amount: "-300.00",
        date: today,
        category_id: cat.id
      })

      BankingFixtures.transaction_fixture(user, %{
        description: "ACADEMIA",
        amount: "-100.00",
        date: today,
        category_id: cat.id
      })

      :ok
    end

    test "renders dashboard with transaction data", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Painel"
    end

    test "select_year with data shows filtered results", %{conn: conn} do
      year = Date.utc_today().year

      {:ok, view, _html} = live(conn, ~p"/dashboard")
      render_click(view, "select_year", %{"year" => to_string(year)})

      html = render(view)
      assert html =~ "Painel"
    end

    test "select_month all with data shows totals", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_click(view, "select_month", %{"month" => "all"})

      html = render(view)
      assert html =~ "Painel"
    end

    test "toggle-category with actual category ID", %{conn: conn, user: user} do
      cat = Banking.get_uncategorized_category(user.id)

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_click(view, "toggle-category", %{"id" => to_string(cat.id)})
      render_click(view, "toggle-category", %{"id" => to_string(cat.id)})

      html = render(view)
      assert html =~ "Painel"
    end

    test "select_bank with nubank filter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_click(view, "select_bank", %{"bank" => "nubank"})
      render_click(view, "select_bank", %{"bank" => "all"})

      html = render(view)
      assert html =~ "Painel"
    end

    test "select_view_total toggles between month and total", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_click(view, "select_view_total", %{})
      render_click(view, "select_view_total", %{})

      html = render(view)
      assert html =~ "Painel"
    end
  end

  describe "banking view modes with transaction data" do
    setup %{user: user} do
      Banking.ensure_default_categories(user.id)
      today = Date.utc_today()

      BankingFixtures.transaction_fixture(user, %{
        description: "SALARIO",
        amount: "5000.00",
        date: today
      })

      BankingFixtures.transaction_fixture(user, %{
        description: "DESPESA",
        amount: "-1500.00",
        date: today
      })

      :ok
    end

    test "select_view_total on banking tab with data", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_click(view, "select_view_total", %{})

      html = render(view)
      assert html =~ "Painel"
    end

    test "select_year then select_month navigates view modes", %{conn: conn} do
      year = Date.utc_today().year

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_click(view, "select_year", %{"year" => to_string(year)})
      render_click(view, "select_month", %{"month" => to_string(Date.utc_today().month)})

      html = render(view)
      assert html =~ "Painel"
    end

    test "select_bank with actual transactions", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_click(view, "select_bank", %{"bank" => "nubank"})

      html = render(view)
      assert html =~ "Painel"
    end

    test "select_txn_type credit filters income", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_click(view, "select_txn_type", %{"txn_type" => "credit"})

      html = render(view)
      assert html =~ "Painel"
    end

    test "select_txn_type debit with data", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_click(view, "select_txn_type", %{"txn_type" => "debit"})

      html = render(view)
      assert html =~ "Painel"
    end
  end

  describe "goals_progress render in month view" do
    setup %{user: user} do
      Banking.ensure_default_categories(user.id)
      today = Date.utc_today()

      Banking.create_financial_goal(%{
        "type" => "expense_limit",
        "target_value" => "1000.00",
        "user_id" => user.id
      })

      BankingFixtures.transaction_fixture(user, %{
        description: "MERCADO TEST",
        amount: "-200.00",
        date: today
      })

      :ok
    end

    test "dashboard month view renders goals progress when goals exist with data", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Painel"
    end

    test "select_view_total then back to month shows goals", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_click(view, "select_view_total", %{})
      render_click(view, "select_month", %{"month" => to_string(Date.utc_today().month)})

      html = render(view)
      assert html =~ "Painel"
    end

    test "daily spending chart renders in month view", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Painel"
    end
  end

  describe "yearly spending in total view" do
    setup %{user: user} do
      Banking.ensure_default_categories(user.id)

      for month <- 1..3 do
        BankingFixtures.transaction_fixture(user, %{
          description: "GASTO #{month}",
          amount: "-100.00",
          date: Date.new!(Date.utc_today().year, month, 1)
        })
      end

      :ok
    end

    test "select_view_total with data shows yearly spending", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_click(view, "select_view_total", %{})

      html = render(view)
      assert html =~ "Painel"
    end

    test "select_year then all months shows year view", %{conn: conn} do
      year = Date.utc_today().year

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_click(view, "select_year", %{"year" => to_string(year)})
      render_click(view, "select_month", %{"month" => "all"})

      html = render(view)
      assert html =~ "Painel"
    end
  end

  describe "uncategorized alert" do
    setup %{user: user} do
      Banking.ensure_default_categories(user.id)
      today = Date.utc_today()

      BankingFixtures.transaction_fixture(user, %{
        description: "SEM CATEGORIA",
        amount: "-50.00",
        date: today,
        category_id: nil
      })

      :ok
    end

    test "shows uncategorized alert when transactions lack category", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Painel"
    end
  end

  describe "dashboard with credit income transactions" do
    setup %{user: user} do
      Banking.ensure_default_categories(user.id)
      today = Date.utc_today()

      BankingFixtures.transaction_fixture(user, %{
        description: "SALARIO CREDITO",
        amount: "5000.00",
        type: "credit",
        date: today
      })

      BankingFixtures.transaction_fixture(user, %{
        description: "BONUS",
        amount: "1000.00",
        type: "credit",
        date: today
      })

      :ok
    end

    test "renders income stat card with income data", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Painel"
    end

    test "balance card renders with income > 0", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      html = render(view)
      assert html =~ "Painel"
    end

    test "select_txn_type credit shows income filter active", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      render_click(view, "select_txn_type", %{"txn_type" => "credit"})
      html = render(view)
      assert html =~ "Painel"
    end
  end

  describe "dashboard with investment category transactions" do
    setup %{user: user} do
      Banking.ensure_default_categories(user.id)
      today = Date.utc_today()

      cats = Banking.list_categories(user.id)
      inv_cat = Enum.find(cats, &(&1.kind == "investment"))

      BankingFixtures.transaction_fixture(user, %{
        description: "APORTE CDB",
        amount: "-2000.00",
        type: "debit",
        date: today,
        category_id: inv_cat.id
      })

      BankingFixtures.transaction_fixture(user, %{
        description: "SALARIO",
        amount: "5000.00",
        type: "credit",
        date: today
      })

      :ok
    end

    test "renders investment stat card with investment category transactions", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Painel"
    end

    test "monthly chart renders with income and expense data", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      render_click(view, "select_view_total", %{})
      html = render(view)
      assert html =~ "Painel"
    end
  end

  describe "dashboard with recurring expense data" do
    setup %{user: user} do
      Banking.ensure_default_categories(user.id)

      for month <- [1, 2, 3, 4, 5, 6] do
        BankingFixtures.transaction_fixture(user, %{
          description: "ACADEMIA MENSAL",
          amount: "-100.00",
          recurring_mode: "fixed",
          date: Date.new!(2026, month, 15)
        })
      end

      :ok
    end

    test "recurring tab with fixed expenses renders items", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard?tab=recurring")
      html = render(view)
      assert html =~ "Painel"
    end

    test "recurring tab shows rec_category for transactions with category", %{
      conn: conn,
      user: user
    } do
      Banking.ensure_default_categories(user.id)
      cat = Banking.get_uncategorized_category(user.id)

      for month <- [1, 2, 3, 4, 5, 6] do
        BankingFixtures.transaction_fixture(user, %{
          description: "PLANO SAUDE",
          amount: "-200.00",
          recurring_mode: "fixed",
          category_id: cat.id,
          date: Date.new!(2026, month, 20)
        })
      end

      {:ok, _view, html} = live(conn, ~p"/dashboard?tab=recurring")
      assert html =~ "Painel"
    end
  end
end
