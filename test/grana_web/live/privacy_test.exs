defmodule GranaWeb.PrivacyTest do
  use GranaWeb.ConnCase

  import Phoenix.LiveViewTest
  import Grana.BankingFixtures

  alias Grana.Accounts

  setup :register_and_log_in_user

  setup %{user: user} do
    transactions_fixture(user, [
      %{description: "PIX JOAO DA SILVA", amount: "-120.00", date: ~D[2026-03-10]},
      %{description: "SALARIO EMPRESA X", amount: "5000.00", type: "credit", date: ~D[2026-03-05]}
    ])

    :ok
  end

  defp hide(user, attrs), do: {:ok, _} = Accounts.update_user_preferences(user, attrs)

  test "transações: nome e valor marcados, sem o nome no tooltip", %{conn: conn, user: user} do
    hide(user, %{hide_names: true, hide_values: true})
    {:ok, view, _html} = live(conn, ~p"/transactions?search=joao")

    assert has_element?(view, "#app-shell.ui-hide-names.ui-hide-values")
    assert has_element?(view, "#transactions-table .ui-private-name", "PIX JOAO DA SILVA")
    assert has_element?(view, "#transactions-table .ui-private", "-R$ 120,00")
    refute has_element?(view, ~s|#transactions-table [title*="JOAO"]|)
    assert has_element?(view, ".transactions-filter-search.ui-private-name-field input")
  end

  test "com os nomes visíveis, o tooltip mostra a descrição", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/transactions")

    refute has_element?(view, "#app-shell.ui-hide-names")
    assert has_element?(view, ~s|#transactions-table [title="PIX JOAO DA SILVA"]|)
  end

  test "painel: maiores receitas e despesas com o nome marcado", %{conn: conn, user: user} do
    hide(user, %{hide_names: true})
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    assert has_element?(view, ".ui-private-name", "PIX JOAO DA SILVA")
    assert has_element?(view, ".ui-private-name", "SALARIO EMPRESA X")
    refute has_element?(view, ~s|[title="SALARIO EMPRESA X"]|)
  end

  test "importar: o nome do arquivo do extrato fica marcado", %{conn: conn, user: user} do
    statement_fixture(user, %{filename: "extrato-joao-silva.csv"})
    {:ok, view, _html} = live(conn, ~p"/upload")

    render_click(view, "switch_tab", %{"tab" => "historico"})

    assert has_element?(view, ".ui-private-name", "extrato-joao-silva.csv")
  end
end
