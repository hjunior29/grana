defmodule GranaWeb.TransactionsLiveTest do
  use GranaWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Grana.Banking
  alias Grana.Investments

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
    assert html =~ "Todas origens"
    assert html =~ "Todos movimentos"
  end

  test "shows transaction count", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/transactions")
    assert html =~ "Nenhuma transação"
  end

  test "shows sortable banking columns", %{conn: conn, user: user} do
    banking_transaction_fixture(user, description: "PADARIA", amount: "-12.00")

    {:ok, view, _html} = live(conn, ~p"/transactions")

    assert has_element?(view, "#transactions-table")
    assert has_element?(view, "a[href*='sort_by=date']", "Data")
    assert has_element?(view, "a[href*='sort_by=description']", "Transação")
    assert has_element?(view, "a[href*='sort_by=source']", "Origem")
    assert has_element?(view, "a[href*='sort_by=kind']", "Classificação")
    assert has_element?(view, "a[href*='sort_by=amount']", "Valor")
  end

  test "shows banking and investment transactions in one table", %{conn: conn, user: user} do
    bank_txn = banking_transaction_fixture(user, description: "PADARIA", amount: "-12.00")
    inv_txn = investment_transaction_fixture(user, asset_name: "TESOURO SELIC", amount: "100.00")

    {:ok, view, html} = live(conn, ~p"/transactions")

    assert has_element?(view, "#transaction-banking-#{bank_txn.id}")
    assert has_element?(view, "#transaction-investment-#{inv_txn.id}")
    assert html =~ "PADARIA"
    assert html =~ "TESOURO SELIC"
  end

  test "marks a transaction as fixed from the transaction row", %{conn: conn, user: user} do
    txn = banking_transaction_fixture(user, description: "SPOTIFY", amount: "-21.90")

    {:ok, view, _html} = live(conn, ~p"/transactions")

    # Select de recorrência já vem visível (sem troca/clique); 1 ocorrência → variável.
    assert has_element?(
             view,
             ~s(#transaction-recurring-form-#{txn.id} option[value="variable"][selected])
           )

    view
    |> form("#transaction-recurring-form-#{txn.id}", %{
      "txn_id" => to_string(txn.id),
      "mode" => "fixed"
    })
    |> render_change()

    assert [rule] = Banking.list_recurring_rules(user.id)
    assert rule.pattern == "spotify"
    assert rule.mode == "fixed"

    assert has_element?(
             view,
             ~s(#transaction-recurring-form-#{txn.id} option[value="fixed"][selected])
           )
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

    # 5 ocorrências → inferida como fixa; o select já vem visível e selecionado.
    assert has_element?(
             view,
             ~s(#transaction-recurring-form-#{txn.id} option[value="fixed"][selected])
           )

    view
    |> form("#transaction-recurring-form-#{txn.id}", %{
      "txn_id" => to_string(txn.id),
      "mode" => "variable"
    })
    |> render_change()

    assert [rule] = Banking.list_recurring_rules(user.id)
    assert rule.pattern == "netflix com"
    assert rule.mode == "variable"

    assert has_element?(
             view,
             ~s(#transaction-recurring-form-#{txn.id} option[value="variable"][selected])
           )
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

  defp investment_transaction_fixture(user, attrs) do
    inst = Investments.ensure_b3_institution(user.id)

    {:ok, statement} =
      Investments.create_statement(%{
        filename: "transactions-live-investments-test.xlsx",
        user_id: user.id,
        institution_id: inst.id,
        status: "completed"
      })

    asset_name = Keyword.fetch!(attrs, :asset_name)
    date = Keyword.get(attrs, :date, ~D[2026-01-11])

    {1, _} =
      Investments.bulk_insert_transactions([
        %{
          date: date,
          asset_name: asset_name,
          asset_ticker: Keyword.get(attrs, :asset_ticker),
          asset_type: Keyword.get(attrs, :asset_type, "renda_fixa"),
          operation: Keyword.get(attrs, :operation, "compra"),
          total_amount: Decimal.new(Keyword.fetch!(attrs, :amount)),
          user_id: user.id,
          statement_id: statement.id,
          institution_id: inst.id
        }
      ])

    user.id
    |> Investments.list_transactions(search: asset_name, date_from: date, date_to: date)
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
