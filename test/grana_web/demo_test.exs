defmodule GranaWeb.DemoTest do
  use GranaWeb.ConnCase, async: false

  import Grana.AccountsFixtures
  import Grana.BankingFixtures
  import Phoenix.LiveViewTest

  alias Grana.Accounts
  alias Grana.Accounts.User
  alias Grana.Demo
  alias Grana.Repo

  defp demo_user do
    user_fixture() |> Ecto.Changeset.change(demo: true) |> Repo.update!()
  end

  defp enable_demo(_context) do
    Application.put_env(:grana, :demo, true)
    on_exit(fn -> Application.put_env(:grana, :demo, false) end)
  end

  describe "outside the demo" do
    test "the login hides the demo access and the landing offers the login", %{conn: conn} do
      user_fixture()

      {:ok, view, _html} = live(conn, ~p"/users/log-in")
      refute has_element?(view, "#demo-credentials")
      assert has_element?(view, "#forgot-password-link")

      {:ok, view, _html} = live(build_conn(), ~p"/")
      assert has_element?(view, "#hero-login")
      refute has_element?(view, "#hero-demo")
      refute has_element?(view, "#hero-demo-note")
    end
  end

  describe "in the demo" do
    setup :enable_demo

    setup do
      %{user: demo_user()}
    end

    test "the login shows the demo access already filled in", %{conn: conn} do
      %{email: email, password: password} = Demo.credentials()
      {:ok, view, _html} = live(conn, ~p"/users/log-in")

      assert has_element?(view, "#demo-credentials", email)
      assert has_element?(view, "#demo-credentials", password)
      assert has_element?(view, ~s(#login_form_password_email[value="#{email}"]))

      assert has_element?(
               view,
               ~s(#login_form_password input[type=password][value="#{password}"])
             )

      refute has_element?(view, "#forgot-password-link")
    end

    test "the visitor signs in with the password like in a real instance", %{
      conn: conn,
      user: user
    } do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == ~p"/dashboard"

      assert {%User{id: id}, _} =
               Accounts.get_user_by_session_token(get_session(conn, :user_token))

      assert id == user.id
    end

    test "the landing offers the demo through the login and explains it", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      for id <- ~w(#nav-demo #hero-demo #cta-demo #hero-demo-note),
          do: assert(has_element?(view, id))

      assert has_element?(view, ~s(#hero-demo[href="/users/log-in"]))
      refute has_element?(view, "#hero-login")

      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/")
      assert has_element?(view, ~s(#hero-demo[href="/dashboard"]))
    end

    test "password recovery, the 2FA code and the technical routes are closed", %{
      conn: conn,
      user: user
    } do
      for path <- [~p"/users/reset-password", ~p"/users/log-in/code"],
          do: assert({:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, path))

      assert conn |> post(~p"/users/log-in/code", %{"code" => "123456"}) |> response(404)
      assert conn |> post(~p"/webhooks/pluggy", %{}) |> response(404)

      conn = log_in_user(conn, user)
      assert conn |> get(~p"/admin/oban") |> response(404)
      assert conn |> get(~p"/users/settings/backup") |> response(404)
    end

    test "the app shows the demo strip with how it works", %{conn: conn, user: user} do
      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/categories")

      assert has_element?(view, "#demo-banner", "Demonstração com dados fictícios")
      assert has_element?(view, "#demo-banner-more[aria-controls=demo-info]")
      assert has_element?(view, "#demo-info li", "Volta ao original")
      assert has_element?(view, "#demo-info-close")
      assert has_element?(view, "#demo-info a[href='/#instalacao']")
    end

    test "settings show the sensitive fields read-only, with a note on each section", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

      for group <- ~w(account ai integrations backup system danger) do
        assert has_element?(view, "#settings-demo-#{group}")
        assert has_element?(view, "#settings-#{group} > fieldset[disabled]")
      end

      for id <-
            ~w(#email_form #identity_form #ai-provider-form #backup #diagnostics #danger-zone),
          do: assert(has_element?(view, id))

      refute has_element?(view, "#settings-demo-preferences")
      refute has_element?(view, "#settings-preferences fieldset[disabled]")
    end

    test "settings refuse to erase the instance even with the right password", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/users/settings?section=danger")

      render_hook(view, "confirm_reset", %{
        "reset" => %{"confirmation" => "APAGAR", "password" => valid_user_password()}
      })

      assert Repo.get(User, user.id)
      refute Accounts.setup_required?()
    end

    test "the chat keeps its example and saves no question", %{conn: conn, user: user} do
      transaction_fixture(user)
      {:ok, conversation} = Grana.Chat.start_conversation(user.id, "Conversa")
      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/chat/#{conversation.id}")

      assert has_element?(view, "#chat-demo-notice")
      refute has_element?(view, "#chat-composer")

      render_hook(view, "send", %{"message" => "Quanto gastei?"})
      assert Repo.aggregate(Grana.Chat.Message, :count) == 0
    end

    test "importing only explains that the demo has no real import", %{conn: conn, user: user} do
      transaction_fixture(user)
      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/upload")

      assert has_element?(view, "#upload-demo-notice")
      refute has_element?(view, "#upload-form")

      render_hook(view, "select_upload_category", %{"category" => "banking"})
      refute has_element?(view, "#upload-form")
      assert Repo.all(Oban.Job) == []
    end

    test "privacy and theme belong to each visitor, not to the shared account", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)
      token = get_session(conn, :user_token)
      {:ok, view, _html} = live(conn, ~p"/categories")
      render_hook(view, "set_preference", %{"hide_values" => "true", "theme" => "dark"})

      assert has_element?(view, "#app-shell.ui-hide-values")
      refute Repo.get!(User, user.id).hide_values

      {:ok, other, _html} = build_conn() |> log_in_user(user) |> live(~p"/categories")
      refute has_element?(other, "#app-shell.ui-hide-values")

      {:ok, again, _html} =
        build_conn() |> init_test_session(%{user_token: token}) |> live(~p"/categories")

      assert has_element?(again, "#app-shell.ui-hide-values")
    end
  end

  describe "guards in the contexts" do
    setup :enable_demo

    test "AI, SMTP, Open Finance and restore refuse to run" do
      user = demo_user()

      assert Grana.AI.resolve(user, "chat") == {:error, :demo}

      assert {:error, %Ecto.Changeset{} = changeset} =
               Grana.AI.add_provider(user, %{"kind" => "gemini", "api_key" => "chave"})

      assert changeset.errors[:api_key]

      assert {:error, changeset} =
               Accounts.save_smtp_settings(user, %{"smtp_host" => "smtp.exemplo.com"})

      assert changeset.errors[:smtp_host]
      refute Accounts.smtp_configured?()

      scope = Accounts.Scope.for_user(user)
      assert Grana.OpenFinance.credentials(scope) == nil

      assert {:error, changeset} =
               Grana.OpenFinance.save_credentials(scope, %{
                 "pluggy_client_id" => "id",
                 "pluggy_client_secret" => "secret"
               })

      assert changeset.errors[:pluggy_client_id]
      assert Grana.Backup.restore(%{path: "/nada.db"}, user.id) == {:error, :demo}
      assert Grana.Backup.reset_all() == {:error, :demo}
      assert Repo.get(User, user.id)
    end

    test "the shared account keeps its email, password and holder" do
      user = demo_user()

      assert {:error, changeset} =
               Accounts.update_user_password(user, "x", %{password: "uma senha nova e longa"})

      assert changeset.errors[:password]

      assert {:error, _changeset} = Accounts.update_user_email_directly(user, %{email: "x@y.com"})
      assert {:error, _changeset} = Accounts.update_user_identity(user, %{name: "Outra Pessoa"})

      assert Accounts.deliver_user_update_email_instructions(user, user.email, & &1) ==
               {:error, :demo}
    end

    test "session preferences only apply to the demo account" do
      user = user_fixture()
      assert Demo.with_session_preferences(user, "token") == user
    end
  end
end
