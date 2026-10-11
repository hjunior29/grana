defmodule GranaWeb.TransactionsAdvancedSearchTest do
  use GranaWeb.ConnCase

  import Phoenix.LiveViewTest
  import Grana.BankingFixtures

  alias Grana.Banking

  setup :register_and_log_in_user

  setup %{user: user} do
    transactions_fixture(user, [
      %{description: "UBER TRIP", amount: "-20.00", date: ~D[2026-03-10]},
      %{description: "99 POP", amount: "-15.00", date: ~D[2026-03-11]},
      %{description: "SALARIO", amount: "5000.00", type: "credit", date: ~D[2026-03-05]}
    ])

    :ok
  end

  defp query_of(path) do
    path |> URI.parse() |> Map.get(:query) |> URI.decode_query()
  end

  defp row?(view, description), do: has_element?(view, "#transactions-table td", description)

  test "o botão leva ao modo avançado levando junto os filtros simples", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/transactions?search=uber&movement=expense&internal=hide")

    refute has_element?(view, "#advanced-search")

    view |> element("#advanced-search-open") |> render_click()

    params = view |> assert_patch() |> query_of()
    assert params["mode"] == "advanced"
    assert params["q"] == "uber AND type:debit AND internal:false"
  end

  test "converte todos os filtros simples para a sintaxe", %{conn: conn, user: user} do
    category = category_fixture(user, %{name: "Casa e Lar"})

    path =
      ~p"/transactions?#{%{origin: "bank:nubank", kind: "category:#{category.id}", movement: "income", date_from: "2026-01-01", date_to: "2026-03-31", amount_min: "10", internal: "only", filter: "uncategorized"}}"

    {:ok, view, _html} = live(conn, path)
    view |> element("#advanced-search-open") |> render_click()

    assert view |> assert_patch() |> query_of() |> Map.get("q") ==
             ~s(type:credit AND bank:nubank AND category:"Casa e Lar" AND date:2026-01-01..2026-03-31 AND amount>=10 AND internal:true AND category:"Sem Categoria")
  end

  test "extrato ou fatura vira statement_type", %{conn: conn} do
    {:ok, view, _html} =
      live(conn, ~p"/transactions?kind=statement:fatura&amount_max=50&search=posto shell")

    view |> element("#advanced-search-open") |> render_click()

    assert view |> assert_patch() |> query_of() |> Map.get("q") ==
             ~s("posto shell" AND statement_type:fatura AND amount<=50)
  end

  test "sem filtros, abre o editor vazio com a lista inteira", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/transactions?mode=advanced")

    assert has_element?(view, "#advanced-search-form")
    assert has_element?(view, "#saved-searches-empty")
    refute has_element?(view, "#transactions-filters-card")
    assert row?(view, "SALARIO")
    assert has_element?(view, "#advanced-search-close[href='/transactions']")
  end

  test "busca e mostra só o que casa", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/transactions?mode=advanced")

    view
    |> form("#advanced-search-form", %{q: "(uber OR 99) AND type:expense"})
    |> render_submit()

    params = view |> assert_patch() |> query_of()
    assert params["q"] == "(uber OR 99) AND type:expense"

    assert row?(view, "UBER TRIP")
    assert row?(view, "99 POP")
    refute row?(view, "SALARIO")
    assert has_element?(view, "#export-csv[href*='q=']")
  end

  test "mostra como leu a busca quando há operador implícito", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/transactions?q=uber+trip")

    assert has_element?(view, "#advanced-search-canonical", "uber AND trip")
    assert row?(view, "UBER TRIP")
  end

  test "busca inválida mostra o erro e esconde os resultados", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/transactions?q=(uber")

    assert has_element?(view, "#advanced-search-error", "Faltou fechar um parêntese")
    refute has_element?(view, "#transactions-table")
    refute has_element?(view, "#transactions-empty")
  end

  test "busca sem resultado tem estado vazio próprio", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/transactions?q=zzzz")

    assert has_element?(view, "#transactions-empty", "Nada com essa busca")
  end

  test "salva a busca com um nome", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/transactions?mode=advanced")

    view
    |> form("#advanced-search-form", %{q: "uber OR 99"})
    |> render_submit(%{intent: "save"})

    assert has_element?(view, "#save-search-modal")

    view
    |> form("#save-search-modal-form", saved_search: %{name: "Transporte"})
    |> render_submit()

    assert [saved] = Banking.list_saved_searches(user.id)
    assert saved.name == "Transporte"
    assert saved.query == "uber OR 99"

    refute has_element?(view, "#save-search-modal")
    assert has_element?(view, "#saved-search-#{saved.id}", "Transporte")
    assert has_element?(view, "#saved-search-#{saved.id} .ui-saved-search-active")
    assert render(view) =~ "Busca salva."
  end

  test "não abre o salvar com a busca inválida", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/transactions?mode=advanced")

    view
    |> form("#advanced-search-form", %{q: "(uber"})
    |> render_submit(%{intent: "save"})

    refute has_element?(view, "#save-search-modal")
  end

  test "nome repetido fica no formulário com o erro", %{conn: conn, user: user} do
    {:ok, _} = Banking.create_saved_search(user.id, %{"name" => "Transporte", "query" => "uber"})
    {:ok, view, _html} = live(conn, ~p"/transactions?mode=advanced")

    view
    |> form("#advanced-search-form", %{q: "99"})
    |> render_submit(%{intent: "save"})

    view
    |> form("#save-search-modal-form", saved_search: %{name: "Transporte"})
    |> render_submit()

    assert has_element?(view, "#save-search-modal", "já existe uma busca com esse nome")

    view |> element("#save-search-modal .modal-backdrop") |> render_click()
    refute has_element?(view, "#save-search-modal")
  end

  test "abre uma busca salva e atualiza depois de editar", %{conn: conn, user: user} do
    {:ok, saved} = Banking.create_saved_search(user.id, %{"name" => "Uber", "query" => "uber"})
    {:ok, view, _html} = live(conn, ~p"/transactions?mode=advanced")

    view |> element("#saved-search-#{saved.id} a") |> render_click()

    params = view |> assert_patch() |> query_of()
    assert params["q"] == "uber"
    assert params["saved"] == to_string(saved.id)
    refute has_element?(view, "#update-saved-search")

    view
    |> form("#advanced-search-form", %{q: "uber OR 99"})
    |> render_submit(%{intent: "run"})

    assert has_element?(view, "#update-saved-search", ~s(Atualizar "Uber"))

    view
    |> form("#advanced-search-form", %{q: "uber OR 99"})
    |> render_submit(%{intent: "update"})

    assert Banking.get_saved_search(user.id, saved.id).query == "uber OR 99"
    assert has_element?(view, "#flash-info", ~s(Busca "Uber" atualizada.))
  end

  test "remove uma busca salva depois de confirmar", %{conn: conn, user: user} do
    {:ok, saved} = Banking.create_saved_search(user.id, %{"name" => "Uber", "query" => "uber"})
    {:ok, view, _html} = live(conn, ~p"/transactions?mode=advanced")

    view |> element("#saved-search-#{saved.id} button") |> render_click()
    assert has_element?(view, "#delete-saved-search-modal", ~s(A busca "Uber" sai da lista))

    view |> element("#delete-saved-search-modal .modal-backdrop") |> render_click()
    refute has_element?(view, "#delete-saved-search-modal")

    view |> element("#saved-search-#{saved.id} button") |> render_click()
    view |> element("#delete-saved-search-modal-confirm") |> render_click()

    refute has_element?(view, "#saved-search-#{saved.id}")
    assert Banking.list_saved_searches(user.id) == []
  end

  test "ordenar e paginar mantém a busca", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/transactions?q=uber+OR+99")

    assert has_element?(view, "a[href*='sort_by=amount'][href*='q=uber']")
  end
end
