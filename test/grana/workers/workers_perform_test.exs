defmodule Grana.Workers.WorkersPerformTest do
  use Grana.DataCase, async: false
  use Mimic

  import Grana.AccountsFixtures
  import Grana.BankingFixtures

  alias Grana.Banking
  alias Grana.Workers.AIAnalysisWorker

  # ── AIAnalysisWorker ──────────────────────────────────────────────────────────

  describe "AIAnalysisWorker.perform/1 banking" do
    setup do
      user = user_fixture()
      user = ai_fixture(user)
      Banking.ensure_default_categories(user.id)
      transaction_fixture(user, %{description: "PADARIA", amount: "-50.00"})

      topic = "analysis:#{user.id}:#{System.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(Grana.PubSub, topic)

      %{user: user, topic: topic}
    end

    defp valid_analysis do
      Jason.encode!(%{
        "titulo" => "Análise Financeira",
        "resumo" => "Situação ok",
        "pontos" => [%{"tipo" => "neutro", "texto" => "ponto1"}],
        "nota" => 7.5
      })
    end

    defp analysis_job(user, topic, attrs \\ %{}) do
      %{
        "user_id" => user.id,
        "context" => "banking",
        "filters" => %{"year" => 2026},
        "custom_prompt" => nil,
        "topic" => topic
      }
      |> Map.merge(attrs)
      |> AIAnalysisWorker.new()
      |> Oban.insert!()
    end

    test "successful analysis broadcasts and persists with the model", %{user: user, topic: topic} do
      Grana.LLMStub.script([valid_analysis()])

      assert :ok = AIAnalysisWorker.perform(analysis_job(user, topic))
      assert_receive {:analysis_complete, :ok}, 5_000

      assert [analysis] = Banking.list_ai_analyses(user.id)
      assert analysis.ai_provider == "Google Gemini"
      assert analysis.ai_model == "gemini-test-model"
      assert analysis.result_json["titulo"] == "Análise Financeira"
    end

    test "uses the model picked for the job", %{user: user, topic: topic} do
      Grana.LLMStub.script([valid_analysis()])
      [ref, _model] = user |> Grana.AI.general_choice() |> String.split("|")

      job = analysis_job(user, topic, %{"model" => Grana.AI.choice(ref, "gemini-pro-x")})

      assert :ok = AIAnalysisWorker.perform(job)
      assert [%{ai_model: "gemini-pro-x"}] = Banking.list_ai_analyses(user.id)
    end

    test "banking analysis with all-months filter (month nil)", %{user: user, topic: topic} do
      Grana.LLMStub.script([valid_analysis()])

      job =
        analysis_job(user, topic, %{
          "filters" => %{"year" => 2026, "month" => nil},
          "custom_prompt" => "Onde gastei mais?"
        })

      assert :ok = AIAnalysisWorker.perform(job)
      assert_receive {:analysis_complete, :ok}, 5_000
    end

    test "permanent error (invalid api key) discards job", %{user: user, topic: topic} do
      Grana.LLMStub.script([{:error, "401 api_key inválida"}])

      assert {:discard, _msg} = AIAnalysisWorker.perform(analysis_job(user, topic))
      assert_receive {:analysis_complete, {:error, _}}, 5_000
    end

    test "transient error returns error tuple", %{user: user, topic: topic} do
      Grana.LLMStub.script([{:error, "timeout connecting to server"}])

      assert {:error, _msg} = AIAnalysisWorker.perform(analysis_job(user, topic))
    end

    test "an answer outside the expected JSON is retried", %{user: user, topic: topic} do
      Grana.LLMStub.script(["sem json"])

      assert {:error, "Falha ao processar resposta da IA"} =
               AIAnalysisWorker.perform(analysis_job(user, topic))
    end

    test "an answer with JSON in the wrong shape is discarded", %{user: user, topic: topic} do
      Grana.LLMStub.script([~s({"titulo": "x"})])

      assert {:discard, "Formato de resposta inesperado da IA"} =
               AIAnalysisWorker.perform(analysis_job(user, topic))
    end
  end

  describe "AIAnalysisWorker.perform/1 invalid context" do
    test "invalid context returns error and broadcasts" do
      user = user_fixture()
      topic = "analysis:#{user.id}:#{System.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(Grana.PubSub, topic)

      job =
        AIAnalysisWorker.new(%{
          "user_id" => user.id,
          "context" => "unknown_context",
          "filters" => %{},
          "custom_prompt" => nil,
          "topic" => topic
        })
        |> Oban.insert!()

      result = AIAnalysisWorker.perform(job)
      assert {:discard, _} = result

      assert_receive {:analysis_complete, {:error, _}}, 5_000
    end
  end
end
