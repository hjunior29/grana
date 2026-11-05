defmodule GranaWeb.QuickActionsLiveTest do
  use GranaWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Grana.Banking

  setup :register_and_log_in_user

  for path <- ~w(/dashboard /transactions /categories /goals /upload /chat /users/settings) do
    test "a busca rápida está disponível em #{path}", %{conn: conn} do
      {:ok, view, _html} = live(conn, unquote(path))

      assert has_element?(view, "#quick-actions[phx-hook=QuickActions][phx-update=ignore]")
      assert has_element?(view, "#quick-actions-open[aria-haspopup=dialog]")
      assert has_element?(view, "#quick-actions-dialog[aria-labelledby=quick-actions-title]")
      assert has_element?(view, "#quick-actions-query[role=combobox]")

      render_hook(view, "quick_actions:load")
      assert_reply view, %{searches: []}
    end
  end

  test "os atalhos apontam para formulários, páginas e seções existentes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    assert has_element?(view, "#quick-action-new-goal[href='/goals?action=new']")
    assert has_element?(view, "#quick-action-new-category[href='/categories?action=new']")
    assert has_element?(view, "#quick-action-new-chat[href='/chat/new']")
    assert has_element?(view, "#quick-action-fixed[href='/dashboard?tab=recurring']")
    assert has_element?(view, "#quick-action-search[href='/transactions?mode=advanced']")
    assert has_element?(view, "#quick-action-account[href='/users/settings?section=account']")
    assert has_element?(view, "#quick-action-ai[href='/users/settings?section=ai']")
    assert has_element?(view, "#quick-action-backup[href='/users/settings?section=backup']")
  end

  test "carrega apenas as buscas do usuário autenticado e ignora um user_id enviado", %{
    conn: conn,
    user: user
  } do
    other = Grana.AccountsFixtures.user_fixture()

    {:ok, saved} =
      Banking.create_saved_search(user.id, %{name: "Delivery", query: "ifood OR rappi"})

    {:ok, _other_saved} =
      Banking.create_saved_search(other.id, %{name: "Busca de outra pessoa", query: "uber"})

    {:ok, view, _html} = live(conn, ~p"/dashboard")
    render_hook(view, "quick_actions:load", %{"user_id" => other.id})

    assert_reply view, %{searches: [%{id: id, name: "Delivery", path: path}]}
    assert id == saved.id
    assert URI.parse(path).path == "/transactions"

    assert URI.decode_query(URI.parse(path).query) == %{
             "mode" => "advanced",
             "q" => "ifood OR rappi",
             "saved" => to_string(saved.id)
           }
  end

  test "reabrir atualiza buscas criadas, editadas ou removidas na mesma sessão", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/categories")
    render_hook(view, "quick_actions:load")
    assert_reply view, %{searches: []}

    {:ok, saved} = Banking.create_saved_search(user.id, %{name: "Transporte", query: "uber"})
    render_hook(view, "quick_actions:load")
    assert_reply view, %{searches: [%{name: "Transporte"}]}

    {:ok, saved} = Banking.update_saved_search(saved, %{name: "Carros", query: "uber OR 99"})
    render_hook(view, "quick_actions:load")
    assert_reply view, %{searches: [%{name: "Carros", path: path}]}
    assert URI.decode_query(URI.parse(path).query)["q"] == "uber OR 99"

    {:ok, _} = Banking.delete_saved_search(saved)
    render_hook(view, "quick_actions:load")
    assert_reply view, %{searches: []}
  end

  test "a busca rápida não aparece no onboarding", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/onboarding")
    refute has_element?(view, "#quick-actions")
  end

  test "a busca rápida não aparece nas páginas públicas" do
    conn = build_conn()
    {:ok, landing, _html} = live(conn, ~p"/")
    refute has_element?(landing, "#quick-actions")

    {:ok, login, _html} = live(conn, ~p"/users/log-in")
    refute has_element?(login, "#quick-actions")
  end
end
