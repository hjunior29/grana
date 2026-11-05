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

  describe "modo privacidade no cabeçalho e na busca rápida" do
    test "o olho liga e desliga valores e nomes juntos", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert has_element?(view, "#privacy-toggle[aria-pressed=false] .hero-eye")
      refute has_element?(view, "#privacy-toggle.is-active")

      view |> element("#privacy-toggle") |> render_click()

      assert has_element?(view, "#app-shell.ui-hide-values.ui-hide-names")
      assert has_element?(view, "#privacy-toggle.is-active[aria-pressed=true] .hero-eye-slash")
      assert %{hide_values: true, hide_names: true} = Accounts.get_user!(user.id)

      view |> element("#privacy-toggle") |> render_click()

      refute has_element?(view, "#app-shell.ui-hide-values")
      refute has_element?(view, "#app-shell.ui-hide-names")
    end

    test "com só um deles ligado, o olho liga os dois", %{conn: conn, user: user} do
      hide(user, %{hide_names: true})
      {:ok, view, _html} = live(conn, ~p"/transactions")

      assert has_element?(view, "#privacy-toggle[aria-pressed=false] .hero-eye-slash")
      view |> element("#privacy-toggle") |> render_click()

      assert has_element?(view, "#app-shell.ui-hide-values.ui-hide-names")
    end

    test "a busca rápida traz os comandos de privacidade, juntos e separados", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/goals")

      assert has_element?(
               view,
               "#quick-actions-privacy #quick-action-privacy-all[data-privacy=all]"
             )

      assert has_element?(view, "#quick-action-privacy-all[data-suggested=true]")
      assert has_element?(view, "#quick-action-privacy-values[data-privacy=values]")
      assert has_element?(view, "#quick-action-privacy-names[data-privacy=names]")

      # O hook manda o mesmo evento das Configurações, só com o que muda.
      render_hook(view, "set_preference", %{"hide_names" => "true"})

      assert has_element?(view, "#app-shell.ui-hide-names")
      refute has_element?(view, "#app-shell.ui-hide-values")
    end
  end
end
