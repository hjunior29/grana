defmodule GranaWeb.LearnedRulesTest do
  use GranaWeb.ConnCase

  import Phoenix.LiveViewTest
  import Grana.BankingFixtures

  alias Grana.Banking

  setup :register_and_log_in_user

  describe "category rules on Categories" do
    setup %{user: user} do
      category = category_fixture(user, %{name: "Delivery"})
      rule = category_rule_fixture(user, category, %{pattern: "ifood"})
      %{category: category, rule: rule}
    end

    test "the rule count opens the rules of the category", %{conn: conn, category: category} do
      {:ok, view, _html} = live(conn, ~p"/categories")

      view |> element("#category-#{category.id}-rules", "1 regra") |> render_click()

      assert has_element?(view, "#category-rules-modal-title", "Regras de Delivery")
      assert has_element?(view, "#category-rules-modal .ui-private-name", "ifood")

      render_click(view, "close_rules", %{})
      refute has_element?(view, "#category-rules-modal")
    end

    test "a rule can be removed", %{conn: conn, user: user, category: category, rule: rule} do
      {:ok, view, _html} = live(conn, ~p"/categories")
      view |> element("#category-#{category.id}-rules") |> render_click()

      view |> element("#category-rule-#{rule.id} button") |> render_click()

      assert render(view) =~ "Regra removida."
      assert has_element?(view, "#category-rules-modal", "Nenhuma regra ainda")
      assert has_element?(view, "#category-#{category.id}-rules", "0 regras")
      assert Banking.category_rules(user.id, category.id) == []
    end

    test "a term can be added by hand", %{conn: conn, user: user, category: category} do
      {:ok, view, _html} = live(conn, ~p"/categories")
      view |> element("#category-#{category.id}-rules") |> render_click()

      view |> form("#category-rule-form", rule: %{pattern: "  Rappi  "}) |> render_submit()

      assert render(view) =~ "Regra adicionada."
      assert has_element?(view, "#category-rules-modal .ui-private-name", "rappi")
      assert has_element?(view, "#category-#{category.id}-rules", "2 regras")

      assert Enum.map(Banking.category_rules(user.id, category.id), & &1.pattern) == [
               "ifood",
               "rappi"
             ]

      # The next import uses it.
      assert Banking.categorize_transaction("RAPPI*RESTAURANTE", user.id) == category.id
    end

    test "a blank term is refused in the field", %{conn: conn, user: user, category: category} do
      {:ok, view, _html} = live(conn, ~p"/categories")
      view |> element("#category-#{category.id}-rules") |> render_click()

      view |> form("#category-rule-form", rule: %{pattern: "   "}) |> render_submit()

      assert has_element?(view, "#category-rule-form", "digite um termo")
      assert length(Banking.category_rules(user.id, category.id)) == 1
    end
  end

  describe "internal transfer rules on Transactions" do
    setup %{user: user} do
      [txn] =
        transactions_fixture(user, [
          %{description: "Transferência enviada pelo Pix - JOAO SILVA", date: ~D[2026-03-02]}
        ])

      %{txn: txn}
    end

    test "without rules there is no button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/transactions")
      refute has_element?(view, "#internal-rules-open")
    end

    test "marking a transfer saves a rule that can be removed and recalculated", %{
      conn: conn,
      user: user,
      txn: txn
    } do
      {:ok, view, _html} = live(conn, ~p"/transactions")

      render_click(view, "toggle-internal", %{"id" => to_string(txn.id), "internal" => "true"})
      assert Grana.Repo.reload!(txn).is_internal_transfer

      view |> element("#internal-rules-open", "Regras internas (1)") |> render_click()
      [rule] = Banking.list_internal_transfer_rules(user.id)
      assert has_element?(view, "#internal-rule-#{rule.id} .ui-private-name", "JOAO SILVA")
      assert has_element?(view, "#internal-rule-#{rule.id}", "interna")

      view |> element("#internal-rule-#{rule.id} button") |> render_click()

      assert render(view) =~ "Regra removida e transferências recalculadas."
      refute has_element?(view, "#internal-rules-modal")
      refute has_element?(view, "#internal-rules-open")
      refute Grana.Repo.reload!(txn).is_internal_transfer
    end

    test "a CPF rule shows only the visible middle of the CPF", %{conn: conn, user: user} do
      Grana.Repo.insert!(%Grana.Banking.InternalTransferRule{
        user_id: user.id,
        pattern: "cpf:123456",
        kind: "external"
      })

      {:ok, view, _html} = live(conn, ~p"/transactions")
      view |> element("#internal-rules-open") |> render_click()

      assert has_element?(view, "#internal-rules-modal", "CPF •••.123.456-••")
      assert has_element?(view, "#internal-rules-modal", "externa")

      render_click(view, "close_internal_rules", %{})
      refute has_element?(view, "#internal-rules-modal")
    end
  end
end
