defmodule GranaWeb.UserLive.SettingsOpenFinanceTest do
  use GranaWeb.ConnCase, async: false

  use Mimic
  use Oban.Testing, repo: Grana.Repo, engine: Oban.Engines.Lite

  import Phoenix.LiveViewTest
  import Grana.AccountsFixtures
  import Grana.OpenFinanceFixtures

  alias Grana.Accounts.User
  alias Grana.OpenFinance.{Connection, Pluggy}
  alias Grana.Repo
  alias Grana.Workers.OpenFinanceSyncWorker

  setup :register_and_log_in_user

  setup do
    # A presença de CLOAK_KEY muda a tela; cada teste decide (o .env local define uma).
    original = System.get_env("CLOAK_KEY")
    System.put_env("CLOAK_KEY", "chave-de-teste")

    on_exit(fn ->
      if original, do: System.put_env("CLOAK_KEY", original), else: System.delete_env("CLOAK_KEY")
    end)
  end

  defp put_pluggy_env(overrides) do
    original = Application.get_env(:grana, :pluggy)
    on_exit(fn -> Application.put_env(:grana, :pluggy, original || []) end)
    Application.put_env(:grana, :pluggy, overrides)
  end

  defp configured(%{user: user}), do: %{user: with_pluggy_credentials(user)}

  describe "credentials" do
    test "without credentials shows the setup steps and the form", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      assert has_element?(lv, "#open-finance-setup")
      assert has_element?(lv, "#pluggy-credentials-form")
      refute has_element?(lv, "#cloak-key-warning")
      refute has_element?(lv, "#connect-meu-pluggy")
    end

    test "asks for a CLOAK_KEY before accepting secrets", %{conn: conn} do
      System.delete_env("CLOAK_KEY")
      reject(Pluggy, :verify_credentials, 1)

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      assert has_element?(lv, "#cloak-key-warning")
      refute has_element?(lv, "#pluggy-credentials-form")

      assert render_hook(lv, "open_finance_save_credentials", %{
               "user" => %{
                 "pluggy_client_id" => Ecto.UUID.generate(),
                 "pluggy_client_secret" => "s"
               }
             }) =~ "Defina CLOAK_KEY"
    end

    test "saves verified credentials", %{conn: conn, user: user} do
      client_id = Ecto.UUID.generate()
      expect(Pluggy, :verify_credentials, fn %{client_id: ^client_id} -> :ok end)

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      html =
        lv
        |> form("#pluggy-credentials-form",
          user: %{pluggy_client_id: client_id, pluggy_client_secret: "segredo-novo"}
        )
        |> render_submit()

      assert html =~ "verificadas e salvas"
      refute html =~ "segredo-novo"
      assert has_element?(lv, "#credentials-saved", client_id)
      refute has_element?(lv, "#pluggy-credentials-form")
      assert has_element?(lv, "#connect-meu-pluggy")

      assert %User{pluggy_client_id: ^client_id, pluggy_client_secret: "segredo-novo"} =
               Repo.get!(User, user.id)
    end

    test "shows errors without echoing any secret", %{conn: conn, user: user} do
      with_pluggy_credentials(user, %{pluggy_client_secret: "segredo-salvo"})
      stub(Pluggy, :verify_credentials, fn _ -> {:error, :invalid_credentials} end)

      {:ok, lv, html} = live(conn, ~p"/users/settings")
      refute html =~ "segredo-salvo"

      lv |> element("#replace-credentials") |> render_click()

      html =
        lv
        |> form("#pluggy-credentials-form",
          user: %{pluggy_client_id: Ecto.UUID.generate(), pluggy_client_secret: "digitado"}
        )
        |> render_submit()

      assert html =~ "recusou"
      refute html =~ "digitado"
      refute html =~ "segredo-salvo"
      assert Repo.get!(User, user.id).pluggy_client_secret == "segredo-salvo"
    end

    test "requires a recent login to save or remove", %{user: user} do
      user = with_pluggy_credentials(user)
      reject(Pluggy, :verify_credentials, 1)

      conn =
        log_in_user(build_conn(), user,
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -30, :minute)
        )

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               render_hook(lv, "open_finance_save_credentials", %{
                 "user" => %{"pluggy_client_id" => Ecto.UUID.generate()}
               })

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               lv |> element("#remove-credentials") |> render_click()

      assert Repo.get!(User, user.id).pluggy_client_secret == "test-secret"
    end

    test "removes saved credentials", %{conn: conn, user: user} do
      with_pluggy_credentials(user)

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      assert lv |> element("#remove-credentials") |> render_click() =~ "removidas"
      assert has_element?(lv, "#open-finance-setup")
      assert %User{pluggy_client_secret: nil} = Repo.get!(User, user.id)
    end

    test "with .env credentials there is nothing to save in the Grana", %{
      conn: conn,
      user: user
    } do
      put_pluggy_env(client_id: "env-id", client_secret: "env-secret")
      with_pluggy_credentials(user)
      reject(Pluggy, :verify_credentials, 1)

      {:ok, lv, html} = live(conn, ~p"/users/settings")

      assert has_element?(lv, "#credentials-env")
      assert has_element?(lv, "#credentials-env-client-id[disabled][value=PLUGGY_CLIENT_ID]")
      assert has_element?(lv, "#credentials-env-client-secret[disabled]")
      assert has_element?(lv, "#connect-meu-pluggy")
      refute html =~ "env-secret"
      refute html =~ "Usando"
      refute html =~ "env-id"
      refute has_element?(lv, "#credentials-saved")
      refute has_element?(lv, "#replace-credentials")
      refute has_element?(lv, "#pluggy-credentials-form")

      assert render_hook(lv, "open_finance_save_credentials", %{
               "user" => %{
                 "pluggy_client_id" => Ecto.UUID.generate(),
                 "pluggy_client_secret" => "s"
               }
             }) =~ "já vêm do .env"
    end
  end

  describe "configured, without connections" do
    setup :configured

    test "renders the empty state and the connect actions", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/users/settings")

      assert has_element?(lv, "#credentials-saved", pluggy_client_id())
      refute html =~ "test-secret"
      assert has_element?(lv, "#open-finance-empty")
      assert has_element?(lv, "#connect-meu-pluggy")
      assert has_element?(lv, "#pluggy-connect-widget[phx-hook=PluggyConnectWidget]")
    end

    test "opens the widget on MeuPluggy with a fresh connect token", %{conn: conn, user: user} do
      user_id = to_string(user.id)
      expect(Pluggy, :create_connect_token, fn _creds, ^user_id -> {:ok, "ct-1"} end)

      {:ok, lv, _html} = live(conn, ~p"/users/settings")
      lv |> element("#connect-meu-pluggy") |> render_click()

      assert_push_event(lv, "pluggy:open", %{connect_token: "ct-1", connector_id: 200})

      assert has_element?(lv, "#connect-meu-pluggy[disabled]")
    end

    test "shows Pluggy errors when the token cannot be created", %{conn: conn} do
      stub(Pluggy, :create_connect_token, fn _, _ -> {:error, :invalid_credentials} end)

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      assert lv |> element("#connect-meu-pluggy") |> render_click() =~
               "recusou o CLIENT_ID/CLIENT_SECRET"
    end

    test "stores the item returned by the widget after checking it on Pluggy", %{
      conn: conn,
      user: user
    } do
      item = item_payload()
      item_id = item["id"]
      expect(Pluggy, :get_item, fn _creds, ^item_id -> {:ok, item} end)

      {:ok, lv, _html} = live(conn, ~p"/users/settings")
      html = render_hook(lv, "pluggy_connected", %{"item_id" => item_id})

      assert html =~ "Conexão adicionada"
      connection = Repo.get_by!(Connection, item_id: item_id)
      assert connection.user_id == user.id
      assert has_element?(lv, "#connection-#{connection.id}")
      assert_enqueued(worker: OpenFinanceSyncWorker, args: %{"connection_id" => connection.id})
    end

    test "reports widget errors and re-enables the button on close", %{conn: conn} do
      stub(Pluggy, :create_connect_token, fn _, _ -> {:ok, "ct"} end)

      {:ok, lv, _html} = live(conn, ~p"/users/settings")
      lv |> element("#connect-meu-pluggy") |> render_click()

      assert render_hook(lv, "pluggy_error", %{"message" => "Invalid credentials"}) =~
               "Pluggy: Invalid credentials"

      assert render_hook(lv, "pluggy_error", %{}) =~ "não foi concluída"

      lv |> element("#connect-meu-pluggy") |> render_click()
      render_hook(lv, "pluggy_closed", %{})
      refute has_element?(lv, "#connect-meu-pluggy[disabled]")
    end

    test "adds a connection by itemId", %{conn: conn} do
      item = item_payload()
      stub(Pluggy, :get_item, fn _, _ -> {:ok, item} end)

      {:ok, lv, _html} = live(conn, ~p"/users/settings")
      refute has_element?(lv, "#open-finance-item-form")

      lv |> element("#toggle-item-form") |> render_click()

      assert lv
             |> form("#open-finance-item-form", open_finance: %{item_id: "nope"})
             |> render_submit() =~ "itemId inválido"

      lv
      |> form("#open-finance-item-form", open_finance: %{item_id: item["id"]})
      |> render_submit()

      assert Repo.get_by(Connection, item_id: item["id"])
      refute has_element?(lv, "#open-finance-item-form")
    end

    test "cancels the itemId form", %{conn: conn} do
      reject(Pluggy, :get_item, 2)

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      lv |> element("#toggle-item-form") |> render_click()
      assert has_element?(lv, "#open-finance-item-form")

      lv |> element("#cancel-item-form") |> render_click()
      refute has_element?(lv, "#open-finance-item-form")
    end

    test "shows the Open Finance and Pluggy logos", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      assert has_element?(lv, "#open-finance-settings svg[aria-label='Open Finance Brasil']")
      assert has_element?(lv, "#open-finance-settings .badge img[alt='Pluggy']")
    end
  end

  describe "with a connection" do
    setup :configured

    setup %{user: user} do
      connection = connection_fixture(user, %{connector_name: "Nubank"})
      account_fixture(connection, %{marketing_name: "Conta do Nubank"})
      %{connection: connection}
    end

    test "lists the connection with its accounts", %{conn: conn, connection: connection} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      assert has_element?(lv, "#connection-#{connection.id}", "Nubank")
      assert has_element?(lv, "#connection-#{connection.id}", "Conta do Nubank")
      assert has_element?(lv, "#connection-#{connection.id}", "Atualizado")
    end

    test "has no manual sync and refreshes when a read finishes", %{
      conn: conn,
      connection: connection
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      refute has_element?(lv, "#sync-connection-#{connection.id}")

      Repo.update!(Ecto.Changeset.change(connection, sync_error: "Falhou feio"))
      send(lv.pid, {:open_finance_synced, connection.id})

      assert has_element?(lv, "#connection-#{connection.id}", "Falhou feio")
    end

    test "removes the connection", %{conn: conn, connection: connection} do
      item_id = connection.item_id
      expect(Pluggy, :delete_item, fn _creds, ^item_id -> :ok end)

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      assert lv |> element("#remove-connection-#{connection.id}") |> render_click() =~
               "Conexão removida"

      refute has_element?(lv, "#connection-#{connection.id}")
      refute Repo.get(Connection, connection.id)
    end

    test "keeps the connection when Pluggy fails to delete it", %{
      conn: conn,
      connection: connection
    } do
      stub(Pluggy, :delete_item, fn _, _ -> {:error, :rate_limited} end)

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      assert lv |> element("#remove-connection-#{connection.id}") |> render_click() =~
               "Limite de requisições"

      assert has_element?(lv, "#connection-#{connection.id}")
    end

    test "says when the widget item is already linked", %{conn: conn, connection: connection} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      assert render_hook(lv, "pluggy_connected", %{"item_id" => connection.item_id}) =~
               "já está vinculada"
    end
  end

  test "users without credentials or .env see no connect actions" do
    conn = log_in_user(build_conn(), user_fixture())
    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    refute has_element?(lv, "#connect-meu-pluggy")
  end
end
