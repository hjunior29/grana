defmodule Grana.OpenFinance.PluggyTest do
  use ExUnit.Case, async: false

  use Mimic

  alias Grana.OpenFinance.Pluggy

  @api "https://api.pluggy.ai"

  # A API key fica em cache por par de credenciais: credenciais únicas por teste
  # garantem que cada um começa sem chave em cache.
  setup do
    %{creds: %{client_id: "client-#{System.unique_integer([:positive])}", client_secret: "s"}}
  end

  defp ok(body, status \\ 200), do: {:ok, %Req.Response{status: status, body: body}}

  # Responde o /auth com uma chave e delega o resto para `fun`, avisando o processo de teste.
  defp stub_api(fun) do
    test_pid = self()

    stub(Req, :request, fn opts ->
      send(test_pid, {:req, opts[:method], opts[:url], opts})

      case {opts[:method], opts[:url]} do
        {:post, @api <> "/auth"} -> ok(%{"apiKey" => "api-key-1"})
        {method, url} -> fun.(method, url, opts)
      end
    end)
  end

  describe "environment settings" do
    setup do
      original = Application.get_env(:grana, :pluggy)
      on_exit(fn -> Application.put_env(:grana, :pluggy, original || []) end)
    end

    test "env_credentials/0 reads PLUGGY_CLIENT_ID/SECRET, ignoring blanks" do
      assert Pluggy.env_credentials() == nil

      Application.put_env(:grana, :pluggy, client_id: "id", client_secret: "")
      assert Pluggy.env_credentials() == nil

      Application.put_env(:grana, :pluggy, client_id: "id", client_secret: "secret")
      assert Pluggy.env_credentials() == %{client_id: "id", client_secret: "secret"}
    end

    test "webhook_url/0" do
      assert Pluggy.webhook_url() == nil

      Application.put_env(:grana, :pluggy,
        webhook_url: "https://grana.example.com/webhooks/pluggy"
      )

      assert Pluggy.webhook_url() == "https://grana.example.com/webhooks/pluggy"
    end
  end

  describe "authentication" do
    test "exchanges client credentials for an API key and reuses it", %{creds: creds} do
      item = %{"id" => "item-1", "status" => "UPDATED"}
      stub_api(fn :get, @api <> "/items/item-1", _opts -> ok(item) end)

      assert {:ok, ^item} = Pluggy.get_item(creds, "item-1")
      assert {:ok, ^item} = Pluggy.get_item(creds, "item-1")

      assert_received {:req, :post, @api <> "/auth", auth_opts}
      assert auth_opts[:json] == %{clientId: creds.client_id, clientSecret: "s"}
      refute_received {:req, :post, @api <> "/auth", _}

      assert_received {:req, :get, _, opts}
      assert {"x-api-key", "api-key-1"} in opts[:headers]
    end

    test "a new secret for the same client id authenticates again", %{creds: creds} do
      stub_api(fn :get, _url, _opts -> ok(%{}) end)

      assert {:ok, _} = Pluggy.get_item(creds, "item-1")
      assert {:ok, _} = Pluggy.get_item(%{creds | client_secret: "rotated"}, "item-1")

      assert_received {:req, :post, @api <> "/auth", first}
      assert_received {:req, :post, @api <> "/auth", second}
      assert [first[:json].clientSecret, second[:json].clientSecret] == ["s", "rotated"]
    end

    test "verify_credentials/1", %{creds: creds} do
      stub(Req, :request, fn opts ->
        case opts[:json] do
          %{clientSecret: "s"} -> ok(%{"apiKey" => "k"})
          _ -> ok(%{"codeDescription" => "CLIENT_KEYS_UNAUTHORIZED"}, 401)
        end
      end)

      assert Pluggy.verify_credentials(creds) == :ok

      assert Pluggy.verify_credentials(%{creds | client_secret: "wrong"}) ==
               {:error, :invalid_credentials}
    end

    test "invalid client credentials", %{creds: creds} do
      stub(Req, :request, fn _opts ->
        ok(%{"codeDescription" => "CLIENT_KEYS_UNAUTHORIZED"}, 401)
      end)

      assert Pluggy.get_item(creds, "item-1") == {:error, :invalid_credentials}
    end

    test "renews the API key once when Pluggy rejects it", %{creds: creds} do
      {:ok, attempts} = Agent.start_link(fn -> 0 end)

      stub_api(fn :get, _url, _opts ->
        case Agent.get_and_update(attempts, &{&1, &1 + 1}) do
          0 -> ok(%{"codeDescription" => "API_KEY_MISSING_OR_INVALID"}, 403)
          _ -> ok(%{"id" => "item-1"})
        end
      end)

      assert {:ok, %{"id" => "item-1"}} = Pluggy.get_item(creds, "item-1")
      assert_received {:req, :post, @api <> "/auth", _}
      assert_received {:req, :post, @api <> "/auth", _}
    end

    test "propagates errors from the auth endpoint", %{creds: creds} do
      stub(Req, :request, fn _opts -> ok(%{"message" => "boom"}, 500) end)

      assert Pluggy.get_item(creds, "item-1") == {:error, {:http_error, 500, "boom"}}
    end
  end

  describe "error mapping" do
    test "404, 429, other statuses and transport errors", %{creds: creds} do
      stub_api(fn :get, @api <> "/items/" <> id, _opts ->
        case id do
          "missing" -> ok(%{"codeDescription" => "ITEM_NOT_FOUND"}, 404)
          "limited" -> ok(%{}, 429)
          "broken" -> ok("Bad Gateway", 502)
          "offline" -> {:error, %Req.TransportError{reason: :econnrefused}}
        end
      end)

      assert Pluggy.get_item(creds, "missing") == {:error, :not_found}
      assert Pluggy.get_item(creds, "limited") == {:error, :rate_limited}
      assert Pluggy.get_item(creds, "broken") == {:error, {:http_error, 502, nil}}
      assert {:error, {:transport, message}} = Pluggy.get_item(creds, "offline")
      assert message =~ "connection refused"
    end
  end

  describe "endpoints" do
    test "create_connect_token/2 sends clientUserId inside options", %{creds: creds} do
      stub_api(fn :post, @api <> "/connect_token", _opts -> ok(%{"accessToken" => "ct-1"}) end)

      assert Pluggy.create_connect_token(creds, "42") == {:ok, "ct-1"}

      assert_received {:req, :post, @api <> "/connect_token", opts}
      assert opts[:json] == %{options: %{clientUserId: "42"}}
    end

    test "list_accounts/2 filters by item", %{creds: creds} do
      stub_api(fn :get, @api <> "/accounts", opts ->
        assert opts[:params] == [itemId: "item-1"]
        ok(%{"results" => [%{"id" => "acc-1"}], "total" => 1})
      end)

      assert Pluggy.list_accounts(creds, "item-1") == {:ok, [%{"id" => "acc-1"}]}
    end

    test "list_transactions/2 follows the v2 cursor until next is null", %{creds: creds} do
      stub_api(fn :get, url, _opts ->
        case url do
          @api <> "/v2/transactions?accountId=acc-1" ->
            ok(%{
              "results" => [%{"id" => "t1"}, %{"id" => "t2"}],
              "next" => "?accountId=acc-1&after=c1"
            })

          @api <> "/v2/transactions?accountId=acc-1&after=c1" ->
            ok(%{"results" => [%{"id" => "t3"}], "next" => nil})
        end
      end)

      assert {:ok, transactions} = Pluggy.list_transactions(creds, "acc-1")
      assert Enum.map(transactions, & &1["id"]) == ["t1", "t2", "t3"]
    end

    test "list_transactions/2 stops on error", %{creds: creds} do
      stub_api(fn :get, @api <> "/v2/transactions" <> _, _opts -> ok(%{}, 429) end)

      assert Pluggy.list_transactions(creds, "acc-1") == {:error, :rate_limited}
    end

    test "delete_item/2", %{creds: creds} do
      stub_api(fn :delete, @api <> "/items/item-1", _opts -> ok(%{"count" => 1}) end)

      assert Pluggy.delete_item(creds, "item-1") == :ok
    end

    test "webhooks CRUD", %{creds: creds} do
      stub_api(fn
        :get, @api <> "/webhooks", _opts ->
          ok(%{"results" => [%{"id" => "wh-1"}]})

        :post, @api <> "/webhooks", opts ->
          assert opts[:json] == %{
                   url: "https://example.com/hook",
                   event: "all",
                   headers: %{"x-secret" => "s"}
                 }

          ok(%{"id" => "wh-2"}, 201)

        :delete, @api <> "/webhooks/wh-1", _opts ->
          ok(%{})
      end)

      assert Pluggy.list_webhooks(creds) == {:ok, [%{"id" => "wh-1"}]}

      assert Pluggy.create_webhook(creds, "https://example.com/hook", "all", %{"x-secret" => "s"}) ==
               {:ok, %{"id" => "wh-2"}}

      assert Pluggy.delete_webhook(creds, "wh-1") == :ok
    end
  end

  test "exposes the MeuPluggy connector id" do
    assert Pluggy.meu_pluggy_connector_id() == 200
  end
end
