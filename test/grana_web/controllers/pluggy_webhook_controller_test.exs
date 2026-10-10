defmodule GranaWeb.PluggyWebhookControllerTest do
  use GranaWeb.ConnCase, async: false

  use Oban.Testing, repo: Grana.Repo, engine: Oban.Engines.Lite

  import Grana.AccountsFixtures
  import Grana.OpenFinanceFixtures

  alias Grana.Workers.OpenFinanceSyncWorker

  @secret "s3cret-do-webhook"

  defp post_webhook(conn, payload, secret) do
    conn =
      if secret,
        do: put_req_header(conn, "x-grana-webhook-secret", secret),
        else: conn

    conn
    |> put_req_header("content-type", "application/json")
    |> post(~p"/webhooks/pluggy", Jason.encode!(payload))
  end

  test "behaves as missing while PLUGGY_WEBHOOK_URL is not set", %{conn: conn} do
    with_pluggy_credentials(user_fixture(), %{pluggy_webhook_secret: @secret})

    assert conn |> post_webhook(%{"event" => "item/updated"}, @secret) |> response(404)
  end

  describe "with the webhook enabled" do
    setup do
      original = Application.get_env(:grana, :pluggy)
      on_exit(fn -> Application.put_env(:grana, :pluggy, original || []) end)

      Application.put_env(:grana, :pluggy,
        webhook_url: "https://grana.example.com/webhooks/pluggy"
      )

      user = with_pluggy_credentials(user_fixture(), %{pluggy_webhook_secret: @secret})
      %{connection: connection_fixture(user)}
    end

    test "rejects calls without or with a wrong secret", %{conn: conn, connection: connection} do
      payload = %{"event" => "item/updated", "itemId" => connection.item_id}

      assert conn |> post_webhook(payload, nil) |> response(401)
      assert build_conn() |> post_webhook(payload, "wrong") |> response(401)
      refute_enqueued(worker: OpenFinanceSyncWorker)
    end

    test "accepts the owner's events and schedules a sync", %{
      conn: conn,
      connection: connection
    } do
      payload = %{
        "event" => "item/updated",
        "eventId" => Ecto.UUID.generate(),
        "itemId" => connection.item_id,
        "triggeredBy" => "SYNC"
      }

      assert conn |> post_webhook(payload, @secret) |> response(200)
      assert_enqueued(worker: OpenFinanceSyncWorker, args: %{"connection_id" => connection.id})
    end

    test "another user's secret cannot touch this connection", %{
      conn: conn,
      connection: connection
    } do
      with_pluggy_credentials(user_fixture(), %{pluggy_webhook_secret: "outro-segredo"})
      payload = %{"event" => "item/updated", "itemId" => connection.item_id}

      assert conn |> post_webhook(payload, "outro-segredo") |> response(200)
      refute_enqueued(worker: OpenFinanceSyncWorker)
    end

    test "acknowledges events it does not care about", %{conn: conn} do
      payload = %{"event" => "connector/status_updated", "connectorId" => "201"}

      assert conn |> post_webhook(payload, @secret) |> response(200)
    end
  end
end
