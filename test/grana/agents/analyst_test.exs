defmodule Grana.Agents.AnalystTest do
  use Grana.DataCase, async: false
  use Mimic

  import Grana.AccountsFixtures
  import Grana.BankingFixtures

  alias Grana.Agents.Analyst
  alias Grana.LLMStub

  @analysis %{
    "nota" => 7.5,
    "titulo" => "Mês controlado",
    "resumo" => "Gastos dentro do esperado.",
    "pontos" => [%{"tipo" => "positivo", "texto" => "Sobrou dinheiro."}],
    "alerta" => nil,
    "resposta" => nil
  }

  setup do
    user = user_fixture() |> ai_fixture()

    transactions_fixture(user, [
      %{description: "MERCADO BOM", amount: "-250.00", date: ~D[2026-03-10]},
      %{description: "SALARIO", amount: "5000.00", type: "credit", date: ~D[2026-03-05]},
      %{description: "LOJA", amount: "-90.00", date: ~D[2026-03-12]}
    ])

    %{user: user}
  end

  defp prompt_of(agent) do
    [{_model, [message]}] = LLMStub.calls(agent)
    LLMStub.text(message)
  end

  test "sends the period's numbers and returns the analysis with the model", %{user: user} do
    agent = LLMStub.script(["Aqui está: " <> Jason.encode!(@analysis)])

    assert {:ok,
            %{analysis: analysis, ai_provider: "Google Gemini", ai_model: "gemini-test-model"}} =
             Analyst.run(user.id, %{year: 2026, month: 3})

    assert analysis["titulo"] == "Mês controlado"

    prompt = prompt_of(agent)
    assert prompt =~ "Março/2026"
    assert prompt =~ "Expenses: R$ 340,00"
    assert prompt =~ "Average expenses per day: R$ 10,97"
    assert prompt =~ "Income: R$ 5.000,00"
    assert prompt =~ "MERCADO BOM"
    assert prompt =~ "DAILY EXPENSES"
    assert prompt =~ ~s("resposta": null)
  end

  test "the whole year, with filters and a question", %{user: user} do
    agent = LLMStub.script([Jason.encode!(%{@analysis | "resposta" => "Mercado."})])

    assert {:ok, %{analysis: %{"resposta" => "Mercado."}}} =
             Analyst.run(
               user.id,
               %{year: 2026, month: 0, bank: "nubank", statement_type: "extrato", type: "debit"},
               "Onde gastei mais?"
             )

    prompt = prompt_of(agent)
    assert prompt =~ "the year 2026"
    assert prompt =~ "bank nubank, bank account statements only, expenses only"
    assert prompt =~ "EXPENSES PER YEAR"
    assert prompt =~ "Onde gastei mais?"
    assert prompt =~ "Average expenses per year"
  end

  test "lists active installments", %{user: user} do
    [statement | _] = Grana.Banking.list_statements(user.id)

    Grana.Banking.bulk_insert_transactions([
      %{
        date: ~D[2026-03-20],
        description: "TV 2/10",
        amount: Decimal.new("-300.00"),
        type: "debit",
        installment_current: 2,
        installment_total: 10,
        installment_group_id: "tv-10",
        bank_statement_id: statement.id,
        user_id: user.id
      }
    ])

    agent = LLMStub.script([Jason.encode!(@analysis)])
    Analyst.run(user.id, %{year: 2026, month: 3})
    assert prompt_of(agent) =~ "ACTIVE INSTALLMENTS (1)"
    assert prompt_of(agent) =~ "(2/10), R$ 2.400,00 left"
  end

  test "a period without transactions does not call the model", %{user: user} do
    assert {:error, "Nenhuma transação encontrada" <> _} =
             Analyst.run(user.id, %{year: 2020, month: 1})
  end

  test "invalid answers are errors", %{user: user} do
    LLMStub.script([~s({"titulo": 1})])

    assert {:error, "Formato de resposta inesperado da IA"} =
             Analyst.run(user.id, %{year: 2026, month: 3})

    LLMStub.script([Jason.encode!(%{@analysis | "nota" => "sete"})])

    assert {:error, "Formato de resposta inesperado da IA"} =
             Analyst.run(user.id, %{year: 2026, month: 3})

    LLMStub.script([Jason.encode!(%{@analysis | "nota" => "7,5"})])
    assert {:ok, _} = Analyst.run(user.id, %{year: 2026, month: 3})
  end

  test "as a chat tool it runs with the specialist default and returns the analysis", %{
    user: user
  } do
    LLMStub.script([Jason.encode!(@analysis)])
    tool = Analyst.tool(%{user_id: user.id})

    assert {:ok, json, %{ai_model: "gemini-test-model"}} =
             tool.function.(%{"year" => 2026, "month" => 3, "bank" => "all"}, %{})

    assert json =~ "Mês controlado"
    assert {:error, "Nenhuma transação" <> _} = tool.function.(%{"year" => 2019}, %{})
  end
end
