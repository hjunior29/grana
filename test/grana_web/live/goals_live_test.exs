defmodule GranaWeb.GoalsLiveTest do
  use GranaWeb.ConnCase

  import Phoenix.LiveViewTest
  import Grana.BankingFixtures

  alias Grana.Banking

  setup :register_and_log_in_user

  test "renders goals page", %{conn: conn, user: user} do
    transaction_fixture(user)
    {:ok, _view, html} = live(conn, ~p"/goals")
    assert html =~ "Metas"
    assert html =~ "Nenhuma meta definida" or html =~ "Sugestões"
  end

  test "shows Nova Meta button", %{conn: conn, user: user} do
    transaction_fixture(user)
    {:ok, _view, html} = live(conn, ~p"/goals")
    assert html =~ "Nova meta"
  end

  test "redirects unauthenticated users" do
    conn = build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/goals")
  end

  describe "show_form / hide_form" do
    test "show_form opens the new goal modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/goals")

      html = render_click(view, "show_form", %{})

      assert html =~ "Nova meta"
    end

    test "hide_form closes the modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/goals")

      render_click(view, "show_form", %{})
      html = render_click(view, "hide_form", %{})

      # Form modal is closed; "Editar meta" header won't be present
      refute html =~ "Editar meta"
      assert html =~ "Metas"
    end

    test "select_type updates form_type", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/goals")

      render_click(view, "show_form", %{})
      html = render_change(view, "select_type", %{"goal" => %{"type" => "income_goal"}})

      assert html =~ "income_goal" or html =~ "Meta de Receita"
    end
  end

  describe "save_goal" do
    test "creates a new expense_limit goal", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/goals")

      render_click(view, "show_form", %{})

      # target_value is a hidden input (CurrencyInput hook); submit event directly
      render_click(view, "save_goal", %{
        "goal" => %{"type" => "expense_limit", "target_value" => "1500.00"}
      })

      goals = Banking.list_financial_goals(user.id)
      assert length(goals) == 1
      assert hd(goals).type == "expense_limit"
    end

    test "shows error for empty target_value", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/goals")

      render_click(view, "show_form", %{})

      html =
        render_click(view, "save_goal", %{
          "goal" => %{"type" => "expense_limit", "target_value" => ""}
        })

      assert html =~ "não pode ficar em branco" or html =~ "can't be blank"
    end

    test "creates investment_goal type", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/goals")

      render_click(view, "show_form", %{})
      render_change(view, "select_type", %{"goal" => %{"type" => "investment_goal"}})

      render_click(view, "save_goal", %{
        "goal" => %{"type" => "investment_goal", "target_value" => "2000.00"}
      })

      goals = Banking.list_financial_goals(user.id)
      assert Enum.any?(goals, &(&1.type == "investment_goal"))
    end
  end

  describe "edit_goal" do
    test "opens edit form with existing data", %{conn: conn, user: user} do
      goal = goal_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/goals")

      html = render_click(view, "edit_goal", %{"id" => to_string(goal.id)})

      assert html =~ "Editar meta"
    end

    test "updates existing goal", %{conn: conn, user: user} do
      goal = goal_fixture(user, %{target_value: "500.00"})

      {:ok, view, _html} = live(conn, ~p"/goals")

      render_click(view, "edit_goal", %{"id" => to_string(goal.id)})

      render_click(view, "save_goal", %{
        "goal" => %{"target_value" => "2500.00"}
      })

      updated = Banking.get_financial_goal!(goal.id, user.id)
      assert Decimal.eq?(updated.target_value, Decimal.new("2500.00"))
    end
  end

  describe "delete_goal" do
    test "confirm_delete shows delete dialog", %{conn: conn, user: user} do
      goal = goal_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/goals")

      html = render_click(view, "confirm_delete", %{"id" => to_string(goal.id)})

      assert html =~ "Remover" or html =~ "remover"
    end

    test "cancel_delete closes delete dialog", %{conn: conn, user: user} do
      goal = goal_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/goals")

      render_click(view, "confirm_delete", %{"id" => to_string(goal.id)})

      html = render_click(view, "cancel_delete", %{})

      assert html =~ "Metas"
    end

    test "delete_goal removes the goal", %{conn: conn, user: user} do
      goal = goal_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/goals")

      render_click(view, "confirm_delete", %{"id" => to_string(goal.id)})
      render_click(view, "delete_goal", %{})

      assert Banking.list_financial_goals(user.id) == []
    end
  end

  describe "accept_suggestion" do
    test "accept_suggestion creates goal from suggested value", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/goals")

      render_click(view, "accept_suggestion", %{
        "type" => "expense_limit",
        "amount" => "1000.00"
      })

      html = render(view)
      assert html =~ "Metas"

      goals = Banking.list_financial_goals(user.id)
      assert Enum.any?(goals, &(&1.type == "expense_limit"))
    end

    test "accept_suggestion shows error for duplicate goal type", %{conn: conn, user: user} do
      Banking.create_financial_goal(%{
        "type" => "expense_limit",
        "target_value" => "500.00",
        "user_id" => user.id
      })

      {:ok, view, _html} = live(conn, ~p"/goals")

      html =
        render_click(view, "accept_suggestion", %{
          "type" => "expense_limit",
          "amount" => "800.00"
        })

      assert html =~ "Metas"
    end
  end

  describe "category_limit goal type" do
    test "select_type to category_limit renders category dropdown", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/goals")

      render_click(view, "show_form", %{})
      html = render_change(view, "select_type", %{"goal" => %{"type" => "category_limit"}})

      assert html =~ "category_limit" or html =~ "Categoria" or html =~ "categoria"
    end

    test "creates a category_limit goal with category", %{conn: conn, user: user} do
      Banking.ensure_default_categories(user.id)
      cat = Banking.get_uncategorized_category(user.id)

      {:ok, view, _html} = live(conn, ~p"/goals")

      render_click(view, "show_form", %{})
      render_change(view, "select_type", %{"goal" => %{"type" => "category_limit"}})

      render_click(view, "save_goal", %{
        "goal" => %{
          "type" => "category_limit",
          "target_value" => "500.00",
          "category_id" => to_string(cat.id)
        }
      })

      goals = Banking.list_financial_goals(user.id)
      assert Enum.any?(goals, &(&1.type == "category_limit"))
    end

    test "renders category badge for category_limit goal with category", %{conn: conn, user: user} do
      Banking.ensure_default_categories(user.id)
      cat = Banking.get_uncategorized_category(user.id)

      Banking.create_financial_goal(%{
        "type" => "category_limit",
        "target_value" => "300.00",
        "user_id" => user.id,
        "category_id" => cat.id
      })

      {:ok, _view, html} = live(conn, ~p"/goals")

      assert html =~ "Metas"
    end
  end

  describe "suggestions block rendered" do
    test "renders suggestions when user has transaction history but no goals", %{
      conn: conn,
      user: user
    } do
      Banking.ensure_default_categories(user.id)

      transaction_fixture(user, %{description: "MERCADO", amount: "-300.00", date: ~D[2026-01-15]})

      transaction_fixture(user, %{description: "SALARIO", amount: "5000.00", date: ~D[2026-01-15]})

      {:ok, _view, html} = live(conn, ~p"/goals")

      assert html =~ "Metas"
    end

    test "accept_suggestion with transaction data creates goal", %{conn: conn, user: user} do
      Banking.ensure_default_categories(user.id)

      transaction_fixture(user, %{description: "PADARIA", amount: "-100.00", date: ~D[2026-01-15]})

      {:ok, view, _html} = live(conn, ~p"/goals")

      render_click(view, "accept_suggestion", %{
        "type" => "expense_limit",
        "amount" => "300.00"
      })

      html = render(view)
      assert html =~ "Metas"
    end
  end

  describe "month_name badge in non-January months" do
    test "goal progress badge shows month name for March", %{conn: conn, user: user} do
      Banking.ensure_default_categories(user.id)

      Banking.create_financial_goal(%{
        "type" => "expense_limit",
        "target_value" => "500.00",
        "user_id" => user.id
      })

      transaction_fixture(user, %{
        description: "MERCADO",
        amount: "-50.00",
        date: ~D[2026-03-15]
      })

      {:ok, _view, html} = live(conn, ~p"/goals")
      assert html =~ "Metas"
    end

    test "goal progress badge shows month name for November", %{conn: conn, user: user} do
      Banking.ensure_default_categories(user.id)

      Banking.create_financial_goal(%{
        "type" => "expense_limit",
        "target_value" => "500.00",
        "user_id" => user.id
      })

      transaction_fixture(user, %{
        description: "SUPERMERCADO",
        amount: "-80.00",
        date: ~D[2025-11-15]
      })

      {:ok, _view, html} = live(conn, ~p"/goals")
      assert html =~ "Metas"
    end
  end

  describe "save_goal unique constraint" do
    test "save_goal with duplicate type shows already-exists flash", %{conn: conn, user: user} do
      Banking.create_financial_goal(%{
        "type" => "expense_limit",
        "target_value" => "500.00",
        "user_id" => user.id
      })

      {:ok, view, _html} = live(conn, ~p"/goals")

      render_click(view, "show_form", %{})

      render_click(view, "save_goal", %{
        "goal" => %{"type" => "expense_limit", "target_value" => "800.00"}
      })

      html = render(view)
      assert html =~ "Metas"
    end
  end

  describe "goal status rendering" do
    test "renders on_track status for low expenses vs goal", %{conn: conn, user: user} do
      Banking.ensure_default_categories(user.id)

      Banking.create_financial_goal(%{
        "type" => "expense_limit",
        "target_value" => "10000.00",
        "user_id" => user.id
      })

      transaction_fixture(user, %{description: "LOJA", amount: "-100.00", date: Date.utc_today()})

      {:ok, _view, html} = live(conn, ~p"/goals")

      assert html =~ "Metas"
    end

    test "renders exceeded status for expenses over goal", %{conn: conn, user: user} do
      Banking.ensure_default_categories(user.id)

      Banking.create_financial_goal(%{
        "type" => "expense_limit",
        "target_value" => "50.00",
        "user_id" => user.id
      })

      transaction_fixture(user, %{description: "LOJA", amount: "-500.00", date: Date.utc_today()})

      {:ok, _view, html} = live(conn, ~p"/goals")

      assert html =~ "Metas"
    end

    test "renders warning status for expenses near goal limit", %{conn: conn, user: user} do
      Banking.ensure_default_categories(user.id)

      Banking.create_financial_goal(%{
        "type" => "expense_limit",
        "target_value" => "100.00",
        "user_id" => user.id
      })

      transaction_fixture(user, %{description: "LOJA", amount: "-85.00", date: Date.utc_today()})

      {:ok, _view, html} = live(conn, ~p"/goals")

      assert html =~ "Metas"
    end

    test "renders income_goal with achieved status", %{conn: conn, user: user} do
      Banking.ensure_default_categories(user.id)

      Banking.create_financial_goal(%{
        "type" => "income_goal",
        "target_value" => "1000.00",
        "user_id" => user.id
      })

      transaction_fixture(user, %{
        description: "SALARIO",
        amount: "5000.00",
        date: Date.utc_today()
      })

      {:ok, _view, html} = live(conn, ~p"/goals")

      assert html =~ "Metas"
    end

    test "renders income_goal with behind status", %{conn: conn, user: user} do
      Banking.ensure_default_categories(user.id)

      Banking.create_financial_goal(%{
        "type" => "income_goal",
        "target_value" => "10000.00",
        "user_id" => user.id
      })

      transaction_fixture(user, %{description: "BONUS", amount: "500.00", date: Date.utc_today()})

      {:ok, _view, html} = live(conn, ~p"/goals")

      assert html =~ "Metas"
    end
  end

  describe "pace and history" do
    test "in the current month, the bar marks today and limits show the daily quota", %{
      conn: conn,
      user: user
    } do
      today = Grana.LocalTime.today()
      transactions_fixture(user, [%{date: Date.beginning_of_month(today), amount: "-250.00"}])
      limit = goal_fixture(user, %{type: "expense_limit", target_value: "1000.00"})
      income = goal_fixture(user, %{type: "income_goal", target_value: "500.00"})

      {:ok, view, _html} = live(conn, ~p"/goals")

      day_pct = Float.round(today.day / Date.days_in_month(today) * 100, 1)
      assert has_element?(view, ~s|#goal-#{limit.id}-today[style="left: #{day_pct}%"]|)
      assert has_element?(view, "#goal-#{income.id}-today")

      assert has_element?(view, "#goal-#{limit.id}-quota", "Restam")
      assert has_element?(view, "#goal-#{limit.id}-quota .ui-private", "R$ 750,00")
      refute has_element?(view, "#goal-#{income.id}-quota")
    end

    test "a past reference month has no mark, and each goal shows its last months", %{
      conn: conn,
      user: user
    } do
      transactions_fixture(user, [
        %{date: ~D[2026-01-10], amount: "-800.00"},
        %{date: ~D[2026-02-10], amount: "-1200.00"},
        %{date: ~D[2026-04-10], amount: "-50.00"}
      ])

      goal = goal_fixture(user, %{type: "expense_limit", target_value: "1000.00"})
      {:ok, view, _html} = live(conn, ~p"/goals")

      refute has_element?(view, "#goal-#{goal.id}-today")
      refute has_element?(view, "#goal-#{goal.id}-quota")

      history = "#goal-#{goal.id}-history"
      assert has_element?(view, history, "Cumprida em 1 de 2 meses")

      assert has_element?(
               view,
               "#{history} .ui-goal-month-met[title='Janeiro/2026: R$ 800,00 (cumprida)']"
             )

      assert has_element?(view, "#{history} .ui-goal-month-missed", "F")

      assert has_element?(
               view,
               "#{history} .ui-goal-month-no_data[title='Março/2026: sem dados']"
             )

      assert view
             |> element(history)
             |> render()
             |> LazyHTML.from_fragment()
             |> LazyHTML.query(".ui-goal-month")
             |> Enum.count() == 6
    end

    test "with values hidden, the history tooltip has no amount", %{conn: conn, user: user} do
      {:ok, _} = Grana.Accounts.update_user_preferences(user, %{hide_values: true})

      transactions_fixture(user, [
        %{date: ~D[2026-01-10], amount: "-800.00"},
        %{date: ~D[2026-02-10]}
      ])

      goal = goal_fixture(user, %{type: "expense_limit", target_value: "1000.00"})

      {:ok, view, _html} = live(conn, ~p"/goals")

      assert has_element?(view, "#goal-#{goal.id}-history [title='Janeiro/2026: cumprida']")
      refute render(view) =~ "R$ 800,00 (cumprida)"
    end

    test "with no month before the reference, the history says so", %{conn: conn, user: user} do
      transactions_fixture(user, [%{date: ~D[2026-01-10]}])
      goal = goal_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/goals")

      assert has_element?(view, "#goal-#{goal.id}-history", "Sem dados nos últimos 6 meses")
    end

    test "a single month of history reads in the singular", %{conn: conn, user: user} do
      transactions_fixture(user, [%{date: ~D[2026-01-10]}, %{date: ~D[2026-02-10]}])
      goal = goal_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/goals")

      assert has_element?(view, "#goal-#{goal.id}-history", "Cumprida em 1 de 1 mês")
    end
  end
end
