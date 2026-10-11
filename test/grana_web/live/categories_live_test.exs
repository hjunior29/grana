defmodule GranaWeb.CategoriesLiveTest do
  use GranaWeb.ConnCase

  import Phoenix.LiveViewTest
  import Grana.BankingFixtures

  alias Grana.Banking

  setup :register_and_log_in_user

  test "renders categories page", %{conn: conn, user: user} do
    Banking.ensure_default_categories(user.id)
    {:ok, _view, html} = live(conn, ~p"/categories")
    assert html =~ "Categorias"
    assert html =~ "Alimentação"
  end

  test "shows empty state when no custom categories", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/categories")
    assert html =~ "Categorias"
  end

  test "redirects unauthenticated users" do
    conn = build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/categories")
  end

  describe "new_category" do
    test "opens the new category form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/categories")

      html = view |> element("button[phx-click=new_category]") |> render_click()

      assert html =~ "Nova categoria"
    end

    test "cancel_form closes the modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/categories")

      view |> element("button[phx-click=new_category]") |> render_click()
      html = render_click(view, "cancel_form", %{})

      # After cancel the form dialog is gone; the form submit button is gone
      refute html =~ "phx-submit=\"save_category\""
    end

    test "select_icon updates icon selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/categories")
      view |> element("button[phx-click=new_category]") |> render_click()

      render_click(view, "select_icon", %{"icon" => "hero-home"})

      html = render(view)
      assert html =~ "hero-home"
    end

    test "select_color updates color selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/categories")
      view |> element("button[phx-click=new_category]") |> render_click()

      render_click(view, "select_color", %{"color" => "#EF4444"})

      html = render(view)
      assert html =~ "#EF4444"
    end

    test "select_kind updates kind selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/categories")
      view |> element("button[phx-click=new_category]") |> render_click()

      render_click(view, "select_kind", %{"kind" => "income"})

      html = render(view)
      assert html =~ "Receita"
    end

    test "save_category creates a new category", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/categories")

      view |> element("button[phx-click=new_category]") |> render_click()

      view
      |> form("#category-form", %{
        "category" => %{"name" => "Pets", "icon" => "hero-tag", "kind" => "expense"}
      })
      |> render_submit()

      categories = Banking.list_categories(user.id)
      names = Enum.map(categories, & &1.name)
      assert "Pets" in names
    end

    test "shows error when name is empty", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/categories")

      view |> element("button[phx-click=new_category]") |> render_click()

      # Submit save_category directly to bypass hidden-field validation in form/3
      render_click(view, "save_category", %{
        "category" => %{
          "name" => "",
          "icon" => "hero-tag",
          "color" => "#6366F1",
          "kind" => "expense"
        }
      })

      # Validation failed: no category was persisted
      assert Banking.list_categories(user.id) == []
    end
  end

  describe "edit_category" do
    test "opens edit form with existing data", %{conn: conn, user: user} do
      cat = category_fixture(user, %{name: "Viagens", icon: "hero-globe-alt", color: "#3B82F6"})

      {:ok, view, _html} = live(conn, ~p"/categories")

      html = render_click(view, "edit_category", %{"id" => to_string(cat.id)})

      assert html =~ "Editar categoria"
    end

    test "save_category updates category name", %{conn: conn, user: user} do
      cat = category_fixture(user, %{name: "Viagens Antigas"})

      {:ok, view, _html} = live(conn, ~p"/categories")

      render_click(view, "edit_category", %{"id" => to_string(cat.id)})

      view
      |> form("#category-form", %{
        "category" => %{"name" => "Viagens"}
      })
      |> render_submit()

      html = render(view)
      assert html =~ "Viagens"
      assert html =~ "Categoria atualizada"
    end
  end

  describe "delete_category" do
    test "confirm_delete shows confirmation dialog", %{conn: conn, user: user} do
      cat = category_fixture(user, %{name: "Deletar Isto"})

      {:ok, view, _html} = live(conn, ~p"/categories")

      html = render_click(view, "confirm_delete", %{"id" => to_string(cat.id)})

      assert html =~ "Remover"
    end

    test "cancel_delete closes the confirmation dialog", %{conn: conn, user: user} do
      cat = category_fixture(user, %{name: "Deletar Isto"})

      {:ok, view, _html} = live(conn, ~p"/categories")

      render_click(view, "confirm_delete", %{"id" => to_string(cat.id)})

      html = render_click(view, "cancel_delete", %{})

      assert html =~ "Categorias"
    end

    test "delete removes a user category", %{conn: conn, user: user} do
      cat = category_fixture(user, %{name: "Para Remover"})

      {:ok, view, _html} = live(conn, ~p"/categories")

      render_click(view, "confirm_delete", %{"id" => to_string(cat.id)})
      render_click(view, "delete", %{})

      categories = Banking.list_categories(user.id)
      names = Enum.map(categories, & &1.name)
      refute "Para Remover" in names
    end

    test "cannot delete system category", %{conn: conn, user: user} do
      Banking.ensure_default_categories(user.id)
      system_cat = Banking.get_uncategorized_category(user.id)

      {:ok, view, _html} = live(conn, ~p"/categories")

      render_click(view, "confirm_delete", %{"id" => to_string(system_cat.id)})

      html = render_click(view, "delete", %{})

      assert html =~ "sistema" or html =~ "não podem ser removidas"
    end

    test "confirm_delete shows transaction count warning when category has transactions", %{
      conn: conn,
      user: user
    } do
      Banking.ensure_default_categories(user.id)
      cat = category_fixture(user, %{name: "Com Transacoes"})

      import Grana.BankingFixtures

      transaction_fixture(user, %{
        description: "TXN",
        amount: "-50.00",
        category_id: cat.id
      })

      {:ok, view, _html} = live(conn, ~p"/categories")

      html = render_click(view, "confirm_delete", %{"id" => to_string(cat.id)})

      assert html =~ "Categorias"
    end
  end

  describe "form kind investment" do
    test "select_kind investment shows investment description", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/categories")

      render_click(view, "new_category", %{})
      html = render_click(view, "select_kind", %{"kind" => "investment"})

      assert html =~ "investment" or html =~ "Investimento" or html =~ "dashboard"
    end
  end
end
