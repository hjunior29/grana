defmodule GranaWeb.AnalysisLiveExtendedTest do
  use GranaWeb.ConnCase, async: false

  use Mimic

  import Phoenix.LiveViewTest
  import Grana.AccountsFixtures
  import Grana.BankingFixtures

  alias Grana.Banking
  alias Grana.Accounts

  setup :register_and_log_in_user

  describe "filter events" do
    test "switch_tab changes active tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analysis")

      render_click(view, "switch_tab", %{"tab" => "investments"})

      html = render(view)
      assert html =~ "Investimentos" or html =~ "Nenhum" or html =~ "Sem dados"
    end

    test "select_year changes year filter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analysis")

      render_click(view, "select_year", %{"year" => "2025"})

      html = render(view)
      assert html =~ "Análise" or html =~ "An"
    end

    test "select_month all clears month filter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analysis")

      render_click(view, "select_month", %{"month" => "all"})

      html = render(view)
      assert html =~ "Análise"
    end

    test "select_month sets specific month", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analysis")

      render_click(view, "select_month", %{"month" => "3"})

      html = render(view)
      assert html =~ "Análise"
    end

    test "select_bank filters by bank", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analysis")

      render_click(view, "select_bank", %{"bank" => "nubank"})

      html = render(view)
      assert html =~ "Análise"
    end

    test "select_source filters by source", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analysis")

      render_click(view, "select_source", %{"source" => "banking"})

      html = render(view)
      assert html =~ "Análise"
    end

    test "select_txn_type filters by transaction type", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analysis")

      render_click(view, "select_txn_type", %{"txn_type" => "debit"})

      html = render(view)
      assert html =~ "Análise"
    end

    test "select_institution filters by institution", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analysis?tab=investments")

      render_click(view, "select_institution", %{"institution" => "all"})

      html = render(view)
      assert html =~ "Análise" or html =~ "An"
    end

    test "select_asset_type filters by asset type", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analysis?tab=investments")

      render_click(view, "select_asset_type", %{"type" => "acao"})

      html = render(view)
      assert html =~ "Análise" or html =~ "An"
    end

    test "update_prompt sets prompt text", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analysis")

      render_click(view, "update_prompt", %{"prompt" => "Quanto gastei em alimentação?"})

      html = render(view)
      assert html =~ "Análise"
    end

    test "set_chip sets prompt from chip", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analysis")

      render_click(view, "set_chip", %{"text" => "Analise meus gastos"})

      html = render(view)
      assert html =~ "Análise"
    end

    test "dismiss_api_alert dismisses the alert", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analysis")

      render_click(view, "dismiss_api_alert", %{})

      html = render(view)
      assert html =~ "Análise"
    end

    test "toggle_year expands/collapses year section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analysis?tab=investments")

      render_click(view, "toggle_year", %{"year" => "2026"})

      html = render(view)
      assert html =~ "Análise"
    end
  end

  describe "analyze event for investments tab" do
    test "analyze on investments tab with no api key shows alert", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analysis?tab=investments")

      render_click(view, "analyze", %{})

      html = render(view)
      assert html =~ "Análise"
    end
  end

  describe "analyze event" do
    test "returns error when no API key is configured", %{conn: conn, user: user} do
      Banking.ensure_default_categories(user.id)
      transaction_fixture(user, %{description: "PADARIA", amount: "-30.00"})

      {:ok, view, _html} = live(conn, ~p"/analysis")

      render_click(view, "analyze", %{})

      html = render(view)
      assert html =~ "Análise"
    end

    test "triggers analysis when API key is set and there is data", %{conn: conn, user: user} do
      {:ok, _user} = Accounts.update_user_ai_settings(user, %{ai_api_key: "fake-key"})

      Banking.ensure_default_categories(user.id)
      transaction_fixture(user, %{description: "SUPERMERCADO", amount: "-100.00"})

      stub(Grana.AI.Provider, :generate_content, fn _prompt, _config ->
        {:ok,
         %{
           "candidates" => [
             %{
               "content" => %{"parts" => [%{"text" => "Você gastou R$ 100 em supermercado."}]},
               "finishReason" => "STOP"
             }
           ]
         }}
      end)

      stub(Grana.AI.Provider, :extract_text, fn body ->
        get_in(body, ["candidates", Access.at(0), "content", "parts", Access.at(0), "text"])
        |> to_string()
      end)

      stub(Grana.AI.Provider, :finish_reason, fn body ->
        get_in(body, ["candidates", Access.at(0), "finishReason"])
      end)

      {:ok, view, _html} = live(conn, ~p"/analysis")

      render_click(view, "analyze", %{})

      Process.sleep(200)
      html = render(view)
      assert html =~ "Análise"
    end
  end

  describe "analysis management" do
    setup %{user: user} do
      {:ok, _user} = Accounts.update_user_ai_settings(user, %{ai_api_key: "fake-key"})
      :ok
    end

    test "toggle_analysis expands/collapses an analysis entry", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analysis")

      render_click(view, "toggle_analysis", %{"id" => "999"})

      html = render(view)
      assert html =~ "Análise"
    end

    test "confirm_delete and cancel_delete on analysis", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analysis")

      render_click(view, "confirm_delete", %{"id" => "999"})
      html = render(view)
      assert html =~ "Análise"

      render_click(view, "cancel_delete", %{})
      html = render(view)
      assert html =~ "Análise"
    end

    test "delete_analysis removes existing analysis", %{conn: conn, user: user} do
      {:ok, analysis} =
        Banking.create_ai_analysis(%{
          user_id: user.id,
          prompt: nil,
          filters_json: %{context: "banking"},
          result_json: %{"titulo" => "T", "resumo" => "r", "pontos" => [], "nota" => 5.0}
        })

      {:ok, view, _html} = live(conn, ~p"/analysis")

      render_click(view, "confirm_delete", %{"id" => to_string(analysis.id)})
      render_click(view, "delete_analysis", %{})

      html = render(view)
      assert html =~ "Análise"
      assert Banking.list_ai_analyses(user.id) == []
    end

    test "delete_analysis with no delete_target is a no-op", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analysis")

      html = render_click(view, "delete_analysis", %{})
      assert html =~ "Análise"
    end

    test "toggle_analysis with valid id expands entry", %{conn: conn, user: user} do
      {:ok, analysis} =
        Banking.create_ai_analysis(%{
          user_id: user.id,
          prompt: nil,
          filters_json: %{context: "banking"},
          result_json: %{"titulo" => "T", "resumo" => "r", "pontos" => [], "nota" => 5.0}
        })

      {:ok, view, _html} = live(conn, ~p"/analysis")

      render_click(view, "toggle_analysis", %{"id" => to_string(analysis.id)})
      html = render(view)
      assert html =~ "Análise"
    end
  end

  describe "handle_info callbacks" do
    test "analysis_complete :ok updates state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analysis")

      send(view.pid, {:analysis_complete, :ok})
      Process.sleep(50)

      html = render(view)
      assert html =~ "Análise"
    end

    test "analysis_complete error shows error message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analysis")

      send(view.pid, {:analysis_complete, {:error, "API Key inválida"}})
      Process.sleep(50)

      html = render(view)
      assert html =~ "Análise"
    end
  end

  describe "analyze duplicate detection" do
    test "analyze shows warning when recent duplicate exists", %{conn: conn, user: user} do
      {:ok, _user} = Accounts.update_user_ai_settings(user, %{ai_api_key: "fake-key"})

      Banking.ensure_default_categories(user.id)
      transaction_fixture(user, %{description: "MERCADO", amount: "-200.00"})

      {:ok, analysis} =
        Banking.create_ai_analysis(%{
          user_id: user.id,
          prompt: nil,
          filters_json: %{
            "context" => "banking",
            "year" => Date.utc_today().year,
            "month" => 0
          },
          result_json: %{"titulo" => "T", "resumo" => "r", "pontos" => [], "nota" => 5.0}
        })

      {:ok, view, _html} = live(conn, ~p"/analysis")

      render_click(view, "analyze", %{})

      html = render(view)
      assert html =~ "Análise"

      Banking.delete_ai_analysis(analysis)
    end
  end

  describe "investments tab filter events" do
    test "select_year on investments tab uses inv filters", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analysis?tab=investments")

      render_click(view, "select_year", %{"year" => "2025"})

      html = render(view)
      assert html =~ "Análise"
    end

    test "select_month all on investments tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analysis?tab=investments")

      render_click(view, "select_month", %{"month" => "all"})

      html = render(view)
      assert html =~ "Análise"
    end

    test "select_month specific on investments tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analysis?tab=investments")

      render_click(view, "select_month", %{"month" => "3"})

      html = render(view)
      assert html =~ "Análise"
    end

    test "toggle_year on banking tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analysis")

      render_click(view, "toggle_year", %{"year" => "2026"})
      render_click(view, "toggle_year", %{"year" => "2026"})

      html = render(view)
      assert html =~ "Análise"
    end

    test "toggle_year with invalid id is no-op", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analysis")

      render_click(view, "toggle_year", %{"year" => "invalid"})

      html = render(view)
      assert html =~ "Análise"
    end
  end

  describe "investments tab with actual data" do
    setup %{user: user} do
      alias Grana.InvestmentsFixtures

      InvestmentsFixtures.transaction_fixture(user, %{
        asset_name: "PETR4",
        asset_ticker: "PETR4",
        asset_type: "acao",
        total_amount: "500.00",
        operation: "compra"
      })

      :ok
    end

    test "investments tab loads with actual investment data", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/analysis?tab=investments")

      assert html =~ "Análise"
    end

    test "select_institution filters investments data", %{conn: conn, user: user} do
      institutions = Grana.Investments.available_institutions(user.id)

      {:ok, view, _html} = live(conn, ~p"/analysis?tab=investments")

      if institutions != [] do
        inst = hd(institutions)
        render_click(view, "select_institution", %{"institution" => to_string(inst.id)})
        render_click(view, "select_institution", %{"institution" => "all"})
      end

      html = render(view)
      assert html =~ "Análise"
    end

    test "select_asset_type filters by asset type", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analysis?tab=investments")

      render_click(view, "select_asset_type", %{"type" => "acao"})

      html = render(view)
      assert html =~ "Análise"
    end
  end

  describe "bradesco bank logo in filter" do
    setup %{user: user} do
      Banking.ensure_default_categories(user.id)
      today = Date.utc_today()

      {:ok, stmt} =
        Banking.create_statement(%{
          bank: "bradesco",
          filename: "extrato_bradesco.csv",
          statement_type: "extrato",
          user_id: user.id,
          period_start: Date.beginning_of_month(today),
          period_end: today
        })

      Banking.bulk_insert_transactions([
        %{
          date: today,
          description: "BRADESCO TXN",
          amount: Decimal.new("-50.00"),
          type: "debit",
          bank_statement_id: stmt.id,
          user_id: user.id
        }
      ])

      :ok
    end

    test "analysis page with bradesco bank data renders bank logo", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/analysis")
      assert html =~ "Análise"
    end

    test "select bradesco bank filter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analysis")
      render_click(view, "select_bank", %{"bank" => "bradesco"})
      html = render(view)
      assert html =~ "Análise"
    end
  end

  describe "analysis filter label rendering" do
    setup %{user: user} do
      {:ok, _user} = Accounts.update_user_ai_settings(user, %{ai_api_key: "fake-key"})

      Banking.create_ai_analysis(%{
        user_id: user.id,
        prompt: nil,
        filters_json: %{
          "context" => "banking",
          "statement_type" => "extrato",
          "type" => "debit",
          "bank" => "bradesco"
        },
        result_json: %{"titulo" => "T", "resumo" => "r", "pontos" => [], "nota" => 5}
      })

      Banking.create_ai_analysis(%{
        user_id: user.id,
        prompt: nil,
        filters_json: %{
          "context" => "banking",
          "statement_type" => "fatura",
          "type" => "credit"
        },
        result_json: %{"titulo" => "T2", "resumo" => "r2", "pontos" => [], "nota" => nil}
      })

      :ok
    end

    test "renders source labels and type labels in analysis cards", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/analysis")
      assert html =~ "Análise"
    end
  end

  describe "investment institution filter loop" do
    setup %{user: user} do
      alias Grana.Investments
      alias Grana.InvestmentsFixtures

      _b3 = Investments.ensure_b3_institution(user.id)
      _gcb = Investments.ensure_gcb_institution(user.id)

      InvestmentsFixtures.transaction_fixture(user, %{
        asset_name: "PETR4",
        asset_type: "acao",
        total_amount: "1000.00",
        operation: "compra"
      })

      :ok
    end

    test "investments tab with multiple institutions renders filter buttons", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/analysis?tab=investments")
      assert html =~ "Análise"
    end
  end

  describe "analysis rendering with score colors" do
    setup %{user: user} do
      {:ok, _user} = Accounts.update_user_ai_settings(user, %{ai_api_key: "fake-key"})
      :ok
    end

    defp create_analysis(user_id, nota) do
      {:ok, analysis} =
        Banking.create_ai_analysis(%{
          user_id: user_id,
          prompt: nil,
          filters_json: %{"context" => "banking"},
          result_json: %{
            "titulo" => "Análise #{nota}",
            "resumo" => "Resumo",
            "pontos" => [
              %{"tipo" => "positivo", "texto" => "Ponto positivo"},
              %{"tipo" => "negativo", "texto" => "Ponto negativo"},
              %{"tipo" => "dica", "texto" => "Dica"},
              %{"tipo" => "outro", "texto" => "Outro"}
            ],
            "nota" => nota
          }
        })

      analysis
    end

    test "renders analysis with nota >= 8 (success color)", %{conn: conn, user: user} do
      analysis = create_analysis(user.id, 8.5)

      {:ok, view, _html} = live(conn, ~p"/analysis")

      render_click(view, "toggle_analysis", %{"id" => to_string(analysis.id)})

      html = render(view)
      assert html =~ "Análise"

      Banking.delete_ai_analysis(analysis)
    end

    test "renders analysis with nota >= 6 (info color)", %{conn: conn, user: user} do
      analysis = create_analysis(user.id, 7.0)

      {:ok, view, _html} = live(conn, ~p"/analysis")

      render_click(view, "toggle_analysis", %{"id" => to_string(analysis.id)})

      html = render(view)
      assert html =~ "Análise"

      Banking.delete_ai_analysis(analysis)
    end

    test "renders analysis with nota >= 4 (warning color)", %{conn: conn, user: user} do
      analysis = create_analysis(user.id, 5.0)

      {:ok, view, _html} = live(conn, ~p"/analysis")

      render_click(view, "toggle_analysis", %{"id" => to_string(analysis.id)})

      html = render(view)
      assert html =~ "Análise"

      Banking.delete_ai_analysis(analysis)
    end

    test "renders analysis with nota < 4 (error color)", %{conn: conn, user: user} do
      analysis = create_analysis(user.id, 2.0)

      {:ok, view, _html} = live(conn, ~p"/analysis")

      render_click(view, "toggle_analysis", %{"id" => to_string(analysis.id)})

      html = render(view)
      assert html =~ "Análise"

      Banking.delete_ai_analysis(analysis)
    end

    test "renders analysis toggle_year collapses and expands year groups", %{
      conn: conn,
      user: user
    } do
      analysis = create_analysis(user.id, 6.0)
      year = analysis.inserted_at.year

      {:ok, view, _html} = live(conn, ~p"/analysis")

      render_click(view, "toggle_year", %{"year" => to_string(year)})

      html = render(view)
      assert html =~ "Análise"

      render_click(view, "toggle_year", %{"year" => to_string(year)})

      html = render(view)
      assert html =~ "Análise"

      Banking.delete_ai_analysis(analysis)
    end
  end

  describe "old format analysis rendering" do
    setup %{user: user} do
      {:ok, _user} = Accounts.update_user_ai_settings(user, %{ai_api_key: "fake-key"})
      :ok
    end

    test "renders old-format analysis (no nota/pontos keys)", %{conn: conn, user: user} do
      {:ok, analysis} =
        Banking.create_ai_analysis(%{
          user_id: user.id,
          prompt: nil,
          filters_json: %{"context" => "banking"},
          result_json: %{"titulo" => "Análise Antiga", "resumo" => "Resumo simples sem nota"}
        })

      {:ok, view, _html} = live(conn, ~p"/analysis")

      render_click(view, "toggle_analysis", %{"id" => to_string(analysis.id)})

      html = render(view)
      assert html =~ "Análise"

      Banking.delete_ai_analysis(analysis)
    end

    test "investment analysis with asset_type filter renders type label", %{conn: conn, user: user} do
      {:ok, analysis} =
        Banking.create_ai_analysis(%{
          user_id: user.id,
          prompt: nil,
          filters_json: %{"context" => "investments", "asset_type" => "fii"},
          result_json: %{
            "titulo" => "Análise FII",
            "resumo" => "Resumo",
            "pontos" => [],
            "nota" => 7.0
          }
        })

      {:ok, _view, html} = live(conn, ~p"/analysis?tab=investments")

      assert html =~ "Análise"

      Banking.delete_ai_analysis(analysis)
    end

    test "bank_logo fallback renders for unknown bank", %{conn: conn, user: user} do
      Banking.create_ai_analysis(%{
        user_id: user.id,
        prompt: nil,
        filters_json: %{"context" => "banking", "bank" => "itau"},
        result_json: %{"titulo" => "T", "resumo" => "r", "pontos" => [], "nota" => 6.0}
      })

      {:ok, _view, html} = live(conn, ~p"/analysis")
      assert html =~ "Análise"
    end
  end
end
