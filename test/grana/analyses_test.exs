defmodule Grana.AnalysesTest do
  use Grana.DataCase, async: false
  use Mimic

  setup :set_mimic_global

  import Grana.AccountsFixtures
  import Grana.BankingFixtures

  alias Grana.Analyses
  alias Grana.Banking
  alias Grana.LLMStub

  setup do
    user = user_fixture() |> ai_fixture()
    transaction_fixture(user, %{description: "MERCADO", amount: "-80.00", date: ~D[2026-03-10]})
    Analyses.subscribe(user.id)
    on_exit(fn -> Analyses.clear(user.id, 2026, 3) end)
    %{user: user}
  end

  defp answer(title) do
    Jason.encode!(%{
      "nota" => 7.5,
      "titulo" => title,
      "resumo" => "Mês sob controle.",
      "pontos" => [%{"tipo" => "positivo", "texto" => "Sobrou R$ 100,00."}]
    })
  end

  test "analyzes the period in the background and saves it with the model", %{user: user} do
    LLMStub.script([answer("Bom mês")])

    assert {:ok, :started} = Analyses.request(user.id, 2026, 3)
    assert %{outcome: nil} = Analyses.in_progress(user.id, 2026, 3)
    assert_receive {:agent_run, {:analysis, 2026, 3}, {:done, _}}, 5_000

    assert %{year: 2026, month: 3, ai_model: "gemini-test-model"} =
             analysis = Analyses.latest(user.id, 2026, 3)

    assert analysis.result_json["titulo"] == "Bom mês"
    assert Analyses.latest(user.id, 2026, 0) == nil
  end

  test "the whole year is month 0", %{user: user} do
    LLMStub.script([answer("Bom ano")])
    on_exit(fn -> Analyses.clear(user.id, 2026, 0) end)

    assert {:ok, :started} = Analyses.request(user.id, 2026, 0)
    assert_receive {:agent_run, {:analysis, 2026, 0}, {:done, _}}, 5_000
    assert %{month: 0} = Analyses.latest(user.id, 2026, 0)
  end

  test "a current analysis is not made again", %{user: user} do
    LLMStub.script([answer("Bom mês")])
    {:ok, :started} = Analyses.request(user.id, 2026, 3)
    assert_receive {:agent_run, {:analysis, 2026, 3}, {:done, _}}, 5_000

    assert {:ok, :current} = Analyses.request(user.id, 2026, 3)
    refute_receive {:agent_run, _, _}, 100
  end

  test "new data in the period makes the analysis stale", %{user: user} do
    LLMStub.script([answer("Bom mês"), answer("Mês revisto")])
    {:ok, :started} = Analyses.request(user.id, 2026, 3)
    assert_receive {:agent_run, {:analysis, 2026, 3}, {:done, _}}, 5_000
    analysis = Analyses.latest(user.id, 2026, 3)
    refute Analyses.stale?(analysis)

    # Timestamps have whole seconds: the data so far and the analysis are moved back so
    # the next transactions clearly land after it.
    now = analysis.inserted_at
    Grana.Repo.update_all(Grana.Banking.Transaction, set: [updated_at: DateTime.add(now, -10)])
    Grana.Repo.update_all(Grana.Banking.AIAnalysis, set: [inserted_at: DateTime.add(now, -5)])
    analysis = Analyses.latest(user.id, 2026, 3)
    refute Analyses.stale?(analysis)

    transaction_fixture(user, %{description: "PADARIA", amount: "-20.00", date: ~D[2026-04-02]})
    refute Analyses.stale?(analysis)

    transaction_fixture(user, %{description: "PADARIA", amount: "-20.00", date: ~D[2026-03-20]})
    assert Analyses.stale?(analysis)

    assert {:ok, :started} = Analyses.request(user.id, 2026, 3)
    assert_receive {:agent_run, {:analysis, 2026, 3}, {:done, _}}, 5_000
    assert Analyses.latest(user.id, 2026, 3).result_json["titulo"] == "Mês revisto"
    assert length(Banking.list_ai_analyses(user.id)) == 2
  end

  test "another model makes the analysis again", %{user: user} do
    LLMStub.script([answer("Bom mês"), answer("Outra visão")])
    {:ok, :started} = Analyses.request(user.id, 2026, 3)
    assert_receive {:agent_run, {:analysis, 2026, 3}, {:done, _}}, 5_000

    [ref, _model] = user |> Grana.AI.general_choice() |> String.split("|")

    assert {:ok, :started} =
             Analyses.request(user.id, 2026, 3, Grana.AI.choice(ref, "gemini-pro"))

    assert_receive {:agent_run, {:analysis, 2026, 3}, {:done, _}}, 5_000
    assert %{ai_model: "gemini-pro"} = Analyses.latest(user.id, 2026, 3)
  end

  test "busy while the period is being analyzed", %{user: user} do
    test_pid = self()

    LLMStub.script([
      fn _messages ->
        send(test_pid, {:waiting, self()})

        receive do
          :go -> answer("Bom mês")
        end
      end
    ])

    {:ok, :started} = Analyses.request(user.id, 2026, 3)
    assert_receive {:waiting, task}, 5_000
    assert {:error, :busy} = Analyses.request(user.id, 2026, 3)

    send(task, :go)
    assert_receive {:agent_run, {:analysis, 2026, 3}, {:done, _}}, 5_000
  end

  test "errors stay with the run", %{user: user} do
    LLMStub.script([{:error, "boom"}, {:error, "boom"}])

    {:ok, :started} = Analyses.request(user.id, 2026, 3)
    assert_receive {:agent_run, {:analysis, 2026, 3}, {:error, _}}, 5_000

    assert %{outcome: {:error, "A IA respondeu com erro: boom"}} =
             Analyses.in_progress(user.id, 2026, 3)

    assert Analyses.latest(user.id, 2026, 3) == nil
  end

  test "a period without transactions cannot be analyzed", %{user: user} do
    on_exit(fn -> Analyses.clear(user.id, 2025, 1) end)
    {:ok, :started} = Analyses.request(user.id, 2025, 1)
    assert_receive {:agent_run, {:analysis, 2025, 1}, {:error, reason}}, 5_000
    assert reason =~ "Nenhuma transação"
  end
end
