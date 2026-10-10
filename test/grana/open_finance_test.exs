defmodule Grana.OpenFinanceTest do
  use Grana.DataCase, async: false

  use Mimic
  use Oban.Testing, repo: Grana.Repo, engine: Oban.Engines.Lite

  import Grana.AccountsFixtures
  import Grana.OpenFinanceFixtures

  alias Grana.Accounts.{Scope, User}
  alias Grana.OpenFinance
  alias Grana.OpenFinance.{Account, Connection, Pluggy, Transaction}
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
      stub(Pluggy, :get_item, fn @creds, _ -> {:ok, item} end)
      stub(Pluggy, :list_accounts, fn @creds, _ -> {:ok, accounts} end)

      stub(Pluggy, :list_transactions, fn @creds, id ->
        {:ok, Map.get(transactions_by_account, id, [])}
      end)
    end

    test "mirrors accounts and transactions", %{connection: connection} do
      bank = bank_account_payload()
      card = card_account_payload()

      card_purchase =
        transaction_payload(%{
          "description" => "NETFLIX.COM",
          "amount" => 55.9,
          "type" => "DEBIT",
          "status" => "PENDING",
          "date" => "2026-10-01T02:30:00.000Z",
          "creditCardMetadata" => %{
            "installmentNumber" => 2.0,
            "totalInstallments" => 6,
            "billId" => "bill-1"
          },
          "providerId" => "of-123"
        })

      stub_pluggy(item_payload(%{"id" => connection.item_id}), [bank, card], %{
        bank["id"] => [transaction_payload()],
        card["id"] => [card_purchase]
      })

      assert {:ok, %Connection{} = synced} = OpenFinance.sync_connection(connection)
      assert synced.status == "UPDATED"
      assert synced.sync_error == nil
      assert synced.last_synced_at
      assert_received {:open_finance_synced, id} when id == connection.id

      bank_account = Repo.get_by!(Account, pluggy_id: bank["id"])
      assert Decimal.equal?(bank_account.balance, "36471.90")
      assert Decimal.equal?(bank_account.automatically_invested_balance, "3647.19")
      assert bank_account.transfer_number == "123/0001/12345-0"

      card_account = Repo.get_by!(Account, pluggy_id: card["id"])
      assert Decimal.equal?(card_account.credit_limit, 3000)
      assert Decimal.equal?(card_account.available_credit_limit, 2000)
      assert card_account.balance_close_date == ~D[2026-10-10]
      assert card_account.balance_due_date == ~D[2026-10-15]
      assert card_account.brand == "MASTERCARD"

      salary = Repo.get_by!(Transaction, account_id: bank_account.id)
      # 03:00Z é meia-noite em Brasília: continua dia 05.
      assert salary.date == ~D[2026-10-05]
      assert Decimal.equal?(salary.amount, 8500)
      assert salary.type == "CREDIT"

      netflix = Repo.get_by!(Transaction, account_id: card_account.id)
      # 02:30Z ainda é dia 30/09 em Brasília.
      assert netflix.date == ~D[2026-09-30]
      assert Decimal.equal?(netflix.amount, "55.90")
      assert netflix.status == "PENDING"
      assert netflix.installment_number == 2
      assert netflix.total_installments == 6
      assert netflix.bill_id == "bill-1"
      assert netflix.provider_id == "of-123"
    end

    test "a later sync updates what changed and drops what disappeared on Pluggy",
         %{connection: connection} do
      bank = bank_account_payload()
      card = card_account_payload()
      kept = transaction_payload(%{"description" => "ANTES"})
      gone = transaction_payload()

      stub_pluggy(item_payload(), [bank, card], %{bank["id"] => [kept, gone]})
      assert {:ok, _} = OpenFinance.sync_connection(connection)
      assert Repo.aggregate(Transaction, :count) == 2

      # O espelho apaga o que tem synced_at anterior ao da nova sincronização.
      Repo.update_all(Account, set: [synced_at: ~U[2026-01-01 00:00:00Z]])
      Repo.update_all(Transaction, set: [synced_at: ~U[2026-01-01 00:00:00Z]])

      stub_pluggy(item_payload(), [Map.put(bank, "balance", 10)], %{
        bank["id"] => [Map.put(kept, "description", "DEPOIS")]
      })

      assert {:ok, _} = OpenFinance.sync_connection(connection)

      assert [%Account{pluggy_id: pluggy_id, balance: balance}] = Repo.all(Account)
      assert pluggy_id == bank["id"]
      assert Decimal.equal?(balance, 10)
      assert [%Transaction{description: "DEPOIS"}] = Repo.all(Transaction)
    end

    test "records the error and keeps the data when Pluggy fails", %{connection: connection} do
      account = account_fixture(connection)
      stub(Pluggy, :get_item, fn _, _ -> {:ok, item_payload()} end)
      stub(Pluggy, :list_accounts, fn _, _ -> {:ok, [bank_account_payload()]} end)
      stub(Pluggy, :list_transactions, fn _, _ -> {:error, :rate_limited} end)

      assert OpenFinance.sync_connection(connection) == {:error, :rate_limited}

      assert Repo.get!(Connection, connection.id).sync_error =~ "Limite de requisições"
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

  describe "delete_connection/2" do
    test "deletes the item on Pluggy and the local mirror", %{scope: scope, user: user} do
      connection = connection_fixture(user)
      account = account_fixture(connection)
      transaction_fixture(account)
      item_id = connection.item_id
      expect(Pluggy, :delete_item, fn @creds, ^item_id -> :ok end)

      assert {:ok, _} = OpenFinance.delete_connection(scope, connection)

      assert Repo.aggregate(Connection, :count) == 0
      assert Repo.aggregate(Account, :count) == 0
      assert Repo.aggregate(Transaction, :count) == 0
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

  describe "reading the mirror" do
    test "lists only the scope's data", %{scope: scope, user: user} do
      connection = connection_fixture(user)
      account = account_fixture(connection)
      transaction_fixture(account, %{date: ~D[2026-10-01], description: "OLD"})
      transaction_fixture(account, %{date: ~D[2026-10-09], description: "NEW"})

      other_scope = user_scope_fixture()

      assert [%Connection{accounts: [%Account{}]}] = OpenFinance.list_connections(scope)
      assert OpenFinance.list_connections(other_scope) == []

      assert [%Account{connection: %Connection{}}] = OpenFinance.list_accounts(scope)
      assert OpenFinance.list_accounts(other_scope) == []

      assert ["NEW", "OLD"] =
               scope |> OpenFinance.list_transactions(account.id) |> Enum.map(& &1.description)

      assert [%Transaction{description: "OLD"}] =
               OpenFinance.list_transactions(scope, account.id, limit: 1, offset: 1)

      assert OpenFinance.list_transactions(other_scope, account.id) == []
      assert OpenFinance.count_transactions(scope, account.id) == 2
      assert OpenFinance.count_transactions(other_scope, account.id) == 0

      assert OpenFinance.get_connection!(scope, connection.id).id == connection.id

      assert_raise Ecto.NoResultsError, fn ->
        OpenFinance.get_connection!(other_scope, connection.id)
      end
    end
  end

  describe "enqueueing syncs" do
    test "per user and for everyone", %{scope: scope, user: user} do
      mine = connection_fixture(user)
      other = connection_fixture(user_fixture())

      OpenFinance.enqueue_user_syncs(scope)
      assert_enqueued(worker: OpenFinanceSyncWorker, args: %{"connection_id" => mine.id})
      refute_enqueued(worker: OpenFinanceSyncWorker, args: %{"connection_id" => other.id})

      OpenFinance.enqueue_sync_all()
      assert_enqueued(worker: OpenFinanceSyncWorker, args: %{"connection_id" => other.id})
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
