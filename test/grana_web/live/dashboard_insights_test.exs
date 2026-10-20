defmodule GranaWeb.DashboardInsightsTest do
  use GranaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Grana.BankingFixtures
  import Grana.OpenFinanceFixtures

  alias Grana.Banking

  setup :register_and_log_in_user

  describe "a past month" do
    setup %{user: user} do
      transactions_fixture(user, [
        %{date: ~D[2026-02-05], description: "SALARIO", amount: "500.00", type: "credit"},
        %{date: ~D[2026-02-10], description: "MERCADO BOM", amount: "-400.00"},
        %{date: ~D[2026-03-05], description: "SALARIO", amount: "1000.00", type: "credit"},
        %{date: ~D[2026-03-02], description: "PADARIA PAO", amount: "-50.00"},
        %{date: ~D[2026-03-20], description: "PADARIA PAO", amount: "-30.00"},
        %{date: ~D[2026-03-25], description: "LIVRARIA", amount: "-120.00"}
      ])

      :ok
    end

    test "the cards compare with the previous month and show the recent average", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert has_element?(view, "#stat-expenses-trend.ui-tag-ativo", "50,0%")
      assert has_element?(view, "#stat-expenses-trend[title='Comparado com Fevereiro/2026']")
      assert has_element?(view, "#stat-income-trend.ui-tag-ativo", "100,0%")
      refute has_element?(view, "#stat-investments-trend")
      assert has_element?(view, "#stat-expenses", "média 1m:")
      assert has_element?(view, "#stat-expenses .ui-private", "R$ 400,00")

      # No year before: nothing to compare with.
      render_click(view, "select_month", %{"month" => "all"})
      refute has_element?(view, "#stat-expenses-trend")
      assert has_element?(view, "#stat-expenses", "transações")
    end

    test "more spending than the month before is an alert", %{conn: conn, user: user} do
      transactions_fixture(user, [%{date: ~D[2026-03-28], amount: "-1000.00"}])
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert has_element?(view, "#stat-expenses-trend.ui-tag-erro", "200,0%")
    end

    test "the pace view draws the month over the previous one", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view |> element("#daily-view-pace") |> render_click()

      assert has_element?(view, "#daily-view-pace[aria-pressed=true]")
      refute has_element?(view, "#daily-chart")
      assert has_element?(view, "#pace-chart[phx-hook=SpendingCalendar] .ui-pace-line")
      assert has_element?(view, "#pace-chart .ui-pace-reference")
      refute has_element?(view, "#pace-chart .ui-pace-dot")
      assert has_element?(view, "#pace-summary", "Até o dia 31")
      assert has_element?(view, "#pace-summary", "em fevereiro")
      assert has_element?(view, "#pace-summary .ui-private", "R$ 200,00")
      assert has_element?(view, "#pace-delta.ui-tag-ativo", "50,0%")

      assert has_element?(
               view,
               ~s|#pace-chart [data-day-date="Até o dia 20"][data-day-value="80.0"]|
             )

      assert view |> element(~s|#pace-chart [data-day-date="Até o dia 20"]|) |> render() =~
               "date_to=2026-03-20"

      # The year has no pace: it shows the bars and keeps the choice for the month.
      render_click(view, "select_month", %{"month" => "all"})
      assert has_element?(view, "#monthly-spending-chart")
      assert has_element?(view, "#monthly-view-bars[aria-pressed=true]")
    end

    test "where the money went, by merchant", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert has_element?(view, "#merchants-card", "2 estabelecimentos em março de 2026")
      assert has_element?(view, "#merchant-1", "LIVRARIA")
      assert has_element?(view, "#merchant-2", "PADARIA PAO")
      assert has_element?(view, "#merchant-2", "2 compras")
      assert has_element?(view, "#merchant-2 .ui-private", "R$ 40,00")
      assert has_element?(view, "#merchant-1", "60.0%")
      assert has_element?(view, "#merchant-2 a[href*='search=PADARIA+PAO']")
      refute has_element?(view, "#merchants-toggle")

      render_click(view, "select_txn_type", %{"txn_type" => "credit"})
      refute has_element?(view, "#merchants-card")
    end

    test "a long merchant list opens on demand", %{conn: conn, user: user} do
      transactions_fixture(
        user,
        for(n <- 1..9, do: %{date: ~D[2026-03-11], description: "LOJA #{<<?A + n>>}"})
      )

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      refute has_element?(view, "#merchant-9")
      view |> element("#merchants-toggle", "Ver todos (11)") |> render_click()
      assert has_element?(view, "#merchant-11")
      view |> element("#merchants-toggle", "Mostrar menos") |> render_click()
      refute has_element?(view, "#merchant-9")
    end
  end

  describe "installments" do
    setup %{user: user} do
      Banking.ensure_default_categories(user.id)
      statement = statement_fixture(user, %{statement_type: "fatura"})

      rows =
        for {description, amount, current, total} <- [
              {"CURSO 9/10", "-460.00", 9, 10},
              {"LOJA 3/10", "-240.00", 3, 10}
            ] do
          %{
            date: ~D[2026-03-08],
            description: description,
            amount: Decimal.new(amount),
            type: "debit",
            installment_current: current,
            installment_total: total,
            installment_group_id: description,
            bank_statement_id: statement.id,
            user_id: user.id
          }
        end

      {2, _} = Banking.bulk_insert_transactions(rows)
      :ok
    end

    test "the projection shows when the budget gets relief", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert has_element?(view, "#installments-relief", "Alívio em Abr/26")
      assert has_element?(view, "#installments-relief .ui-private", "R$ 460,00")
    end

    test "a simulated purchase stacks on the next months, hidden until asked", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      refute has_element?(view, "#simulation-form")
      view |> element("#simulation-open") |> render_click()
      assert has_element?(view, "#simulation-result", "Digite o valor")
      refute has_element?(view, "#simulation-open")

      # The hidden total is what the currency hook writes from what was typed.
      view
      |> element("#simulation-form")
      |> render_change(%{"sim" => %{"total" => "2400.00", "count" => "10"}})

      assert has_element?(view, "#simulation-result", "10x de")
      assert has_element?(view, "#simulation-result .ui-private", "R$ 240,00")
      assert has_element?(view, "#simulation-result", "a partir de Abr/26")

      data =
        view
        |> element("#projection-chart")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.attribute("data-projections")
        |> hd()
        |> Jason.decode!()

      # Mar/26 keeps only the real installments; Apr/26 to Jan/27 get the simulation,
      # past the 8 months the current installments last.
      assert %{"label" => "Mar/2026", "sim" => +0.0} = hd(data)
      assert %{"label" => "Abr/2026", "sim" => 240.0, "value" => 240.0} = Enum.at(data, 1)
      assert %{"label" => "Jan/2027", "sim" => 240.0, "value" => +0.0} = List.last(data)
      assert length(data) == 11

      view |> element("#simulation-close") |> render_click()
      refute has_element?(view, "#simulation-form")
      chart = view |> element("#projection-chart") |> render()
      refute chart =~ "&quot;sim&quot;:240.0"
      refute chart =~ "Jan/2027"
    end

    test "an invalid value just waits for a valid one", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      view |> element("#simulation-open") |> render_click()

      render_change(view, "simulate", %{"sim" => %{"total" => "abc", "count" => "99"}})

      assert has_element?(view, "#simulation-result", "Digite o valor")
      assert has_element?(view, "#simulation-form input[name='sim[count]'][value='48']")
    end
  end

  describe "the current month" do
    setup %{user: user} do
      today = Grana.LocalTime.today()
      month = Date.beginning_of_month(today)

      transactions_fixture(
        user,
        [%{date: month, description: "STREAMING TV", amount: "-40.00"}] ++
          Enum.flat_map(1..3, fn n ->
            date = Date.shift(month, month: -n)

            [
              %{date: Date.add(date, 4), description: "STREAMING TV", amount: "-40.00"},
              %{date: Date.add(date, 9), description: "ACADEMIA FORTE", amount: "-120.00"}
            ]
          end)
      )

      %{today: today}
    end

    test "with Open Finance, the free balance discounts bills and pending fixed expenses", %{
      conn: conn,
      user: user
    } do
      connection = connection_fixture(user)
      account_fixture(connection, %{balance: Decimal.new("1000.00")})

      account_fixture(connection, %{
        type: "CREDIT",
        subtype: "CREDIT_CARD",
        name: "Cartão",
        balance: Decimal.new("300.00")
      })

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert has_element?(view, "#liquidity-card", "Livre depois de faturas e fixas")
      assert has_element?(view, "#liquidity-free", "R$ 580,00")
      assert has_element?(view, "#liquidity-bills", "R$ 300,00")
      assert has_element?(view, "#liquidity-pending", "R$ 120,00")
      assert has_element?(view, "#liquidity-pending-list", "1 fixa ainda não caiu")
      assert has_element?(view, "#liquidity-pending-list .ui-private-name", "ACADEMIA FORTE")

      # Not on the fixed expenses tab.
      render_click(view, "switch_tab", %{"tab" => "recurring"})
      refute has_element?(view, "#liquidity-card")
    end

    test "when bills and fixed expenses pass the balance, it says what is missing", %{
      conn: conn,
      user: user
    } do
      connection = connection_fixture(user)
      account_fixture(connection, %{balance: Decimal.new("100.00")})

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert has_element?(view, "#liquidity-card", "Falta para cobrir faturas e fixas")
      assert has_element?(view, "#liquidity-free.ui-money-despesa", "R$ 20,00")
    end

    test "without Open Finance there is no free balance card", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      refute has_element?(view, "#liquidity-card")
    end

    test "goals of the month show today's mark and the daily quota", %{
      conn: conn,
      user: user,
      today: today
    } do
      goal = goal_fixture(user, %{type: "expense_limit", target_value: "1000.00"})
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      day_pct = Float.round(today.day / Date.days_in_month(today) * 100, 1)

      assert has_element?(
               view,
               ~s|#dashboard-goal-#{goal.id} .ui-goal-needle[style="left: #{day_pct}%"]|
             )

      assert has_element?(view, "#dashboard-goal-#{goal.id}", "Restam")
      assert has_element?(view, "#dashboard-goal-#{goal.id} .ui-private", "R$ 960,00")
    end

    test "the pace of the current month stops today, with a dot", %{conn: conn, today: today} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      view |> element("#daily-view-pace") |> render_click()

      assert has_element?(view, "#pace-chart .ui-pace-dot")
      assert has_element?(view, "#pace-summary", "Até o dia #{today.day}")
      refute has_element?(view, ~s|#pace-chart [data-day-date="Até o dia #{today.day + 1}"]|)
    end
  end

  test "saved fixed-expense rules can be removed from the fixed expenses tab", %{
    conn: conn,
    user: user
  } do
    transactions_fixture(user, [%{date: ~D[2026-03-02], description: "PADARIA PAO"}])
    Banking.upsert_recurring_rule(user.id, "PADARIA PAO", "variable")
    Banking.upsert_recurring_rule(user.id, "ACADEMIA", "fixed")

    {:ok, view, _html} = live(conn, ~p"/dashboard?tab=recurring")

    refute has_element?(view, "#rec-rules-modal")
    view |> element("#rec-rules-open", "Regras salvas (2)") |> render_click()

    assert has_element?(view, "#rec-rules-modal .ui-private-name", "academia")
    assert has_element?(view, "#rec-rules-modal", "fixa")
    assert has_element?(view, "#rec-rules-modal", "variável")

    view
    |> element(~s|#rec-rules-modal button[phx-value-pattern="padaria pao"]|)
    |> render_click()

    assert render(view) =~ "Regra removida"
    assert Enum.map(Banking.list_recurring_rules(user.id), & &1.pattern) == ["academia"]
    assert has_element?(view, "#rec-rules-open", "Regras salvas (1)")

    view |> element(~s|#rec-rules-modal button[phx-value-pattern="academia"]|) |> render_click()

    refute has_element?(view, "#rec-rules-modal")
    refute has_element?(view, "#rec-rules-open")
  end

  test "the rules modal closes without changing anything", %{conn: conn, user: user} do
    transactions_fixture(user, [%{date: ~D[2026-03-02]}])
    Banking.upsert_recurring_rule(user.id, "ACADEMIA", "fixed")

    {:ok, view, _html} = live(conn, ~p"/dashboard?tab=recurring")
    view |> element("#rec-rules-open") |> render_click()
    render_click(view, "close_rec_rules", %{})

    refute has_element?(view, "#rec-rules-modal")
    assert length(Banking.list_recurring_rules(user.id)) == 1
  end
end
