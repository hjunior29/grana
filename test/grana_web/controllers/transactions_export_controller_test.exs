defmodule GranaWeb.TransactionsExportControllerTest do
  use GranaWeb.ConnCase

  import Grana.AccountsFixtures
  alias Grana.BankingFixtures
  alias Grana.InvestmentsFixtures

  setup :register_and_log_in_user

  describe "GET /transactions/export" do
    test "returns CSV file for authenticated user with no transactions", %{conn: conn} do
      conn = get(conn, ~p"/transactions/export")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/csv; charset=utf-8"]
      [cd] = get_resp_header(conn, "content-disposition")
      assert cd =~ "attachment"
      assert cd =~ "transacoes_"
      assert cd =~ ".csv"
    end

    test "returns CSV containing transaction data", %{conn: conn, user: user} do
      BankingFixtures.transaction_fixture(user, %{description: "PADARIA TESTE", amount: "-25.00"})

      conn = get(conn, ~p"/transactions/export")

      assert conn.status == 200
      assert conn.resp_body =~ "PADARIA TESTE"
    end

    test "redirects unauthenticated users" do
      conn = build_conn()
      conn = get(conn, ~p"/transactions/export")
      assert redirected_to(conn) =~ "/users/log-in"
    end

    test "accepts search filter param", %{conn: conn, user: user} do
      BankingFixtures.transaction_fixture(user, %{description: "SUPERMERCADO", amount: "-150.00"})
      BankingFixtures.transaction_fixture(user, %{description: "FARMACIA", amount: "-30.00"})

      conn = get(conn, ~p"/transactions/export?search=SUPERMERCADO")

      assert conn.status == 200
      assert conn.resp_body =~ "SUPERMERCADO"
      refute conn.resp_body =~ "FARMACIA"
    end

    test "accepts date_from and date_to params", %{conn: conn, user: user} do
      BankingFixtures.transaction_fixture(user, %{
        description: "CONTA JANEIRO",
        amount: "-50.00",
        date: ~D[2026-01-15]
      })

      conn = get(conn, ~p"/transactions/export?date_from=2026-01-01&date_to=2026-01-31")

      assert conn.status == 200
      assert conn.resp_body =~ "CONTA JANEIRO"
    end

    test "accepts type filter param", %{conn: conn, user: user} do
      BankingFixtures.transaction_fixture(user, %{
        description: "SALARIO",
        amount: "5000.00",
        type: "credit"
      })

      conn = get(conn, ~p"/transactions/export?type=credit")

      assert conn.status == 200
      assert conn.resp_body =~ "SALARIO"
    end

    test "accepts filter=uncategorized param", %{conn: conn} do
      conn = get(conn, ~p"/transactions/export?filter=uncategorized")
      assert conn.status == 200
    end

    test "accepts amount_min and amount_max params", %{conn: conn} do
      conn = get(conn, ~p"/transactions/export?amount_min=10.00&amount_max=100.00")
      assert conn.status == 200
    end

    test "accepts bank and statement_type params", %{conn: conn} do
      conn = get(conn, ~p"/transactions/export?bank=nubank&statement_type=extrato")
      assert conn.status == 200
    end

    test "accepts sort_by and sort_dir params", %{conn: conn} do
      conn = get(conn, ~p"/transactions/export?sort_by=date&sort_dir=asc")
      assert conn.status == 200
    end

    test "accepts statement_id param", %{conn: conn, user: user} do
      {:ok, stmt} =
        Grana.Banking.create_statement(%{
          bank: "nubank",
          filename: "test.csv",
          statement_type: "extrato",
          user_id: user.id
        })

      conn = get(conn, ~p"/transactions/export?statement_id=#{stmt.id}")
      assert conn.status == 200
    end

    test "accepts invalid date_from gracefully", %{conn: conn} do
      conn = get(conn, ~p"/transactions/export?date_from=not-a-date")
      assert conn.status == 200
    end

    test "accepts category_id param", %{conn: conn, user: user} do
      Grana.Banking.ensure_default_categories(user.id)
      cat = Grana.Banking.get_uncategorized_category(user.id)
      conn = get(conn, ~p"/transactions/export?category_id=#{cat.id}")
      assert conn.status == 200
    end
  end

  describe "GET /transactions/export/investments" do
    test "returns CSV file for authenticated user with no investments", %{conn: conn} do
      conn = get(conn, ~p"/transactions/export/investments")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/csv; charset=utf-8"]
      [cd] = get_resp_header(conn, "content-disposition")
      assert cd =~ "investimentos_"
      assert cd =~ ".csv"
    end

    test "returns CSV containing investment data", %{conn: conn, user: user} do
      InvestmentsFixtures.transaction_fixture(user, %{
        asset_name: "PETR4 EXPORTTEST",
        total_amount: "500.00"
      })

      conn = get(conn, ~p"/transactions/export/investments")

      assert conn.status == 200
      assert conn.resp_body =~ "PETR4 EXPORTTEST"
    end

    test "accepts search filter", %{conn: conn, user: user} do
      InvestmentsFixtures.transaction_fixture(user, %{
        asset_name: "VALE3 ONLY",
        total_amount: "200.00"
      })

      InvestmentsFixtures.transaction_fixture(user, %{
        asset_name: "PETR4 OTHER",
        total_amount: "300.00"
      })

      conn = get(conn, ~p"/transactions/export/investments?search=VALE3")

      assert conn.status == 200
      assert conn.resp_body =~ "VALE3 ONLY"
      refute conn.resp_body =~ "PETR4 OTHER"
    end

    test "accepts single operation filter", %{conn: conn, user: user} do
      InvestmentsFixtures.transaction_fixture(user, %{
        asset_name: "FUNDO DIV",
        total_amount: "100.00",
        operation: "dividendo"
      })

      conn = get(conn, ~p"/transactions/export/investments?operation=dividendo")
      assert conn.status == 200
      assert conn.resp_body =~ "FUNDO DIV"
    end

    test "accepts operation filter with comma-separated list", %{conn: conn} do
      conn = get(conn, ~p"/transactions/export/investments?operation=dividendo,jcp")
      assert conn.status == 200
    end

    test "accepts all filter for operation" do
      conn = build_conn()

      conn =
        conn
        |> setup_conn_with_user()
        |> get(~p"/transactions/export/investments?operation=all")

      assert conn.status == 200
    end
  end

  defp setup_conn_with_user(conn) do
    user = user_fixture()
    log_in_user(conn, user)
  end
end
