defmodule GranaWeb.DashboardOpenFinanceTest do
  use GranaWeb.ConnCase, async: false

  use Oban.Testing, repo: Grana.Repo, engine: Oban.Engines.Lite

  import Phoenix.LiveViewTest
  import Grana.AccountsFixtures
  import Grana.OpenFinanceFixtures

  alias Grana.Workers.OpenFinanceSyncWorker

  setup :register_and_log_in_user

  test "the Open Finance tab sits next to the other dashboard tabs", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/dashboard")

    refute has_element?(lv, "#open-finance-tab")

    lv |> element("#tab-open-finance") |> render_click()
    assert_patch(lv, ~p"/dashboard?tab=open_finance")

    assert has_element?(lv, "#tab-open-finance.tab-active")
    assert has_element?(lv, "#open-finance-tab")
  end

  test "shows the empty state without accounts", %{conn: conn, user: user} do
    with_pluggy_credentials(user)

    {:ok, lv, html} = live(conn, ~p"/dashboard?tab=open_finance")

    assert has_element?(lv, "#open-finance-empty-state")
    assert html =~ "Conecte seus bancos pelo Meu Pluggy"
    refute has_element?(lv, "#sync-all")
  end

  test "explains that the integration is not configured", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/dashboard?tab=open_finance")

    assert html =~ "ainda não foi configurada"
  end

  test "ignores sync notifications while the tab was never opened", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/dashboard")

    send(lv.pid, {:open_finance_synced, 1})

    refute has_element?(lv, "#open-finance-tab")
  end

  test "picks up the first account when it arrives after the tab was opened", %{
    conn: conn,
    user: user
  } do
    {:ok, lv, _html} = live(conn, ~p"/dashboard?tab=open_finance")
    assert has_element?(lv, "#open-finance-empty-state")

    connection = connection_fixture(user)
    account = account_fixture(connection, %{marketing_name: "Chegou agora"})
    transaction_fixture(account, %{description: "PRIMEIRA"})
    send(lv.pid, {:open_finance_synced, connection.id})

    assert has_element?(lv, "#account-#{account.id}", "Chegou agora")
    assert has_element?(lv, "#open-finance-transactions", "PRIMEIRA")
  end

  describe "with accounts" do
    setup %{user: user} do
      connection = connection_fixture(user, %{connector_name: "Nubank"})

      bank =
        account_fixture(connection, %{
          marketing_name: "Conta Nubank",
          balance: Decimal.new("1234.56"),
          transfer_number: "260/0001/123-4",
          automatically_invested_balance: Decimal.new("50.00")
        })

      card =
        account_fixture(connection, %{
          type: "CREDIT",
          subtype: "CREDIT_CARD",
          name: "Ultravioleta",
          number: "4321",
          brand: "MASTERCARD",
          balance: Decimal.new("750.00"),
          credit_limit: Decimal.new("3000.00"),
          available_credit_limit: Decimal.new("2250.00"),
          balance_close_date: ~D[2026-10-20],
          balance_due_date: ~D[2026-10-27]
        })

      transaction_fixture(bank, %{
        description: "SALARIO",
        amount: Decimal.new("5000"),
        type: "CREDIT"
      })

      transaction_fixture(card, %{
        description: "MERCADO",
        amount: Decimal.new("120.50"),
        type: "DEBIT",
        status: "PENDING",
        installment_number: 1,
        total_installments: 3,
        operation_type: "PAGAMENTO"
      })

      %{connection: connection, bank: bank, card: card}
    end

    test "summarizes balances and card limits", %{conn: conn, bank: bank, card: card} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard?tab=open_finance")

      assert has_element?(lv, "#open-finance-summary", "R$ 1.234,56")
      assert has_element?(lv, "#open-finance-summary", "R$ 750,00")
      assert has_element?(lv, "#open-finance-summary", "R$ 2.250,00")

      assert has_element?(lv, "#account-#{bank.id}", "Conta Nubank")
      assert has_element?(lv, "#account-#{bank.id}", "aplicado automaticamente")
      assert has_element?(lv, "#account-#{card.id}", "final 4321")
      assert has_element?(lv, "#account-#{card.id}", "vence 27/10/2026")
      assert has_element?(lv, "#account-#{card.id} progress[value='25.0']")
    end

    test "shows the first account's transactions and switches account", %{
      conn: conn,
      card: card
    } do
      {:ok, lv, _html} = live(conn, ~p"/dashboard?tab=open_finance")

      assert has_element?(lv, "#open-finance-transactions", "SALARIO")
      assert has_element?(lv, "#open-finance-transactions", "+ R$ 5.000,00")

      lv |> element("#account-#{card.id}") |> render_click()
      assert_patch(lv, ~p"/dashboard?#{[tab: "open_finance", account: card.id]}")

      assert has_element?(lv, "#open-finance-transactions", "MERCADO")
      assert has_element?(lv, "#open-finance-transactions", "- R$ 120,50")
      assert has_element?(lv, "#open-finance-transactions", "Pendente")
      assert has_element?(lv, "#open-finance-transactions", "Parcela 1/3")
      refute has_element?(lv, "#open-finance-transactions", "SALARIO")
    end

    test "paginates long histories", %{conn: conn, bank: bank} do
      for day <- 1..55 do
        transaction_fixture(bank, %{
          description: "COMPRA #{String.pad_leading(to_string(day), 2, "0")}",
          date: Date.add(~D[2026-01-01], day),
          type: "DEBIT"
        })
      end

      {:ok, lv, _html} = live(conn, ~p"/dashboard?tab=open_finance&account=#{bank.id}")

      assert has_element?(lv, "#load-more-transactions")
      refute has_element?(lv, "#open-finance-transactions", "COMPRA 01")

      lv |> element("#load-more-transactions") |> render_click()

      assert has_element?(lv, "#open-finance-transactions", "COMPRA 01")
      refute has_element?(lv, "#load-more-transactions")
    end

    test "ignores accounts from other users in the URL", %{conn: conn} do
      other_connection = connection_fixture(user_fixture())
      other_account = account_fixture(other_connection, %{marketing_name: "Alheia"})

      {:ok, lv, _html} = live(conn, ~p"/dashboard?tab=open_finance&account=#{other_account.id}")

      refute has_element?(lv, "#account-#{other_account.id}")
      assert has_element?(lv, "#open-finance-transactions", "SALARIO")
    end

    test "syncs every connection and refreshes when done", %{
      conn: conn,
      connection: connection,
      bank: bank
    } do
      {:ok, lv, _html} = live(conn, ~p"/dashboard?tab=open_finance")

      lv |> element("#sync-all") |> render_click()
      assert_enqueued(worker: OpenFinanceSyncWorker, args: %{"connection_id" => connection.id})
      assert has_element?(lv, "#sync-all[disabled]")

      Grana.Repo.update!(Ecto.Changeset.change(bank, balance: Decimal.new("99.00")))
      send(lv.pid, {:open_finance_synced, connection.id})

      assert has_element?(lv, "#account-#{bank.id}", "R$ 99,00")
      refute has_element?(lv, "#sync-all[disabled]")
    end
  end
end
