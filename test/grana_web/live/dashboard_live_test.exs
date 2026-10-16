defmodule GranaWeb.DashboardLiveTest do
  use GranaWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders dashboard page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/dashboard")
    assert html =~ "Painel"
    assert html =~ "Nenhuma transação encontrada"
  end

  test "shows upload button when no transactions", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/dashboard")
    assert html =~ "Importar"
  end

  test "shows period selector description", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/dashboard")
    assert html =~ "Visão geral das suas finanças"
  end

  test "redirects unauthenticated users", %{conn: _conn} do
    conn = build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/dashboard")
  end

  describe "aba Despesas Fixas" do
    alias Grana.Banking

    test "sem nada importado, fica igual ao Resumo: sem filtros e com o botão de importar",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard?tab=recurring")

      assert has_element?(view, "#recurring-empty", "Nenhuma transação encontrada")

      assert has_element?(
               view,
               ~s|#recurring-empty a.btn-primary[href="/upload"]|,
               "Importar extratos"
             )

      refute has_element?(view, "#recurring-filters")
    end

    test "com dados fora da janela, mantém os filtros", %{conn: conn, user: user} do
      Grana.BankingFixtures.transaction_fixture(user, %{date: Date.add(Date.utc_today(), -800)})
      {:ok, view, _html} = live(conn, ~p"/dashboard?tab=recurring")

      assert has_element?(view, "#recurring-empty", "Nenhuma despesa encontrada nesse período")
      assert has_element?(view, "#recurring-filters")
    end

    test "mostra apenas a lista efetiva de despesas fixas", %{
      conn: conn,
      user: user
    } do
      Banking.ensure_default_categories(user.id)
      uncat = Banking.get_uncategorized_category(user.id)

      {:ok, stmt} =
        Banking.create_statement(%{
          bank: "bradesco",
          filename: "e.pdf",
          statement_type: "extrato",
          user_id: user.id
        })

      today = Date.utc_today()

      entries =
        for n <- 0..4 do
          total = today.year * 12 + (today.month - 1) - n

          %{
            date: Date.new!(div(total, 12), rem(total, 12) + 1, 10),
            description: "NETFLIX.COM",
            amount: Decimal.new("-44.90"),
            type: "debit",
            bank_statement_id: stmt.id,
            user_id: user.id,
            category_id: uncat.id
          }
        end

      Banking.bulk_insert_transactions(entries)

      {:ok, _view, html} = live(conn, ~p"/dashboard?tab=recurring")
      assert html =~ "NETFLIX"

      [txn | _] = Banking.list_transactions(user.id)
      assert {:ok, _rule} = Banking.set_transaction_recurring_mode(user.id, txn.id, "variable")

      assert [rule] = Banking.list_recurring_rules(user.id)
      assert rule.pattern == "netflix com"
      assert rule.mode == "variable"

      {:ok, _view, html} = live(conn, ~p"/dashboard?tab=recurring")
      refute html =~ "NETFLIX"
      assert html =~ "Nenhuma despesa fixa"
    end
  end
end
