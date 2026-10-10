defmodule Grana.OpenFinanceTest do
  use Grana.DataCase, async: false

  use Mimic
  use Oban.Testing, repo: Grana.Repo, engine: Oban.Engines.Lite

  import Grana.AccountsFixtures

  import Grana.BankingFixtures,
    only: [category_fixture: 2, statement_fixture: 2, transaction_fixture: 2]

  import Grana.OpenFinanceFixtures

  alias Grana.Accounts.{Scope, User}
  alias Grana.Banking.BankStatement
  alias Grana.Banking.Transaction, as: BankingTransaction
  alias Grana.OpenFinance
  alias Grana.OpenFinance.{Account, Connection, Pluggy}
  alias Grana.Workers.OpenFinanceSyncWorker

  @creds %{client_id: "0b0e2a4c-6c2d-4b8e-9f3a-1d2c3b4a5e6f", client_secret: "test-secret"}
  @webhook_url "https://grana.example.com/webhooks/pluggy"

  setup do
    user = with_pluggy_credentials(user_fixture())
    %{user: user, scope: Scope.for_user(user)}
  end

  defp put_pluggy_env(overrides) do
    original = Application.get_env(:grana, :pluggy)
    on_exit(fn -> Application.put_env(:grana, :pluggy, original || []) end)
    Application.put_env(:grana, :pluggy, overrides)
  end

  defp with_webhook_url(_context) do
    put_pluggy_env(webhook_url: @webhook_url)
    :ok
  end

  describe "credentials" do
    test "uses the credentials saved in the database", %{scope: scope} do
      assert OpenFinance.credentials(scope) == @creds
      assert OpenFinance.credentials_source(scope) == :database
      assert OpenFinance.configured?(scope)
    end

    test "the environment takes precedence over saved credentials", %{scope: scope} do
      put_pluggy_env(client_id: "env-id", client_secret: "env-secret")

      assert OpenFinance.credentials(scope) == %{client_id: "env-id", client_secret: "env-secret"}
      assert OpenFinance.credentials_source(scope) == :env
    end

    test "without environment or saved credentials it is not configured" do
      scope = user_scope_fixture()

      assert OpenFinance.credentials(scope) == nil
      assert OpenFinance.credentials_source(scope) == nil
      refute OpenFinance.configured?(scope)
    end

    test "change_credentials/2 never carries the saved secret", %{scope: scope} do
      changeset = OpenFinance.change_credentials(scope)

      assert Ecto.Changeset.get_field(changeset, :pluggy_client_id) == @creds.client_id
      assert Ecto.Changeset.get_field(changeset, :pluggy_client_secret) == nil
    end

    test "save_credentials/2 verifies on Pluggy and stores the secret encrypted" do
      scope = user_scope_fixture()
      client_id = Ecto.UUID.generate()

      expect(Pluggy, :verify_credentials, fn creds ->
        assert creds == %{client_id: client_id, client_secret: "new-secret"}
        :ok
      end)

      assert {:ok, %User{} = user} =
               OpenFinance.save_credentials(scope, %{
                 "pluggy_client_id" => " #{client_id} ",
                 "pluggy_client_secret" => "new-secret"
               })

      assert Repo.get!(User, user.id).pluggy_client_secret == "new-secret"

      %{rows: [[stored]]} =
        Repo.query!("SELECT pluggy_client_secret FROM users WHERE id = ?", [user.id])

      refute stored =~ "new-secret"
    end

    test "save_credentials/2 requires both fields and a UUID client id", %{scope: scope} do
      reject(Pluggy, :verify_credentials, 1)

      assert {:error, changeset} =
               OpenFinance.save_credentials(scope, %{
                 "pluggy_client_id" => "nope",
                 "pluggy_client_secret" => ""
               })

      assert %{pluggy_client_id: [_], pluggy_client_secret: ["can't be blank"]} =
               errors_on(changeset)
    end

    test "save_credentials/2 reports credentials rejected by Pluggy", %{scope: scope} do
      stub(Pluggy, :verify_credentials, fn _ -> {:error, :invalid_credentials} end)

      assert {:error, changeset} =
               OpenFinance.save_credentials(scope, %{
                 "pluggy_client_id" => Ecto.UUID.generate(),
                 "pluggy_client_secret" => "wrong"
               })

      assert %{pluggy_client_secret: [message]} = errors_on(changeset)
      assert message =~ "recusou"
      assert Repo.get!(User, scope.user.id).pluggy_client_secret == "test-secret"
    end

    test "remove_credentials/1 clears credentials and the webhook secret", %{user: user} do
      user = with_pluggy_credentials(user, %{pluggy_webhook_secret: "wh"})

      assert {:ok, _} = OpenFinance.remove_credentials(Scope.for_user(user))

      assert %User{
               pluggy_client_id: nil,
               pluggy_client_secret: nil,
               pluggy_webhook_secret: nil
             } = Repo.get!(User, user.id)
    end
  end

  describe "add_connection/2" do
    test "verifies the item on Pluggy, stores it and schedules a sync", %{
      scope: scope,
      user: user
    } do
      item = item_payload()
      item_id = item["id"]
      expect(Pluggy, :get_item, fn @creds, ^item_id -> {:ok, item} end)

      assert {:ok, %Connection{} = connection} = OpenFinance.add_connection(scope, " #{item_id} ")

      assert connection.user_id == user.id
      assert connection.item_id == item_id
      assert connection.connector_name == "MeuPluggy"
      assert connection.status == "UPDATED"
      assert connection.pluggy_updated_at == ~U[2026-10-10 06:17:59Z]
      assert_enqueued(worker: OpenFinanceSyncWorker, args: %{"connection_id" => connection.id})
    end

    test "needs credentials" do
      assert OpenFinance.add_connection(user_scope_fixture(), Ecto.UUID.generate()) ==
               {:error, :not_configured}
    end

    test "rejects ids that are not UUIDs without calling Pluggy", %{scope: scope} do
      reject(Pluggy, :get_item, 2)

      assert OpenFinance.add_connection(scope, "not-an-id") == {:error, :invalid_item_id}
    end

    test "rejects items unknown to this Pluggy application", %{scope: scope} do
      stub(Pluggy, :get_item, fn _, _ -> {:error, :not_found} end)

      assert OpenFinance.add_connection(scope, Ecto.UUID.generate()) == {:error, :not_found}
      assert Repo.aggregate(Connection, :count) == 0
    end

    test "does not link the same item twice, even for another user", %{scope: scope, user: user} do
      connection = connection_fixture(user)
      reject(Pluggy, :get_item, 2)

      assert OpenFinance.add_connection(scope, connection.item_id) == {:error, :already_connected}

      other = Scope.for_user(with_pluggy_credentials(user_fixture()))
      assert OpenFinance.add_connection(other, connection.item_id) == {:error, :already_connected}
    end
  end

  describe "sync_connection/1" do
    setup %{user: user} do
      connection = connection_fixture(user, %{status: "UPDATING", last_synced_at: nil})
      Phoenix.PubSub.subscribe(Grana.PubSub, OpenFinance.topic(user.id))
      %{connection: connection}
    end

    defp stub_pluggy(item, accounts, transactions_by_account) do
      stub(Pluggy, :get_identity, fn @creds, _ -> {:ok, %{"documentType" => "CPF"}} end)
      stub(Pluggy, :get_item, fn @creds, _ -> {:ok, item} end)
      stub(Pluggy, :list_accounts, fn @creds, _ -> {:ok, accounts} end)

      stub(Pluggy, :list_transactions, fn @creds, id ->
        {:ok, Map.get(transactions_by_account, id, [])}
      end)
    end

    defp bradesco_account(attrs \\ %{}),
      do: bank_account_payload(Map.merge(%{"name" => "Banco Bradesco"}, attrs))

    defp of_transactions(user) do
      from(t in BankingTransaction,
        join: s in assoc(t, :bank_statement),
        where: t.user_id == ^user.id and s.source == "open_finance",
        order_by: [t.date, t.id],
        preload: [bank_statement: s, category: []]
      )
      |> Repo.all()
    end

    test "keeps the snapshot of accounts and fills periods without uploads", %{
      connection: connection,
      user: user
    } do
      bank = bradesco_account()
      card = card_account_payload()

      card_purchase =
        transaction_payload(%{
          "description" => "NETFLIX.COM",
          "amount" => 55.9,
          "type" => "DEBIT",
          "date" => "2026-10-01T02:30:00.000Z",
          "categoryId" => "09010000",
          "creditCardMetadata" => %{
            "installmentNumber" => 2.0,
            "totalInstallments" => 6,
            "billId" => "bill-1"
          }
        })

      open_bill = transaction_payload(%{"description" => "PADARIA", "type" => "DEBIT"})

      stub_pluggy(item_payload(%{"id" => connection.item_id}), [bank, card], %{
        bank["id"] => [transaction_payload(%{"descriptionRaw" => "SALARIO RAW"})],
        card["id"] => [card_purchase, open_bill]
      })

      assert {:ok, %Connection{} = synced} = OpenFinance.sync_connection(connection)
      assert synced.status == "UPDATED"
      assert synced.bank == "bradesco"
      assert synced.last_synced_at
      assert_received {:open_finance_synced, id} when id == connection.id

      bank_account = Repo.get_by!(Account, pluggy_id: bank["id"])
      assert Decimal.equal?(bank_account.balance, "36471.90")
      assert Decimal.equal?(bank_account.automatically_invested_balance, "3647.19")

      card_account = Repo.get_by!(Account, pluggy_id: card["id"])
      assert Decimal.equal?(card_account.credit_limit, 3000)
      assert card_account.balance_due_date == ~D[2026-10-15]

      [salary, netflix, padaria] =
        Enum.sort_by(of_transactions(user), & &1.description)
        |> then(fn txns ->
          [
            Enum.find(txns, &(&1.description =~ "SALARIO")),
            Enum.find(txns, &(&1.description == "NETFLIX.COM")),
            Enum.find(txns, &(&1.description == "PADARIA"))
          ]
        end)

      # Extrato virtual do Bradesco: entrada positiva, data em Brasília, categoria
      # do Grana (Salário) e a descrição bruta da Pluggy como original.
      assert salary.bank_statement.bank == "bradesco"
      assert salary.bank_statement.statement_type == "extrato"
      assert salary.bank_statement.open_finance_account_id == bank_account.id
      assert salary.date == ~D[2026-10-05]
      assert salary.type == "credit"
      assert Decimal.equal?(salary.amount, 8500)
      assert salary.original_description == "SALARIO RAW"
      assert salary.external_id

      # Fatura virtual por fatura da Pluggy; débito negativo como nos uploads.
      assert netflix.bank_statement.statement_type == "fatura"
      assert netflix.bank_statement.external_id == "#{card["id"]}:bill-1"
      assert netflix.date == ~D[2026-09-30]
      assert netflix.type == "debit"
      assert Decimal.equal?(netflix.amount, "-55.90")
      assert netflix.installment_current == 2
      assert netflix.installment_total == 6
      assert netflix.installment_group_id
      # Sem regra do Grana, vale a categoria da Pluggy (Serviços digitais → Assinaturas).
      assert netflix.category.name == "Assinaturas"

      assert padaria.bank_statement.external_id == "#{card["id"]}:aberta"
    end

    test "uploads win: covered periods and boundary matches stay out", %{
      connection: connection,
      user: user
    } do
      bank = bradesco_account()
      upload = statement_fixture(user, %{bank: "bradesco", statement_type: "extrato"})

      Repo.update!(
        Ecto.Changeset.change(upload, period_start: ~D[2026-09-01], period_end: ~D[2026-09-30])
      )

      # Mesma compra no upload com data de lançamento diferente (fora do período).
      transaction_fixture(user, %{
        bank_statement_id: upload.id,
        date: ~D[2026-09-30],
        amount: "-42.00"
      })

      stub_pluggy(item_payload(), [bank], %{
        bank["id"] => [
          transaction_payload(%{"description" => "DENTRO", "date" => "2026-09-15T12:00:00Z"}),
          transaction_payload(%{
            "description" => "MESMA COMPRA",
            "type" => "DEBIT",
            "amount" => 42,
            "date" => "2026-10-02T12:00:00Z"
          }),
          transaction_payload(%{"description" => "DEPOIS", "date" => "2026-10-03T12:00:00Z"})
        ]
      })

      assert {:ok, _} = OpenFinance.sync_connection(connection)

      assert ["DEPOIS"] = Enum.map(of_transactions(user), & &1.description)
    end

    test "a later sync keeps manual categories and drops what is gone or now covered", %{
      connection: connection,
      user: user
    } do
      bank = bradesco_account()
      kept = transaction_payload(%{"description" => "ANTES", "date" => "2026-10-02T12:00:00Z"})
      gone = transaction_payload(%{"description" => "SOME", "date" => "2026-10-03T12:00:00Z"})

      stub_pluggy(item_payload(), [bank], %{bank["id"] => [kept, gone]})
      assert {:ok, _} = OpenFinance.sync_connection(connection)

      manual = category_fixture(user, %{name: "Manual"})
      [kept_row, _] = of_transactions(user)
      Repo.update!(Ecto.Changeset.change(kept_row, category_id: manual.id))

      stub_pluggy(item_payload(), [bank], %{
        bank["id"] => [Map.put(kept, "description", "DEPOIS")]
      })

      assert {:ok, _} = OpenFinance.sync_connection(connection)

      assert [%BankingTransaction{description: "DEPOIS", category_id: category_id}] =
               of_transactions(user)

      assert category_id == manual.id
    end

    test "virtual statements disappear when nothing is left in them", %{
      connection: connection,
      user: user
    } do
      bank = bradesco_account()
      stub_pluggy(item_payload(), [bank], %{bank["id"] => [transaction_payload()]})
      assert {:ok, _} = OpenFinance.sync_connection(connection)

      assert Repo.aggregate(from(s in BankStatement, where: s.source == "open_finance"), :count) ==
               1

      stub_pluggy(item_payload(), [bank], %{bank["id"] => []})
      assert {:ok, _} = OpenFinance.sync_connection(connection)

      assert Repo.aggregate(from(s in BankStatement, where: s.source == "open_finance"), :count) ==
               0

      assert of_transactions(user) == []
    end

    test "reads PF/PJ from the identity once", %{connection: connection} do
      stub_pluggy(item_payload(), [bank_account_payload()], %{})

      for {identity, holder} <- [
            {%{"documentType" => "CNPJ"}, "PJ"},
            {%{"documentType" => "CPF", "companyName" => "MINHA EMPRESA ME"}, "PJ"},
            {%{"documentType" => "CPF", "fullName" => "Fulano"}, "PF"},
            {nil, nil}
          ] do
        Repo.update_all(Connection, set: [holder_type: nil])

        stub(Pluggy, :get_identity, fn _, _ ->
          if identity, do: {:ok, identity}, else: {:error, :not_found}
        end)

        assert {:ok, %Connection{holder_type: ^holder}} =
                 OpenFinance.sync_connection(Repo.get!(Connection, connection.id))
      end

      # Já conhecido: não consulta de novo.
      Repo.update_all(Connection, set: [holder_type: "PJ"])
      reject(Pluggy, :get_identity, 2)

      assert {:ok, %Connection{holder_type: "PJ"}} =
               OpenFinance.sync_connection(Repo.get!(Connection, connection.id))
    end

    test "infers the bank from the account names", %{connection: connection} do
      for {name, bank} <- [
            {"Nu Pagamentos S.A. - Instituição de Pagamento", "nubank"},
            {"Banco Inter S.A.", "inter"},
            {"Itaú Unibanco", "itau"}
          ] do
        stub_pluggy(item_payload(), [bank_account_payload(%{"name" => name})], %{})

        assert {:ok, %Connection{bank: ^bank}} = OpenFinance.sync_connection(connection)
      end
    end

    test "records the error and keeps the data when Pluggy fails", %{connection: connection} do
      account = account_fixture(connection)
      stub(Pluggy, :get_item, fn _, _ -> {:ok, item_payload()} end)
      stub(Pluggy, :list_accounts, fn _, _ -> {:ok, [bank_account_payload()]} end)
      stub(Pluggy, :list_transactions, fn _, _ -> {:error, :rate_limited} end)

      assert OpenFinance.sync_connection(connection) == {:error, :rate_limited}

      failed = Repo.get!(Connection, connection.id)
      assert failed.sync_error =~ "Limite de requisições"
      # A tentativa conta para o cache de 1h: não fica relendo a cada tela aberta.
      assert failed.last_synced_at
      assert Repo.get!(Account, account.id)
      assert_received {:open_finance_synced, _}
    end

    test "records when the user has no credentials anymore", %{user: user, connection: connection} do
      OpenFinance.remove_credentials(Scope.for_user(user))

      assert OpenFinance.sync_connection(connection) == {:error, :not_configured}
      assert Repo.get!(Connection, connection.id).sync_error =~ "não configurada"
    end

    test "sync/1 ignores connections removed in the meantime" do
      assert OpenFinance.sync(-1) == {:ok, :removed}
    end

    test "sync/1 syncs by id", %{connection: connection} do
      stub(Pluggy, :get_item, fn _, _ -> {:error, :not_found} end)

      assert OpenFinance.sync(connection.id) == {:error, :not_found}
      assert Repo.get!(Connection, connection.id).sync_error =~ "não encontrado"
    end
  end

  describe "release_period/5" do
    test "removes Open Finance rows of the same bank and type inside the period", %{user: user} do
      account = account_fixture(connection_fixture(user))
      extrato = open_finance_statement_fixture(account)

      fatura =
        open_finance_statement_fixture(account, %{
          statement_type: "fatura",
          external_id: "#{account.pluggy_id}:bill"
        })

      inside = transaction_fixture(user, %{bank_statement_id: extrato.id, date: ~D[2026-10-05]})
      outside = transaction_fixture(user, %{bank_statement_id: extrato.id, date: ~D[2026-10-09]})

      other_type =
        transaction_fixture(user, %{bank_statement_id: fatura.id, date: ~D[2026-10-05]})

      OpenFinance.release_period(user.id, "nubank", "extrato", ~D[2026-10-01], ~D[2026-10-08])

      refute Repo.get(BankingTransaction, inside.id)
      assert Repo.get(BankingTransaction, outside.id)
      assert Repo.get(BankingTransaction, other_type.id)
    end
  end

  describe "delete_connection/2" do
    test "deletes the item on Pluggy and everything it brought", %{scope: scope, user: user} do
      connection = connection_fixture(user)
      account = account_fixture(connection)
      statement = open_finance_statement_fixture(account)
      transaction_fixture(user, %{bank_statement_id: statement.id})
      item_id = connection.item_id
      expect(Pluggy, :delete_item, fn @creds, ^item_id -> :ok end)

      assert {:ok, _} = OpenFinance.delete_connection(scope, connection)

      assert Repo.aggregate(Connection, :count) == 0
      assert Repo.aggregate(Account, :count) == 0
      refute Repo.get(BankStatement, statement.id)
      assert Repo.aggregate(BankingTransaction, :count) == 0
    end

    test "deletes locally when the item no longer exists on Pluggy", %{scope: scope, user: user} do
      connection = connection_fixture(user)
      stub(Pluggy, :delete_item, fn _, _ -> {:error, :not_found} end)

      assert {:ok, _} = OpenFinance.delete_connection(scope, connection)
    end

    test "keeps the connection when Pluggy fails", %{scope: scope, user: user} do
      connection = connection_fixture(user)
      stub(Pluggy, :delete_item, fn _, _ -> {:error, {:transport, "timeout"}} end)

      assert OpenFinance.delete_connection(scope, connection) == {:error, {:transport, "timeout"}}
      assert Repo.get(Connection, connection.id)
    end
  end

  describe "current state" do
    test "lists the scope's accounts, totals and where Open Finance is the source", %{
      scope: scope,
      user: user
    } do
      connection = connection_fixture(user)
      account = account_fixture(connection, %{balance: Decimal.new("100.50")})

      account_fixture(connection, %{
        type: "CREDIT",
        subtype: "CREDIT_CARD",
        balance: Decimal.new("40"),
        available_credit_limit: Decimal.new("960")
      })

      today = Date.utc_today()
      last_month = today |> Date.beginning_of_month() |> Date.shift(month: -1)
      statement = open_finance_statement_fixture(account)
      transaction_fixture(user, %{bank_statement_id: statement.id, date: today})

      # Mês passado: fatura importada; nada do Open Finance.
      transaction_fixture(user, %{
        bank_statement_id: statement_fixture(user, %{statement_type: "fatura"}).id,
        date: last_month
      })

      assert [%Account{connection: %Connection{}}, _] = OpenFinance.list_accounts(scope)
      assert OpenFinance.list_accounts(user_scope_fixture()) == []

      totals = scope |> OpenFinance.list_accounts() |> OpenFinance.totals()
      assert Decimal.equal?(totals.bank, "100.50")
      assert Decimal.equal?(totals.card_used, 40)
      assert Decimal.equal?(totals.card_available, 960)
      assert totals.bank_count == 1
      assert totals.card_count == 1

      # Últimos 12 meses, em linhas por ano como o calendário de uploads.
      rows = OpenFinance.coverage_calendar(scope)
      cells = Enum.flat_map(rows, & &1.cells)
      assert Enum.all?(rows, &(length(&1.cells) == 12))
      assert List.last(rows).year == today.year

      current = Enum.find(cells, &(&1.year == today.year and &1.month == today.month))
      assert current.open_finance == [{"nubank", "extrato"}]
      assert current.upload_types == []
      refute current.future?

      previous = Enum.find(cells, &(&1.year == last_month.year and &1.month == last_month.month))
      assert previous.upload_types == ["fatura"]
      assert previous.open_finance == []

      other_cells =
        user_scope_fixture() |> OpenFinance.coverage_calendar() |> Enum.flat_map(& &1.cells)

      assert Enum.all?(other_cells, &(&1.open_finance == [] and &1.upload_types == []))
      assert OpenFinance.last_refreshed_at(scope) == connection.last_synced_at
    end
  end

  describe "refreshing" do
    test "refresh_if_stale/1 only rereads connections older than 1 hour", %{
      scope: scope,
      user: user
    } do
      fresh = connection_fixture(user)
      stale = connection_fixture(user, %{last_synced_at: ~U[2026-01-01 00:00:00Z]})
      never = connection_fixture(user, %{last_synced_at: nil})

      OpenFinance.refresh_if_stale(scope)

      refute_enqueued(worker: OpenFinanceSyncWorker, args: %{"connection_id" => fresh.id})
      assert_enqueued(worker: OpenFinanceSyncWorker, args: %{"connection_id" => stale.id})
      assert_enqueued(worker: OpenFinanceSyncWorker, args: %{"connection_id" => never.id})
    end

    test "uploads_changed/1 and enqueue_user_syncs/1 reread every connection of the user", %{
      scope: scope,
      user: user
    } do
      mine = connection_fixture(user)
      other = connection_fixture(user_fixture())

      OpenFinance.uploads_changed(user.id)
      assert_enqueued(worker: OpenFinanceSyncWorker, args: %{"connection_id" => mine.id})
      refute_enqueued(worker: OpenFinanceSyncWorker, args: %{"connection_id" => other.id})

      OpenFinance.enqueue_user_syncs(scope)
      refute_enqueued(worker: OpenFinanceSyncWorker, args: %{"connection_id" => other.id})
    end
  end

  describe "webhook_user/1" do
    test "finds the owner of a webhook secret", %{user: user} do
      user = with_pluggy_credentials(user, %{pluggy_webhook_secret: "secret-a"})
      with_pluggy_credentials(user_fixture(), %{pluggy_webhook_secret: "secret-b"})

      assert OpenFinance.webhook_user("secret-a").id == user.id
      assert OpenFinance.webhook_user("wrong") == nil
    end
  end

  describe "handle_webhook/2" do
    test "schedules a sync for the user's item, ignoring the payload data", %{
      scope: scope,
      user: user
    } do
      connection = connection_fixture(user)

      OpenFinance.handle_webhook(scope, %{
        "event" => "transactions/created",
        "itemId" => connection.item_id,
        "accountId" => "whatever"
      })

      assert_enqueued(worker: OpenFinanceSyncWorker, args: %{"connection_id" => connection.id})
    end

    test "registers items created by this user's widget", %{scope: scope, user: user} do
      item_id = Ecto.UUID.generate()

      OpenFinance.handle_webhook(scope, %{
        "event" => "item/created",
        "itemId" => item_id,
        "clientUserId" => to_string(user.id)
      })

      assert_enqueued(
        worker: OpenFinanceSyncWorker,
        args: %{"user_id" => user.id, "item_id" => item_id}
      )
    end

    test "ignores other users' items and events without item", %{scope: scope} do
      other_connection = connection_fixture(user_fixture())
      item_id = Ecto.UUID.generate()

      assert OpenFinance.handle_webhook(scope, %{
               "event" => "item/updated",
               "itemId" => other_connection.item_id
             }) == :ignored

      assert OpenFinance.handle_webhook(scope, %{
               "event" => "item/created",
               "itemId" => item_id,
               "clientUserId" => "999999"
             }) == :ignored

      assert OpenFinance.handle_webhook(scope, %{"event" => "item/created", "itemId" => item_id}) ==
               :ignored

      assert OpenFinance.handle_webhook(scope, %{"event" => "connector/status_updated"}) ==
               :ignored

      refute_enqueued(worker: OpenFinanceSyncWorker)
    end
  end

  describe "ensure_webhook/1" do
    setup :with_webhook_url

    defp ours(secret) do
      %{
        "id" => "ours",
        "url" => @webhook_url,
        "event" => "all",
        "headers" => %{"x-grana-webhook-secret" => secret}
      }
    end

    test "does nothing without PLUGGY_WEBHOOK_URL", %{scope: scope} do
      put_pluggy_env([])
      reject(Pluggy, :list_webhooks, 1)

      assert OpenFinance.ensure_webhook(scope) == :ok
    end

    test "needs credentials" do
      assert OpenFinance.ensure_webhook(user_scope_fixture()) == {:error, :not_configured}
    end

    test "keeps a webhook that already carries the user's secret", %{user: user} do
      user = with_pluggy_credentials(user, %{pluggy_webhook_secret: "atual"})
      stub(Pluggy, :list_webhooks, fn @creds -> {:ok, [ours("atual")]} end)
      reject(Pluggy, :create_webhook, 4)

      assert OpenFinance.ensure_webhook(Scope.for_user(user)) == :ok
    end

    test "registers the webhook, replacing stale ones on the same URL", %{user: user} do
      user = with_pluggy_credentials(user, %{pluggy_webhook_secret: "antigo"})
      test_pid = self()

      stub(Pluggy, :list_webhooks, fn @creds ->
        {:ok,
         [
           ours("outro-segredo"),
           %{"id" => "manual", "url" => "https://grana.example.com/webhooks", "headers" => %{}}
         ]}
      end)

      stub(Pluggy, :delete_webhook, fn @creds, id ->
        send(test_pid, {:deleted, id})
        :ok
      end)

      expect(Pluggy, :create_webhook, fn @creds, @webhook_url, "all", headers ->
        send(test_pid, {:headers, headers})
        {:ok, %{"id" => "new"}}
      end)

      assert OpenFinance.ensure_webhook(Scope.for_user(user)) == :ok

      assert_received {:deleted, "ours"}
      refute_received {:deleted, "manual"}
      assert_received {:headers, %{"x-grana-webhook-secret" => secret}}
      assert byte_size(secret) >= 32
      assert Repo.get!(User, user.id).pluggy_webhook_secret == secret
      assert OpenFinance.webhook_user(secret).id == user.id
    end

    test "registers when the user has no secret yet", %{scope: scope} do
      stub(Pluggy, :list_webhooks, fn _ -> {:ok, [ours("qualquer")]} end)
      stub(Pluggy, :delete_webhook, fn _, _ -> :ok end)
      expect(Pluggy, :create_webhook, fn _, _, _, _ -> {:ok, %{"id" => "new"}} end)

      assert OpenFinance.ensure_webhook(scope) == :ok
    end

    test "reports Pluggy failures", %{scope: scope} do
      stub(Pluggy, :list_webhooks, fn _ -> {:error, :rate_limited} end)
      assert OpenFinance.ensure_webhook(scope) == {:error, :rate_limited}

      stub(Pluggy, :list_webhooks, fn _ -> {:ok, [%{"id" => "stale", "url" => @webhook_url}]} end)
      stub(Pluggy, :delete_webhook, fn _, _ -> {:error, :rate_limited} end)
      reject(Pluggy, :create_webhook, 4)

      assert OpenFinance.ensure_webhook(scope) == {:error, :rate_limited}
    end

    test "sync/1 ensures the webhook and syncs even when that fails", %{user: user} do
      connection = connection_fixture(user)
      stub(Pluggy, :list_webhooks, fn _ -> {:error, :rate_limited} end)
      stub(Pluggy, :get_identity, fn _, _ -> {:ok, %{"documentType" => "CPF"}} end)
      stub(Pluggy, :get_item, fn _, _ -> {:ok, item_payload()} end)
      stub(Pluggy, :list_accounts, fn _, _ -> {:ok, []} end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:ok, %Connection{}} = OpenFinance.sync(connection.id)
        end)

      assert log =~ "webhook não garantido"
    end
  end

  test "create_connect_token/1 identifies the user", %{scope: scope, user: user} do
    user_id = to_string(user.id)
    expect(Pluggy, :create_connect_token, fn @creds, ^user_id -> {:ok, "ct"} end)

    assert OpenFinance.create_connect_token(scope) == {:ok, "ct"}
    assert OpenFinance.create_connect_token(user_scope_fixture()) == {:error, :not_configured}
  end

  test "error_message/1 covers every reason" do
    for reason <- [
          :not_configured,
          :invalid_credentials,
          :unauthorized,
          :not_found,
          :invalid_item_id,
          :already_connected,
          :rate_limited,
          {:http_error, 500, nil},
          {:http_error, 400, "bad"},
          {:transport, "timeout"}
        ] do
      assert is_binary(OpenFinance.error_message(reason))
    end

    assert OpenFinance.error_message({:http_error, 400, "bad"}) =~ "bad"
  end
end
