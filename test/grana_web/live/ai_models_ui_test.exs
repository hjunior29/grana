defmodule GranaWeb.AiModelsUiTest do
  use GranaWeb.ConnCase, async: false
  use Mimic
  use Oban.Testing, repo: Grana.Repo, engine: Oban.Engines.Lite

  import Phoenix.LiveViewTest
  import Grana.AccountsFixtures
  import Grana.BankingFixtures

  alias Grana.AI
  alias Grana.LLMStub
  alias Grana.Workers.StatementUploadWorker

  setup :register_and_log_in_user
  setup :set_mimic_global

  setup %{user: user} do
    stub(AI.Models, :list, fn _config -> {:ok, [%{id: "gemini-pro", name: "Gemini Pro"}]} end)
    user = ai_fixture(user)
    [ref, _model] = user |> AI.general_choice() |> String.split("|")
    %{user: user, pro: AI.choice(ref, "gemini-pro")}
  end

  describe "analysis" do
    setup %{user: user} do
      transaction_fixture(user, %{description: "MERCADO", amount: "-80.00", date: ~D[2026-03-10]})
      Grana.Analyses.subscribe(user.id)
      on_exit(fn -> Grana.Analyses.clear(user.id, 2026, 3) end)
      :ok
    end

    test "the picked model goes with the run and the analysis shows who made it", %{
      conn: conn,
      user: user,
      pro: pro
    } do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      render_async(view)

      assert has_element?(view, "#analysis-model option", "Padrão · gemini-test-model")

      LLMStub.script([
        Jason.encode!(%{"nota" => 8, "titulo" => "Bom mês", "resumo" => "Ok.", "pontos" => []})
      ])

      view |> form("#analysis-form", %{"model" => pro}) |> render_submit()
      assert_receive {:agent_run, {:analysis, 2026, 3}, {:done, _}}, 5_000

      assert %{ai_model: "gemini-pro"} = Grana.Analyses.latest(user.id, 2026, 3)
      assert has_element?(view, "#analysis-toggle", "gemini-pro")
    end
  end

  describe "upload" do
    test "the picked model goes with each file job", %{conn: conn, pro: pro} do
      {:ok, view, _html} = live(conn, ~p"/upload")
      render_async(view)
      render_click(view, "select_upload_category", %{"category" => "banking"})
      render_click(view, "select-bank", %{"bank" => "nubank"})
      render_click(view, "select-type", %{"type" => "extrato"})

      assert has_element?(view, "#upload-form #upload-model option", "Padrão · gemini-test-model")

      view
      |> file_input("#upload-form", :statements, [
        %{name: "extrato.pdf", content: "%PDF", type: "application/pdf"}
      ])
      |> render_upload("extrato.pdf")

      view |> form("#upload-form", %{"model" => pro}) |> render_change()
      view |> form("#upload-form", %{"model" => pro}) |> render_submit()

      assert_enqueued(worker: StatementUploadWorker, args: %{"model" => pro, "bank" => "nubank"})
      File.rm_rf!(Path.join(Grana.DataDir.tmp_dir(), "imports"))
    end

    test "the history shows the model that processed a statement", %{conn: conn, user: user} do
      by_ai =
        statement_fixture(user, %{
          filename: "ia.pdf",
          ai_provider: "Google Gemini",
          ai_model: "gemini-pro"
        })

      by_rules = statement_fixture(user, %{filename: "regras.csv"})
      transaction_fixture(user, %{bank_statement_id: by_rules.id})

      {:ok, view, _html} = live(conn, ~p"/upload?tab=historico")

      assert has_element?(view, "#statement-model-#{by_ai.id}", "gemini-pro")
      refute has_element?(view, "#statement-model-#{by_rules.id}")
    end

    test "the platform import has no model picker", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upload")
      render_click(view, "select_upload_category", %{"category" => "platform"})

      refute has_element?(view, "#upload-model")
    end
  end

  describe "settings" do
    test "each specialist gets its own default model", %{conn: conn, user: user, pro: pro} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render_async(view)

      assert has_element?(
               view,
               "#ai-specialist-analysis option[value='']",
               "Padrão geral · gemini-test-model"
             )

      assert has_element?(
               view,
               "#ai-specialist-chat optgroup[label='Google Gemini'] option",
               "Gemini Pro"
             )

      view
      |> form("#ai-specialists-form", %{"specialists" => %{"analysis" => pro, "chat" => ""}})
      |> render_submit()

      assert render(view) =~ "Modelos dos especialistas salvos."
      assert has_element?(view, "#ai-specialist-analysis option[selected][value='#{pro}']")

      user = Grana.Repo.reload!(user)
      assert user.ai_specialists == %{"analysis" => pro}
      assert {:ok, %{model: "gemini-pro"}} = AI.resolve(user, "analysis")
    end

    test "a saved choice stays visible when the API stops listing the model", %{
      conn: conn,
      user: user
    } do
      [ref, _model] = user |> AI.general_choice() |> String.split("|")
      {:ok, _user} = AI.set_specialist_default(user, "search", AI.choice(ref, "gemini-old"))

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render_async(view)

      assert has_element?(view, "#ai-specialist-search option[selected]", "gemini-old")
    end

    test "without providers there is no specialists section", %{conn: conn} do
      Grana.Repo.delete_all(Grana.AI.ProviderConfig)
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      refute has_element?(view, "#ai-specialists")
    end
  end
end
