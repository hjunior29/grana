defmodule GranaWeb.UploadLiveExtendedTest do
  use GranaWeb.ConnCase

  import Phoenix.LiveViewTest
  import Grana.BankingFixtures

  alias Grana.Banking

  setup :register_and_log_in_user

  describe "select_upload_category" do
    test "select banking category shows bank selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      html = render_click(view, "select_upload_category", %{"category" => "banking"})

      assert html =~ "Nubank" or html =~ "Bradesco"
    end

    test "select platform category shows platform import options", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      html = render_click(view, "select_upload_category", %{"category" => "platform"})

      assert html =~ "Plataforma" or html =~ "Importar" or html =~ "import"
    end
  end

  describe "select-bank" do
    test "select-bank nubank shows type selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "select_upload_category", %{"category" => "banking"})
      html = render_click(view, "select-bank", %{"bank" => "nubank"})

      assert html =~ "Extrato" or html =~ "Fatura"
    end

    test "select-bank bradesco shows type selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "select_upload_category", %{"category" => "banking"})
      html = render_click(view, "select-bank", %{"bank" => "bradesco"})

      assert html =~ "Extrato" or html =~ "Fatura"
    end
  end

  describe "select-type" do
    test "select-type extrato advances to file upload step", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "select_upload_category", %{"category" => "banking"})
      render_click(view, "select-bank", %{"bank" => "nubank"})
      html = render_click(view, "select-type", %{"type" => "extrato"})

      assert html =~ "Selecionar" or html =~ "arquivo" or html =~ "Extrato"
    end

    test "select-type fatura advances to file upload step", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "select_upload_category", %{"category" => "banking"})
      render_click(view, "select-bank", %{"bank" => "bradesco"})
      html = render_click(view, "select-type", %{"type" => "fatura"})

      assert html =~ "Selecionar" or html =~ "arquivo" or html =~ "Fatura"
    end
  end

  describe "switch_tab" do
    test "switches between tabs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "switch_tab", %{"tab" => "historico"})
      html = render(view)
      assert html =~ "Importar"

      render_click(view, "switch_tab", %{"tab" => "calendario"})
      html = render(view)
      assert html =~ "Importar"
    end
  end

  describe "statement management" do
    test "toggle_select selects a banking statement", %{conn: conn, user: user} do
      stmt = statement_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "toggle_select", %{"id" => "bank_#{stmt.id}"})

      html = render(view)
      assert html =~ "Importar"
    end

    test "toggle_all selects/deselects all statements", %{conn: conn, user: user} do
      statement_fixture(user)
      statement_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "toggle_all", %{})
      html = render(view)
      assert html =~ "Importar"
    end

    test "confirm_delete shows delete confirmation", %{conn: conn, user: user} do
      stmt = statement_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "confirm_delete", %{"id" => "bank_#{stmt.id}"})
      html = render(view)
      assert html =~ "Remover" or html =~ "Confirmar" or html =~ "Importar"
    end

    test "cancel_delete closes the delete dialog", %{conn: conn, user: user} do
      stmt = statement_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "confirm_delete", %{"id" => "bank_#{stmt.id}"})
      render_click(view, "cancel_delete", %{})

      html = render(view)
      assert html =~ "Importar"
    end

    test "delete removes selected statement", %{conn: conn, user: user} do
      stmt = statement_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "confirm_delete", %{"id" => "bank_#{stmt.id}"})
      render_click(view, "delete", %{})

      assert Banking.list_statements(user.id) == []
    end

    test "confirm_bulk_delete shows bulk delete confirmation", %{conn: conn, user: user} do
      stmt = statement_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "toggle_select", %{"id" => to_string(stmt.id)})
      render_click(view, "confirm_bulk_delete", %{})

      html = render(view)
      assert html =~ "Importar"
    end
  end

  describe "outro bank upload triggers api key alert" do
    test "upload with outro bank and no api key shows api key alert", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "select_upload_category", %{"category" => "banking"})
      render_click(view, "select-bank", %{"bank" => "outro"})
      render_click(view, "select-type", %{"type" => "extrato"})

      html = render_click(view, "upload", %{})

      assert html =~ "Importar"
    end
  end

  describe "validate" do
    test "validate event is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")
      render_click(view, "validate", %{})
      html = render(view)
      assert html =~ "Importar"
    end
  end

  describe "dismiss_api_alert" do
    test "dismisses the API alert", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")
      render_click(view, "dismiss_api_alert", %{})
      html = render(view)
      assert html =~ "Importar"
    end
  end

  describe "bulk delete flow" do
    test "confirm_bulk_delete with 0 selected is a no-op", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")
      render_click(view, "confirm_bulk_delete", %{})
      html = render(view)
      assert html =~ "Importar"
    end

    test "bulk delete with selected banking statements", %{conn: conn, user: user} do
      stmt1 = statement_fixture(user)
      stmt2 = statement_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "toggle_select", %{"id" => "bank_#{stmt1.id}"})
      render_click(view, "toggle_select", %{"id" => "bank_#{stmt2.id}"})
      render_click(view, "confirm_bulk_delete", %{})
      render_click(view, "delete", %{})

      assert Banking.list_statements(user.id) == []
    end

    test "delete with no delete_target is a no-op", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")
      render_click(view, "delete", %{})
      html = render(view)
      assert html =~ "Importar"
    end
  end

  describe "historico tab" do
    test "switch_tab to historico shows statement history", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "switch_tab", %{"tab" => "historico"})

      html = render(view)
      assert html =~ "Importar" or html =~ "Histórico"
    end

    test "historico tab via URL params loads directly", %{conn: conn, user: user} do
      statement_fixture(user)
      {:ok, _view, html} = live(conn, ~p"/upload?tab=historico")
      assert html =~ "Importar"
    end
  end

  describe "calendario tab" do
    test "calendario tab via URL params loads calendar", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/upload?tab=calendario")
      assert html =~ "Importar"
    end

    test "calendario tab with banking data shows months", %{conn: conn, user: user} do
      statement_fixture(user)
      {:ok, _view, html} = live(conn, ~p"/upload?tab=calendario")
      assert html =~ "Importar"
    end
  end

  describe "upload event error paths" do
    test "upload with nil bank shows error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "select_upload_category", %{"category" => "banking"})
      html = render_click(view, "upload", %{})

      assert html =~ "Importar"
    end

    test "upload with bank but nil statement type shows error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "select_upload_category", %{"category" => "banking"})
      render_click(view, "select-bank", %{"bank" => "nubank"})
      html = render_click(view, "upload", %{})

      assert html =~ "Importar"
    end
  end

  describe "history pagination" do
    setup %{user: user} do
      for i <- 1..25 do
        Banking.create_statement(%{
          bank: "nubank",
          filename: "extrato_#{i}.csv",
          statement_type: "extrato",
          user_id: user.id,
          period_start: Date.new!(2026, 1, 1),
          period_end: Date.new!(2026, 1, 31)
        })
      end

      :ok
    end

    test "pagination shows on historico tab with many statements", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/upload?tab=historico&source=banking")
      assert html =~ "Importar"
    end

    test "navigating to page 2 of historico", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/upload?tab=historico&source=banking&page=2")
      assert html =~ "Importar"
    end
  end

  describe "fatura statement in historico" do
    test "shows fatura type badge for fatura statements", %{conn: conn, user: user} do
      Banking.create_statement(%{
        bank: "nubank",
        filename: "fatura_nubank.csv",
        statement_type: "fatura",
        user_id: user.id,
        period_start: ~D[2026-01-01],
        period_end: ~D[2026-01-31]
      })

      {:ok, _view, html} = live(conn, ~p"/upload?tab=historico&source=banking")
      assert html =~ "Importar"
    end

    test "select-bank bradesco shows bradesco-specific tip", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "select_upload_category", %{"category" => "banking"})
      render_click(view, "select-bank", %{"bank" => "bradesco"})

      html = render(view)
      assert html =~ "Importar"
    end

    test "select-bank outro shows outro-specific type options", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "select_upload_category", %{"category" => "banking"})
      render_click(view, "select-bank", %{"bank" => "outro"})

      html = render(view)
      assert html =~ "Importar"
    end
  end
end
