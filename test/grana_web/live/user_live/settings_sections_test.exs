defmodule GranaWeb.UserLive.SettingsSectionsTest do
  use GranaWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  @groups %{
    "account" => ~w(account-settings identity-settings),
    "preferences" => ~w(preferences-settings privacy-settings),
    "ai" => ~w(ai-settings),
    "integrations" => ~w(open-finance-settings smtp-settings),
    "backup" => ~w(backup),
    "system" => ~w(diagnostics),
    "danger" => ~w(danger-zone)
  }

  defp assert_only_visible(view, section) do
    for key <- Map.keys(@groups) do
      if key == section do
        refute has_element?(view, "#settings-#{key}.hidden"), "#{key} should be visible"
        assert has_element?(view, "#settings-nav-#{key}[aria-current=page]")
      else
        assert has_element?(view, "#settings-#{key}.hidden"), "#{key} should be hidden"
        refute has_element?(view, "#settings-nav-#{key}[aria-current]")
      end
    end
  end

  test "each group holds its related cards", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/users/settings")

    for {key, cards} <- @groups, card <- cards do
      assert has_element?(view, "#settings-#{key} ##{card}"), "#{card} should be in #{key}"
    end
  end

  test "opens on the account group", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/users/settings")

    assert_only_visible(view, "account")
  end

  test "the address picks the group, and an unknown one falls back to account", %{conn: conn} do
    for key <- Map.keys(@groups) do
      {:ok, view, _html} = live(conn, ~p"/users/settings?section=#{key}")
      assert_only_visible(view, key)
    end

    {:ok, view, _html} = live(conn, ~p"/users/settings?section=nope")
    assert_only_visible(view, "account")
  end

  test "the menu switches groups without leaving the page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/users/settings")

    view |> element("#settings-nav-integrations") |> render_click()

    assert_patch(view, ~p"/users/settings?section=integrations")
    assert_only_visible(view, "integrations")
  end

  test "the danger zone has its own group", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/users/settings?section=danger")

    assert has_element?(view, "#settings-nav-danger.ui-settings-nav-item-danger")
    refute has_element?(view, "#danger-zone a[href='/users/settings/backup']")

    view |> element("#show-reset-modal") |> render_click()

    assert has_element?(view, "#reset-modal")
  end
end
