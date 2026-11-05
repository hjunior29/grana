defmodule Grana.Agents.CoordinatorTest do
  use Grana.DataCase, async: false
  use Mimic

  import Grana.AccountsFixtures
  import Grana.BankingFixtures

  alias Grana.Agents.Coordinator
  alias Grana.LLMStub

  setup do
    user = user_fixture() |> ai_fixture()

    transactions_fixture(user, [
      %{description: "UBER TRIP", amount: "-30.00", date: ~D[2026-03-10]},
      %{description: "SALARIO", amount: "5000.00", type: "credit", date: ~D[2026-03-05]}
    ])

    %{user: user}
  end

  defp user_says(text), do: [%{role: "user", content: text, tool_calls: []}]

  test "answers with the data a tool returned and records the tool call", %{user: user} do
    agent =
      LLMStub.script([
        {:tool, "get_period_summary", %{"year" => 2026, "month" => 3}},
        "Em março você gastou R$ 30,00."
      ])

    assert {:ok, answer} = Coordinator.run(user.id, user_says("quanto gastei em março?"))

    assert answer.content == "Em março você gastou R$ 30,00."
    assert answer.ai_model == "gemini-test-model"

    assert [%{"name" => "get_period_summary", "arguments" => %{"month" => 3}} = call] =
             answer.tool_calls

    assert call["result"] =~ "R$ 30,00"
    refute call["error"]

    [_first, {_model, messages}] = LLMStub.calls(agent)
    [result] = List.last(messages).tool_results
    assert LLMStub.text(result) =~ ~s("expenses":"R$ 30,00")
  end

  test "asks for an HTML fragment with the allowed tags", %{user: user} do
    agent = LLMStub.script(["<p>ok</p>"])
    Coordinator.run(user.id, user_says("oi"))

    [{_model, [system | _]}] = LLMStub.calls(agent)
    prompt = LLMStub.text(system)
    assert prompt =~ "HTML fragment"
    assert prompt =~ ~s(class="expense")
    refute prompt =~ "Plain text only"
  end

  test "reports each tool as it starts", %{user: user} do
    LLMStub.script([{:tool, "get_data_overview", %{}}, "ok"])
    test_pid = self()

    Coordinator.run(user.id, user_says("o que tem?"), nil, &send(test_pid, &1))

    assert_received {:tool, "get_data_overview"}
  end

  test "streams the answer as it is written", %{user: user} do
    agent = LLMStub.script(["Você gastou R$ 30,00 em março."])
    test_pid = self()

    assert {:ok, %{content: "Você gastou R$ 30,00 em março."}} =
             Coordinator.run(user.id, user_says("e março?"), nil, &send(test_pid, &1))

    assert [{%{stream: true}, _messages}] = LLMStub.calls(agent)
    assert collect_deltas() == "Você gastou R$ 30,00 em março."
  end

  defp use_provider(user, kind, model) do
    provider =
      Grana.Repo.insert!(%Grana.AI.ProviderConfig{
        user_id: user.id,
        kind: kind,
        name: kind,
        api_key: "k"
      })

    {:ok, user} = Grana.AI.set_default(user, Grana.AI.ProviderConfig.ref(provider), model)
    user
  end

  test "streams the OpenAI format, where deltas are plain text", %{user: user} do
    user = use_provider(user, "openai", "gpt-x")
    agent = LLMStub.script([{:stream, ["Tudo ", "certo."]}])
    test_pid = self()

    assert {:ok, %{content: "Tudo certo.", ai_model: "gpt-x"}} =
             Coordinator.run(user.id, user_says("oi"), nil, &send(test_pid, &1))

    assert [{%LangChain.ChatModels.ChatOpenAI{stream: true}, _}] = LLMStub.calls(agent)
    assert collect_deltas() == "Tudo certo."
  end

  test "leaves the model's thinking out of the streamed answer", %{user: user} do
    user = use_provider(user, "anthropic", "claude-x")
    LLMStub.script([{:stream, [{:thinking, "pensando…"}, "Tudo ", "certo."]}])
    test_pid = self()

    assert {:ok, %{content: "Tudo certo."}} =
             Coordinator.run(user.id, user_says("oi"), nil, &send(test_pid, &1))

    assert collect_deltas() == "Tudo certo."
  end

  test "a streamed call that fails is retried without streaming", %{user: user} do
    agent = LLMStub.script([{:error, "stream closed"}, "Pronto."])

    assert {:ok, %{content: "Pronto."}} = Coordinator.run(user.id, user_says("oi"))
    assert [{%{stream: true}, _}, {%{stream: false}, _}] = LLMStub.calls(agent)
  end

  test "a failure without streaming is not retried", %{user: user} do
    agent = LLMStub.script([{:error, "stream closed"}, {:error, "still broken"}])

    assert {:error, "A IA respondeu com erro: still broken"} =
             Coordinator.run(user.id, user_says("oi"))

    assert length(LLMStub.calls(agent)) == 2
  end

  defp collect_deltas(acc \\ "") do
    receive do
      {:delta, text} -> collect_deltas(acc <> text)
    after
      0 -> acc
    end
  end

  test "delegates the search to the specialist and keeps the query", %{user: user} do
    LLMStub.script([
      {:tool, "build_search", %{"request" => "uber"}},
      {:tool, "submit_query", %{"query" => "uber", "explanation" => "Uber."}},
      "Use a busca uber."
    ])

    assert {:ok, %{tool_calls: [%{"name" => "build_search", "query" => "uber"}]}} =
             Coordinator.run(user.id, user_says("monta uma busca de uber"))
  end

  test "replays earlier answers with the data they consulted", %{user: user} do
    agent = LLMStub.script(["Abril ainda não tem dados."])

    history = [
      %{role: "user", content: "e março?", tool_calls: []},
      %{
        role: "assistant",
        content: "Março: R$ 30,00.",
        tool_calls: [
          %{
            "name" => "get_period_summary",
            "arguments" => %{"month" => 3},
            "result" => "{\"expenses\":\"R$ 30,00\"}"
          }
        ]
      },
      %{role: "user", content: "e abril?", tool_calls: []}
    ]

    assert {:ok, _answer} = Coordinator.run(user.id, history)

    [{_model, [_system, _user, assistant, _last]}] = LLMStub.calls(agent)
    assert LLMStub.text(assistant) =~ "[consulted data]"
    assert LLMStub.text(assistant) =~ ~s[get_period_summary({"month":3})]
  end

  test "an invalid search query comes back to the model as a tool error", %{user: user} do
    LLMStub.script([{:tool, "search_transactions", %{"query" => "amount >"}}, "Não consegui."])

    assert {:ok, %{tool_calls: [%{"error" => true, "result" => "Invalid query" <> _}]}} =
             Coordinator.run(user.id, user_says("acima de?"))
  end
end
