defmodule GranaWeb.CalendarLiveTest do
  use GranaWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Grana.Banking

  setup :register_and_log_in_user

  test "mostra estado vazio quando não há dados", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/upload?tab=calendario")
    assert html =~ "Calendário de importações"
    assert html =~ "Ainda não há dados importados"
  end

  test "renderiza o heatmap com dados de extrato e fatura", %{
    conn: conn,
    user: user
  } do
    Banking.ensure_default_categories(user.id)
    uncat = Banking.get_uncategorized_category(user.id)

    {:ok, ext} =
      Banking.create_statement(%{
        bank: "bradesco",
        filename: "e.pdf",
        statement_type: "extrato",
        user_id: user.id
      })

    {:ok, fat} =
      Banking.create_statement(%{
        bank: "bradesco",
        filename: "f.pdf",
        statement_type: "fatura",
        user_id: user.id
      })

    Banking.bulk_insert_transactions([
      %{
        date: ~D[2026-03-10],
        description: "Compra extrato",
        amount: Decimal.new("-10.00"),
        type: "debit",
        bank_statement_id: ext.id,
        user_id: user.id,
        category_id: uncat.id
      },
      %{
        date: ~D[2026-03-20],
        description: "Outra compra do mesmo extrato",
        amount: Decimal.new("-15.00"),
        type: "debit",
        bank_statement_id: ext.id,
        user_id: user.id,
        category_id: uncat.id
      },
      %{
        date: ~D[2026-03-12],
        description: "Compra fatura",
        amount: Decimal.new("-20.00"),
        type: "debit",
        bank_statement_id: fat.id,
        user_id: user.id,
        category_id: uncat.id
      }
    ])

    {:ok, view, html} = live(conn, ~p"/upload?tab=calendario")
    assert html =~ "Calendário de importações"
    assert html =~ "2026"
    assert html =~ ~s(aria-label="Mar/2026 - 2 uploads - Extrato, Fatura")
    assert html =~ ~s(data-calendar-uploads="2 uploads")
    assert has_element?(view, ".grana-calendar-card")
    assert has_element?(view, "#calendar-heatmap.grana-calendar-heatmap")
    assert has_element?(view, ".grana-calendar-cell.calendar-count-3")
    assert has_element?(view, ".grana-calendar-score-ring")
    assert html =~ "Menos"
    # Pontuação de cobertura ao lado do calendário
    assert html =~ "Cobertura"
    assert html =~ "importações"
    refute html =~ "Ainda não há dados"
  end

  test "redireciona usuário não autenticado" do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             live(build_conn(), ~p"/upload?tab=calendario")
  end
end
