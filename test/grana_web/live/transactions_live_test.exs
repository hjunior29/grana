defmodule GranaWeb.TransactionsLiveTest do
  use GranaWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Grana.Banking

  setup :register_and_log_in_user

  test "renders transactions page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/transactions")
    assert html =~ "Transações"
    assert html =~ "Nenhuma transação encontrada"
  end

  test "shows page description", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/transactions")
    assert html =~ "Visualize e gerencie todas as suas transações"
  end

  test "shows filter panel", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/transactions")
    assert html =~ "Todas"
    assert html =~ "Sem Categoria"
    assert html =~ "Limpar filtros"
    assert html =~ "Todos os bancos"
    assert html =~ "Todas transações"
  end

  test "shows transaction count", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/transactions")
    assert html =~ "Nenhuma transação"
  end

  test "shows sortable banking columns", %{conn: conn, user: user} do
    banking_transaction_fixture(user, description: "PADARIA", amount: "-12.00")

    {:ok, view, _html} = live(conn, ~p"/transactions")

    assert has_element?(view, "#banking-transactions-table")
    assert has_element?(view, "a[href*='sort_by=date']", "Data")
    assert has_element?(view, "a[href*='sort_by=description']", "Descrição")
    assert has_element?(view, "a[href*='sort_by=bank']", "Banco")
    assert has_element?(view, "a[href*='sort_by=category']", "Categoria")
    assert has_element?(view, "a[href*='sort_by=amount']", "Valor")
  end

  test "marks a transaction as fixed from the transaction row", %{conn: conn, user: user} do
    txn = banking_transaction_fixture(user, description: "SPOTIFY", amount: "-21.90")

    {:ok, view, _html} = live(conn, ~p"/transactions")

    assert has_element?(view, "#transaction-recurring-chip-#{txn.id}", "Variável")

    view
    |> element("#transaction-recurring-chip-#{txn.id}")
    |> render_click()

    view
    |> form("#transaction-recurring-form-#{txn.id}", %{
      "txn_id" => to_string(txn.id),
      "mode" => "fixed"
    })
    |> render_change()

    assert [rule] = Banking.list_recurring_rules(user.id)
    assert rule.pattern == "spotify"
    assert rule.mode == "fixed"
    assert has_element?(view, "#transaction-recurring-chip-#{txn.id}", "Fixa")
  end

  test "marks an inferred fixed transaction as variable", %{conn: conn, user: user} do
    txns =
      for n <- 0..4 do
        banking_transaction_fixture(user,
          date: month_date_ago(n, 10),
          description: "NETFLIX.COM",
          amount: "-44.90"
        )
      end

    txn = hd(txns)

    {:ok, view, _html} = live(conn, ~p"/transactions")

    assert has_element?(view, "#transaction-recurring-chip-#{txn.id}", "Fixa")

    view
    |> element("#transaction-recurring-chip-#{txn.id}")
    |> render_click()

    view
    |> form("#transaction-recurring-form-#{txn.id}", %{
      "txn_id" => to_string(txn.id),
      "mode" => "variable"
    })
    |> render_change()

    assert [rule] = Banking.list_recurring_rules(user.id)
    assert rule.pattern == "netflix com"
    assert rule.mode == "variable"
    assert has_element?(view, "#transaction-recurring-chip-#{txn.id}", "Variável")
  end

  test "redirects unauthenticated users", %{conn: _conn} do
    conn = build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/transactions")
  end

  defp banking_transaction_fixture(user, attrs) do
    Banking.ensure_default_categories(user.id)
    category = Banking.get_uncategorized_category(user.id)

    {:ok, statement} =
      Banking.create_statement(%{
        bank: Keyword.get(attrs, :bank, "nubank"),
        filename: "transactions-live-test.csv",
        statement_type: Keyword.get(attrs, :statement_type, "extrato"),
        user_id: user.id
      })

    description = Keyword.fetch!(attrs, :description)
    date = Keyword.get(attrs, :date, ~D[2026-01-10])

    {1, _} =
      Banking.bulk_insert_transactions([
        %{
          date: date,
          description: description,
          amount: Decimal.new(Keyword.fetch!(attrs, :amount)),
          type: Keyword.get(attrs, :type, "debit"),
          bank_statement_id: statement.id,
          user_id: user.id,
          category_id: category.id
        }
      ])

    user.id
    |> Banking.list_transactions(search: description, date_from: date, date_to: date)
    |> List.first()
  end

  defp month_date_ago(months_ago, day) do
    today = Date.utc_today()
    total = today.year * 12 + (today.month - 1) - months_ago
    year = div(total, 12)
    month = rem(total, 12) + 1

    Date.new!(year, month, min(day, Date.days_in_month(Date.new!(year, month, 1))))
  end
end
