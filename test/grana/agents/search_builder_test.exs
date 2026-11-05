defmodule Grana.Agents.SearchBuilderTest do
  use Grana.DataCase, async: false
  use Mimic

  import Grana.AccountsFixtures

  alias Grana.Agents.SearchBuilder
  alias Grana.LLMStub

  setup do
    user = user_fixture() |> ai_fixture()
    %{user: user}
  end

  test "returns the query the model submitted once it parses", %{user: user} do
    LLMStub.script([
      {:tool, "submit_query",
       %{"query" => "uber AND type:expense", "explanation" => "Gastos com Uber."}}
    ])

    assert {:ok, result} = SearchBuilder.run(user.id, "gastos com uber")

    assert result.kind == :query
    assert result.query == "uber AND type:expense"
    assert result.explanation == "Gastos com Uber."
    assert result.ai_provider == "Google Gemini"
    assert result.ai_model == "gemini-test-model"
  end

  test "sends a parser error back to the model until the query is valid", %{user: user} do
    agent =
      LLMStub.script([
        {:tool, "submit_query", %{"query" => "amount >", "explanation" => "x"}},
        {:tool, "submit_query", %{"query" => "amount > 100", "explanation" => "Acima de R$ 100."}}
      ])

    assert {:ok, %{kind: :query, query: "amount > 100"}} =
             SearchBuilder.run(user.id, "acima de cem reais")

    [_first, {_model, messages}] = LLMStub.calls(agent)
    error = messages |> List.last() |> Map.fetch!(:tool_results) |> hd()
    assert error.is_error
    assert LLMStub.text(error) =~ "Invalid query"
  end

  test "explores the user's merchants and previews before submitting", %{user: user} do
    Grana.BankingFixtures.transactions_fixture(user, [
      %{description: "Pagamento de boleto - UNIMED BH", amount: "-450.00", date: ~D[2026-04-05]}
    ])

    agent =
      LLMStub.script([
        {:tool, "list_merchants", %{"type" => "debit"}},
        {:tool, "preview_query", %{"query" => "category:saude OR unimed"}},
        {:tool, "submit_query",
         %{"query" => "category:saude OR unimed", "explanation" => "Saúde, incluindo a Unimed."}}
      ])

    assert {:ok, %{kind: :query, query: "category:saude OR unimed"}} =
             SearchBuilder.run(user.id, "gastos com saúde")

    calls = LLMStub.calls(agent)
    assert length(calls) == 3
    [{_, messages} | _] = Enum.reverse(calls)

    [merchants, preview | _] =
      for %{role: :tool, tool_results: [r]} <- messages, do: LLMStub.text(r)

    assert merchants =~ "UNIMED BH"
    assert preview =~ ~s("count":1)
    assert LLMStub.text(hd(messages)) =~ "list_merchants"
  end

  test "answers with text when the request is not a search", %{user: user} do
    LLMStub.script(["Eu só monto buscas de transações."])

    assert {:ok, %{kind: :text, text: "Eu só monto buscas de transações."}} =
             SearchBuilder.run(user.id, "qual a capital da França?")
  end

  test "the prompt carries the user's categories and the syntax", %{user: user} do
    Grana.Banking.ensure_default_categories(user.id)
    agent = LLMStub.script(["ok"])

    SearchBuilder.run(user.id, "mercado")

    [{_model, [system | _]}] = LLMStub.calls(agent)
    text = LLMStub.text(system)
    assert text =~ "Alimentação"
    assert text =~ "statement_type:extrato|fatura"
  end

  test "uses the model picked for the call", %{user: user} do
    agent = LLMStub.script(["ok"])
    [ref, _model] = user |> Grana.AI.general_choice() |> String.split("|")
    choice = Grana.AI.choice(ref, "other-model")

    assert {:ok, %{ai_model: "other-model"}} = SearchBuilder.run(user.id, "x", choice)
    assert [{%{model: "other-model"}, _messages}] = LLMStub.calls(agent)
  end

  test "without a provider it reports no_api_key" do
    user = user_fixture()
    assert {:error, :no_api_key} = SearchBuilder.run(user.id, "uber")
  end

  test "provider errors become a message", %{user: user} do
    LLMStub.script([{:error, "Invalid API key"}])
    assert {:error, "A IA respondeu com erro: Invalid API key"} = SearchBuilder.run(user.id, "x")
  end
end
