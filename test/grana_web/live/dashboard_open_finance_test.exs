defmodule GranaWeb.DashboardOpenFinanceTest do
  use GranaWeb.ConnCase, async: false

  use Oban.Testing, repo: Grana.Repo, engine: Oban.Engines.Lite

  import Phoenix.LiveViewTest
  import Grana.BankingFixtures, only: [transaction_fixture: 2]
  import Grana.OpenFinanceFixtures

  alias Grana.Workers.OpenFinanceSyncWorker

  setup :register_and_log_in_user

  test "the main tab is called Resumo and there is no Open Finance tab", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/dashboard")

    assert html =~ "Resumo"
    refute html =~ "Bancário"
    refute html =~ "tab-open-finance"
  end

  test "without connections there is no Hoje block", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/dashboard")

    refute has_element?(lv, "#open-finance-today")
  end

  describe "with Open Finance" do
    setup %{user: user} do
      connection =
        connection_fixture(user, %{bank: "nubank", last_synced_at: ~U[2026-01-01 00:00:00Z]})

      checking =
        account_fixture(connection, %{
          marketing_name: "Conta Nubank",
          balance: Decimal.new("1234.56")
        })

      card =
        account_fixture(connection, %{
          type: "CREDIT",
          subtype: "CREDIT_CARD",
          name: "Ultravioleta",
          number: "4321",
          balance: Decimal.new("750.00"),
          credit_limit: Decimal.new("3000.00"),
          available_credit_limit: Decimal.new("2250.00"),
          balance_due_date: Date.add(Date.utc_today(), 2)
        })

      %{connection: connection, checking: checking, card: card}
    end

    test "shows today's position, cards and alerts above the history", %{
      conn: conn,
      checking: checking,
      card: card
    } do
      {:ok, lv, _html} = live(conn, ~p"/dashboard")

      assert has_element?(lv, "#open-finance-today-totals", "R$ 1.234,56")
      assert has_element?(lv, "#open-finance-today-totals", "R$ 750,00")
      assert has_element?(lv, "#open-finance-today-totals", "R$ 2.250,00")
      assert has_element?(lv, "#today-account-#{checking.id}", "Conta corrente")
      assert has_element?(lv, "#today-card-#{card.id}", "Ultravioleta")
      assert has_element?(lv, "#today-card-#{card.id}", "••4321")
      # Uso do limite = comprometido (limite - disponível), não só a fatura atual.
      assert has_element?(lv, "#today-card-#{card.id} progress[value='25.0']")
      assert has_element?(lv, "#today-card-#{card.id}", "25% do limite usado")
      assert has_element?(lv, "#open-finance-today-alerts", "vence em 2 dia(s)")
    end

    test "labels business accounts and leaves zero-balance due dates out of the alerts", %{
      conn: conn,
      user: user
    } do
      business = connection_fixture(user, %{bank: "nubank", holder_type: "PJ"})

      account_fixture(business, %{
        type: "CREDIT",
        subtype: "CREDIT_CARD",
        name: "company",
        balance: Decimal.new("0"),
        credit_limit: Decimal.new("9800"),
        available_credit_limit: Decimal.new("2800"),
        balance_due_date: Date.utc_today()
      })

      {:ok, lv, _html} = live(conn, ~p"/dashboard")

      assert has_element?(lv, "#today-bank-#{business.id}", "PJ")
      assert has_element?(lv, "#today-bank-#{business.id}", "71% do limite usado")
      refute has_element?(lv, "#open-finance-today-alerts", "Company")
    end

    test "is only shown on the Resumo tab", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard?tab=recurring")

      refute has_element?(lv, "#open-finance-today")
    end

    test "tells where Open Finance is filling a period without upload", %{
      conn: conn,
      user: user,
      checking: checking
    } do
      today = Date.utc_today()
      statement = open_finance_statement_fixture(checking)
      transaction_fixture(user, %{bank_statement_id: statement.id, date: today})

      {:ok, lv, _html} = live(conn, ~p"/dashboard")

      assert has_element?(lv, "#open-finance-today-sources", "(1)")
      cell = "#mini-calendar-#{today.year}-#{today.month}"
      assert has_element?(lv, "#{cell} svg[aria-label='Open Finance Brasil']")
      assert has_element?(lv, "#{cell}[title*='Open Finance: Nubank (extrato)']")
      assert has_element?(lv, ~s|#open-finance-calendar-link[href="/upload?tab=calendario"]|)
    end

    test "rereads Pluggy when the last read is older than 1 hour", %{
      conn: conn,
      connection: connection
    } do
      {:ok, _lv, _html} = live(conn, ~p"/dashboard")

      assert_enqueued(worker: OpenFinanceSyncWorker, args: %{"connection_id" => connection.id})
    end

    test "refreshes the Hoje block and the history when a read finishes", %{
      conn: conn,
      user: user,
      connection: connection,
      checking: checking
    } do
      {:ok, lv, _html} = live(conn, ~p"/dashboard")

      Grana.Repo.update!(Ecto.Changeset.change(checking, balance: Decimal.new("99.00")))
      statement = open_finance_statement_fixture(checking)

      transaction_fixture(user, %{
        bank_statement_id: statement.id,
        date: Date.utc_today(),
        description: "VEIO DO OPEN FINANCE"
      })

      send(lv.pid, {:open_finance_synced, connection.id})

      assert has_element?(lv, "#open-finance-today-totals", "R$ 99,00")
      assert render(lv) =~ "VEIO DO OPEN FINANCE"
    end
  end
end
