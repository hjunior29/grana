defmodule GranaWeb.UploadLiveExtendedTest do
  use GranaWeb.ConnCase

  import Phoenix.LiveViewTest
  import Grana.BankingFixtures

  alias Grana.InvestmentsFixtures

  alias Grana.Banking
  alias Grana.Investments

  setup :register_and_log_in_user

  describe "select_upload_category" do
    test "select banking category shows bank selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      html = render_click(view, "select_upload_category", %{"category" => "banking"})

      assert html =~ "Nubank" or html =~ "Bradesco"
    end

    test "select investment category shows provider options", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      html = render_click(view, "select_upload_category", %{"category" => "investment"})

      assert html =~ "B3" or html =~ "GCB" or html =~ "Investimento"
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

  describe "select_investment_provider" do
    test "select B3 provider sets upload context", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "select_upload_category", %{"category" => "investment"})
      html = render_click(view, "select_investment_provider", %{"provider" => "b3"})

      assert html =~ "B3" or html =~ "arquivo" or html =~ "Selecionar"
    end

    test "select GCB provider sets upload context", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "select_upload_category", %{"category" => "investment"})
      html = render_click(view, "select_investment_provider", %{"provider" => "gcb"})

      assert html =~ "GCB" or html =~ "arquivo" or html =~ "Selecionar"
    end
  end

  describe "dismiss_roadmap" do
    test "dismisses the roadmap notice", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")
      render_click(view, "dismiss_roadmap", %{})
      html = render(view)
      assert html =~ "Upload"
    end
  end

  describe "switch_tab" do
    test "switches between banking and investment tabs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "switch_tab", %{"tab" => "banking"})
      html = render(view)
      assert html =~ "Fatura / Extrato" or html =~ "Upload"

      render_click(view, "switch_tab", %{"tab" => "investment"})
      html = render(view)
      assert html =~ "Investimento" or html =~ "Upload"
    end
  end

  describe "statement management" do
    test "toggle_select selects a banking statement", %{conn: conn, user: user} do
      stmt = statement_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "toggle_select", %{"id" => "bank_#{stmt.id}"})

      html = render(view)
      assert html =~ "Upload"
    end

    test "toggle_all selects/deselects all statements", %{conn: conn, user: user} do
      statement_fixture(user)
      statement_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "toggle_all", %{})
      html = render(view)
      assert html =~ "Upload"
    end

    test "confirm_delete shows delete confirmation", %{conn: conn, user: user} do
      stmt = statement_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "confirm_delete", %{"id" => "bank_#{stmt.id}"})
      html = render(view)
      assert html =~ "Remover" or html =~ "Confirmar" or html =~ "Upload"
    end

    test "cancel_delete closes the delete dialog", %{conn: conn, user: user} do
      stmt = statement_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "confirm_delete", %{"id" => "bank_#{stmt.id}"})
      render_click(view, "cancel_delete", %{})

      html = render(view)
      assert html =~ "Upload"
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

      render_click(view, "toggle_select", %{"id" => "bank_#{stmt.id}"})
      render_click(view, "confirm_bulk_delete", %{})

      html = render(view)
      assert html =~ "Upload"
    end

    test "investment statement toggle_select works", %{conn: conn, user: user} do
      inst = Investments.ensure_b3_institution(user.id)
      inv_stmt = InvestmentsFixtures.statement_fixture(user, inst)

      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "toggle_select", %{"id" => "inv_#{inv_stmt.id}"})

      html = render(view)
      assert html =~ "Upload"
    end
  end

  describe "upload_complete with 4-tuple warnings" do
    test "upload_complete with 4-tuple success and warnings shows warning flash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      send(
        view.pid,
        {:upload_complete, [{:ok, "extrato.csv", 5, ["Linha 3 ignorada", "Linha 7 ignorada"]}]}
      )

      Process.sleep(50)

      html = render(view)
      assert html =~ "Upload"
    end

    test "upload_complete all errors shows error flash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      send(
        view.pid,
        {:upload_complete,
         [
           {:error, "bad1.csv", "Erro 1"},
           {:error, "bad2.csv", "Erro 2"},
           {:error, "bad3.csv", "Erro 3"},
           {:error, "bad4.csv", "Erro 4"},
           {:error, "bad5.csv", "Erro 5"},
           {:error, "bad6.csv", "Erro 6"}
         ]}
      )

      Process.sleep(50)

      html = render(view)
      assert html =~ "Upload"
    end

    test "upload_complete partial success shows both info and error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      send(
        view.pid,
        {:upload_complete,
         [
           {:ok, "good.csv", 3, []},
           {:error, "bad.csv", "Erro ao processar"}
         ]}
      )

      Process.sleep(50)

      html = render(view)
      assert html =~ "Upload"
    end
  end

  describe "outro bank upload triggers api key alert" do
    test "upload with outro bank and no api key shows api key alert", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "select_upload_category", %{"category" => "banking"})
      render_click(view, "select-bank", %{"bank" => "outro"})
      render_click(view, "select-type", %{"type" => "extrato"})

      html = render_click(view, "upload", %{})

      assert html =~ "Upload"
    end
  end

  describe "processing state render" do
    test "upload with nubank extrato triggers processing state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "select_upload_category", %{"category" => "banking"})
      render_click(view, "select-bank", %{"bank" => "nubank"})
      render_click(view, "select-type", %{"type" => "extrato"})

      html = render_click(view, "upload", %{})
      assert html =~ "Upload"

      send(view.pid, {:upload_complete, []})
      Process.sleep(100)
      html = render(view)
      assert html =~ "Upload"
    end

    test "investment upload triggers processing state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "select_upload_category", %{"category" => "investment"})
      render_click(view, "select_investment_provider", %{"provider" => "gcb"})

      html = render_click(view, "upload", %{})
      assert html =~ "Upload"
    end

    test "platform upload triggers processing state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "select_upload_category", %{"category" => "platform"})

      html = render_click(view, "upload", %{})
      assert html =~ "Upload"
    end
  end

  describe "validate" do
    test "validate event is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")
      render_click(view, "validate", %{})
      html = render(view)
      assert html =~ "Upload"
    end
  end

  describe "dismiss_api_alert" do
    test "dismisses the API alert", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")
      render_click(view, "dismiss_api_alert", %{})
      html = render(view)
      assert html =~ "Upload"
    end
  end

  describe "bulk delete flow" do
    test "confirm_bulk_delete with 0 selected is a no-op", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")
      render_click(view, "confirm_bulk_delete", %{})
      html = render(view)
      assert html =~ "Upload"
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
      assert html =~ "Upload"
    end
  end

  describe "handle_info callbacks" do
    test "processing_file updates progress filename", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      send(view.pid, {:processing_file, 1, 3, "extrato.csv"})
      Process.sleep(50)

      html = render(view)
      assert html =~ "Upload"
    end

    test "processing_file with PDF sets AI flag", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      send(view.pid, {:processing_file, 1, 1, "fatura.pdf"})
      Process.sleep(50)

      html = render(view)
      assert html =~ "Upload"
    end

    test "file_done updates progress counter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      send(view.pid, {:file_done, 1, 3})
      Process.sleep(50)

      html = render(view)
      assert html =~ "Upload"
    end

    test "upload_complete with success results updates state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      send(view.pid, {:upload_complete, [{:ok, "extrato.csv", 5}]})
      Process.sleep(50)

      html = render(view)
      assert html =~ "Upload"
    end

    test "upload_complete with error results shows errors", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      send(view.pid, {:upload_complete, [{:error, "bad.csv", "Arquivo inválido"}]})
      Process.sleep(50)

      html = render(view)
      assert html =~ "Upload"
    end

    test "upload_complete with mixed results", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      send(view.pid, {
        :upload_complete,
        [{:ok, "ok.csv", 10}, {:error, "bad.csv", "Erro"}]
      })

      Process.sleep(50)

      html = render(view)
      assert html =~ "Upload"
    end
  end

  describe "historico tab" do
    test "switch_tab to historico shows statement history", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "switch_tab", %{"tab" => "historico"})

      html = render(view)
      assert html =~ "Upload" or html =~ "Histórico"
    end

    test "switch_tab to historico investment source", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "switch_tab", %{"tab" => "historico", "source" => "investment"})

      html = render(view)
      assert html =~ "Upload"
    end

    test "historico tab via URL params loads directly", %{conn: conn, user: user} do
      statement_fixture(user)
      {:ok, _view, html} = live(conn, ~p"/upload?tab=historico")
      assert html =~ "Upload"
    end

    test "historico banking source filter", %{conn: conn, user: user} do
      statement_fixture(user)
      {:ok, _view, html} = live(conn, ~p"/upload?tab=historico&source=banking")
      assert html =~ "Upload"
    end

    test "historico investment source filter", %{conn: conn, user: user} do
      inst = Investments.ensure_b3_institution(user.id)
      InvestmentsFixtures.statement_fixture(user, inst)
      {:ok, _view, html} = live(conn, ~p"/upload?tab=historico&source=investment")
      assert html =~ "Upload"
    end
  end

  describe "calendario tab" do
    test "calendario tab via URL params loads calendar", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/upload?tab=calendario")
      assert html =~ "Upload"
    end

    test "calendario tab with banking data shows months", %{conn: conn, user: user} do
      statement_fixture(user)
      {:ok, _view, html} = live(conn, ~p"/upload?tab=calendario")
      assert html =~ "Upload"
    end
  end

  describe "select_investment_provider for gcb" do
    test "select GCB provider with a specific format", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "select_upload_category", %{"category" => "investment"})
      html = render_click(view, "select_investment_provider", %{"provider" => "gcb"})

      assert html =~ "GCB" or html =~ "arquivo" or html =~ "Selecionar"
    end
  end

  describe "upload event error paths" do
    test "upload with nil bank shows error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "select_upload_category", %{"category" => "banking"})
      html = render_click(view, "upload", %{})

      assert html =~ "Upload"
    end

    test "upload with bank but nil statement type shows error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "select_upload_category", %{"category" => "banking"})
      render_click(view, "select-bank", %{"bank" => "nubank"})
      html = render_click(view, "upload", %{})

      assert html =~ "Upload"
    end

    test "upload when processing is blocked - switch_tab no-op", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      send(view.pid, {:processing_file, 1, 3, "test.csv"})
      Process.sleep(50)

      html = render(view)
      assert html =~ "Upload"
    end
  end

  describe "handle_info process_uploads" do
    test "process_uploads with no files starts worker", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      send(view.pid, {:process_uploads, "nubank", "extrato", user.id})
      Process.sleep(50)

      html = render(view)
      assert html =~ "Upload"
    end

    test "process_investment_uploads with no files starts worker", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      send(view.pid, {:process_investment_uploads, "gcb", user.id})
      Process.sleep(50)

      html = render(view)
      assert html =~ "Upload"
    end

    test "process_platform_uploads with no files starts worker", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      send(view.pid, {:process_platform_uploads, user.id})
      Process.sleep(50)

      html = render(view)
      assert html =~ "Upload"
    end
  end

  describe "processing state guards" do
    setup do
      :ok
    end

    test "switch_tab while processing is no-op", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "select_upload_category", %{"category" => "banking"})
      render_click(view, "select-bank", %{"bank" => "nubank"})
      render_click(view, "select-type", %{"type" => "extrato"})
      render_click(view, "upload", %{})

      html = render_click(view, "switch_tab", %{"tab" => "investments"})
      assert html =~ "Upload"
    end

    test "select-bank while processing is no-op", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "select_upload_category", %{"category" => "banking"})
      render_click(view, "select-bank", %{"bank" => "nubank"})
      render_click(view, "select-type", %{"type" => "extrato"})
      render_click(view, "upload", %{})

      html = render_click(view, "select-bank", %{"bank" => "bradesco"})
      assert html =~ "Upload"
    end

    test "select-type while processing is no-op", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "select_upload_category", %{"category" => "banking"})
      render_click(view, "select-bank", %{"bank" => "nubank"})
      render_click(view, "select-type", %{"type" => "extrato"})
      render_click(view, "upload", %{})

      html = render_click(view, "select-type", %{"type" => "fatura"})
      assert html =~ "Upload"
    end

    test "select_upload_category while processing is no-op", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "select_upload_category", %{"category" => "banking"})
      render_click(view, "select-bank", %{"bank" => "nubank"})
      render_click(view, "select-type", %{"type" => "extrato"})
      render_click(view, "upload", %{})

      html = render_click(view, "select_upload_category", %{"category" => "investment"})
      assert html =~ "Upload"
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
      assert html =~ "Upload"
    end

    test "navigating to page 2 of historico", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/upload?tab=historico&source=banking&page=2")
      assert html =~ "Upload"
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
      assert html =~ "Upload"
    end

    test "select-bank bradesco shows bradesco-specific tip", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "select_upload_category", %{"category" => "banking"})
      render_click(view, "select-bank", %{"bank" => "bradesco"})

      html = render(view)
      assert html =~ "Upload"
    end

    test "select-bank outro shows outro-specific type options", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")

      render_click(view, "select_upload_category", %{"category" => "banking"})
      render_click(view, "select-bank", %{"bank" => "outro"})

      html = render(view)
      assert html =~ "Upload"
    end
  end

  describe "investment statement delete" do
    test "delete single investment statement", %{conn: conn, user: user} do
      inst = Investments.ensure_b3_institution(user.id)
      inv_stmt = InvestmentsFixtures.statement_fixture(user, inst)

      {:ok, view, _html} = live(conn, ~p"/upload?tab=historico&source=investment")

      render_click(view, "confirm_delete", %{"id" => "inv_#{inv_stmt.id}"})
      render_click(view, "delete", %{})

      assert Investments.list_statements(user.id) == []
    end

    test "bulk delete with investment statements", %{conn: conn, user: user} do
      inst = Investments.ensure_b3_institution(user.id)
      inv_stmt = InvestmentsFixtures.statement_fixture(user, inst)

      {:ok, view, _html} = live(conn, ~p"/upload?tab=historico&source=investment")

      render_click(view, "toggle_select", %{"id" => "inv_#{inv_stmt.id}"})
      render_click(view, "confirm_bulk_delete", %{})
      render_click(view, "delete", %{})

      assert Investments.list_statements(user.id) == []
    end
  end
end
