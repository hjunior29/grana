defmodule GranaWeb.TransactionsOpenFinanceTest do
  use GranaWeb.ConnCase, async: false

  use Oban.Testing, repo: Grana.Repo, engine: Oban.Engines.Lite

  import Phoenix.LiveViewTest
  import Grana.BankingFixtures, only: [transaction_fixture: 2]
  import Grana.OpenFinanceFixtures

  alias Grana.Workers.OpenFinanceSyncWorker

  setup :register_and_log_in_user

  setup %{user: user} do
    connection = connection_fixture(user, %{last_synced_at: ~U[2026-01-01 00:00:00Z]})
    statement = open_finance_statement_fixture(account_fixture(connection))
    %{connection: connection, statement: statement}
  end

  test "marks rows that came from Open Finance and rereads a stale connection", %{
    conn: conn,
    user: user,
    connection: connection,
    statement: statement
  } do
    transaction_fixture(user, %{
      bank_statement_id: statement.id,
      date: ~D[2026-10-05],
      description: "PIX DO OPEN FINANCE"
    })

    transaction_fixture(user, %{date: ~D[2026-10-05], description: "LINHA DE UPLOAD"})

    {:ok, lv, html} = live(conn, ~p"/transactions")

    assert html =~ "PIX DO OPEN FINANCE"
    assert html =~ "LINHA DE UPLOAD"
    assert has_element?(lv, "svg[aria-label='Open Finance Brasil']")
    assert html |> String.split("aria-label=\"Open Finance Brasil\"") |> length() == 2
    assert_enqueued(worker: OpenFinanceSyncWorker, args: %{"connection_id" => connection.id})

    transaction_fixture(user, %{
      bank_statement_id: statement.id,
      date: ~D[2026-10-06],
      description: "CHEGOU DEPOIS"
    })

    send(lv.pid, {:open_finance_synced, connection.id})
    assert render(lv) =~ "CHEGOU DEPOIS"
  end
end
