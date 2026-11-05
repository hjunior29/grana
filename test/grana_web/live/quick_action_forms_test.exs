defmodule GranaWeb.QuickActionFormsTest do
  use GranaWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Grana.Banking

  setup :register_and_log_in_user

  test "o atalho abre uma meta sem dados e consome o parâmetro", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/goals?action=new")

    assert has_element?(view, "#goal-form")

    render_click(view, "hide_form")
    refute has_element?(view, "#goal-form")

    render_patch(view, ~p"/goals?action=new")
    assert_patch(view, ~p"/goals")
    assert has_element?(view, "#goal-form")

    {:ok, fresh, _html} = live(conn, ~p"/goals")
    refute has_element?(fresh, "#goal-form")
  end

  test "a meta só é criada depois do envio do formulário", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/goals?action=new")
    assert Banking.list_financial_goals(user.id) == []

    view
    |> form("#goal-form", %{goal: %{type: "expense_limit"}})
    |> render_submit(%{goal: %{target_value: "1500"}})

    assert [%{type: "expense_limit", target_value: amount}] =
             Banking.list_financial_goals(user.id)

    assert Decimal.equal?(amount, "1500")
    refute has_element?(view, "#goal-form")
  end

  test "o atalho abre uma categoria e permite cancelar sem criá-la", %{conn: conn, user: user} do
    count = length(Banking.list_categories(user.id))
    {:ok, view, _html} = live(conn, ~p"/categories?action=new")

    assert has_element?(view, "#category-form")

    render_click(view, "cancel_form")
    refute has_element?(view, "#category-form")
    assert length(Banking.list_categories(user.id)) == count

    render_patch(view, ~p"/categories?action=new")
    assert_patch(view, ~p"/categories")
    assert has_element?(view, "#category-form")
  end

  test "o atalho usa o fluxo existente de salvar categoria", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/categories?action=new")

    view
    |> form("#category-form", %{category: %{name: "Viagens"}})
    |> render_submit()

    assert Enum.any?(Banking.list_categories(user.id), &(&1.name == "Viagens"))
    refute has_element?(view, "#category-form")
  end

  test "parâmetros desconhecidos não abrem formulários", %{conn: conn} do
    {:ok, goals, _html} = live(conn, ~p"/goals?action=delete")
    refute has_element?(goals, "#goal-form")

    {:ok, categories, _html} = live(conn, ~p"/categories?action=delete")
    refute has_element?(categories, "#category-form")
  end

  test "os atalhos de criação exigem autenticação" do
    conn = build_conn()

    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/goals?action=new")
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/categories?action=new")
  end
end
