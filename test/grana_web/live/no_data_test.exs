defmodule GranaWeb.NoDataTest do
  use GranaWeb.ConnCase, async: false
  use Mimic

  import Phoenix.LiveViewTest
  import Grana.AccountsFixtures
  import Grana.BankingFixtures

  setup :register_and_log_in_user
  setup :set_mimic_global

  setup %{user: user} do
    stub(Grana.AI.Models, :list, fn _config ->
      {:ok, [%{id: "gemini-pro", name: "Gemini Pro"}]}
    end)

    %{user: ai_fixture(user)}
  end

  defp assert_only_no_data(view, id) do
    assert has_element?(view, "##{id} a[href='/upload']", "Importar extratos")

    assert has_element?(
             view,
             "##{id} a[href='/users/settings?section=integrations']",
             "Conectar o Open Finance"
           )
  end

  describe "without any transaction" do
    test "the dashboard shows neither tabs nor filters", %{conn: conn} do
      for path <- [~p"/dashboard", ~p"/dashboard?tab=recurring"] do
        {:ok, view, _html} = live(conn, path)

        assert_only_no_data(view, "dashboard-no-data")
        refute has_element?(view, "[role=tablist]")
        refute has_element?(view, "#banking-filters")
        refute has_element?(view, "#recurring-filters")
      end
    end

    test "transactions show neither filters nor the advanced search", %{conn: conn} do
      for path <- [~p"/transactions", ~p"/transactions?mode=advanced"] do
        {:ok, view, _html} = live(conn, path)

        assert_only_no_data(view, "transactions-no-data")
        refute has_element?(view, "#advanced-search-open")
        refute has_element?(view, "#advanced-search-close")
        refute has_element?(view, "#advanced-search")
        refute has_element?(view, "#ai-search")
        refute has_element?(view, "#transactions-table")
      end
    end

    test "the chat shows neither the composer nor the conversations", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/chat")

      assert_only_no_data(view, "chat-no-data")
      refute has_element?(view, "#new-conversation")
      refute has_element?(view, "#chat-composer")
      refute has_element?(view, "#conversations-panel")
    end

    test "goals show no new goal button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/goals")

      assert_only_no_data(view, "goals-no-data")
      refute has_element?(view, "#new-goal")
      refute has_element?(view, "#goals-empty")
    end

    test "categories stay open: they come before the data", %{conn: conn} do
      {:ok, categories, _html} = live(conn, ~p"/categories")
      assert has_element?(categories, "#new-category")
    end

    test "imports show only the import, without history and calendar tabs", %{conn: conn} do
      for tab <- ~w(upload historico calendario) do
        {:ok, upload, _html} = live(conn, ~p"/upload?tab=#{tab}")

        refute has_element?(upload, "[role=tablist]")
        refute has_element?(upload, "#statements-table")
        refute has_element?(upload, "#calendar-heatmap")
        refute render(upload) =~ "Nenhuma transação ainda"
      end
    end
  end

  describe "when the first transactions arrive" do
    test "a screen that reads the data reloads, keeping its address", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/transactions?mode=advanced")

      transaction_fixture(user)
      send(view.pid, :imports_changed)

      assert_redirect(view, "/transactions?mode=advanced")
    end

    test "an Open Finance read reloads too", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/dashboard?tab=recurring")

      transaction_fixture(user)
      send(view.pid, {:open_finance_synced, 1})

      assert_redirect(view, "/dashboard?tab=recurring")
    end

    test "an import that brings nothing keeps the screen", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      send(view.pid, :imports_changed)

      assert has_element?(view, "#dashboard-no-data")
    end

    test "the import screen itself does not reload", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      transaction_fixture(user)
      send(view.pid, :imports_changed)

      assert render(view)
    end

    test "with data, the screens open as usual", %{conn: conn, user: user} do
      transaction_fixture(user)

      {:ok, chat, _html} = live(conn, ~p"/chat")
      assert has_element?(chat, "#chat-composer")
      refute has_element?(chat, "#chat-no-data")

      {:ok, goals, _html} = live(conn, ~p"/goals")
      assert has_element?(goals, "#new-goal")
    end
  end
end
