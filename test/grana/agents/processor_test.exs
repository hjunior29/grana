defmodule Grana.Agents.ProcessorTest do
  use Grana.DataCase, async: false
  use Mimic

  import Grana.AccountsFixtures

  alias Grana.Banking
  alias Grana.Banking.StatementProcessor
  alias Grana.LLMStub
  alias LangChain.Message.ContentPart

  setup do
    user = user_fixture()
    Banking.ensure_default_categories(user.id)

    csv = """
    Data,Valor,Identificador,Descrição
    01/03/2026,-42.00,00000000-0000-0000-0000-0000000000a1,Compra no débito - ZYX COMERCIO
    02/03/2026,-17.50,00000000-0000-0000-0000-0000000000a2,Compra no débito - QWE ARTIGOS
    """

    %{user: user, csv: csv}
  end

  defp pdf_reply(transactions), do: Jason.encode!(transactions)

  defp txn(date, description, amount, type),
    do: %{"date" => date, "description" => description, "amount" => amount, "type" => type}

  # Answers the categorization prompt with one category per numbered line.
  defp categorize_as(name) do
    fn messages ->
      count = Regex.scan(~r/^\d+\. /m, LLMStub.text(List.last(messages))) |> length()
      Jason.encode!(List.duplicate(name, count))
    end
  end

  describe "PDF reading" do
    test "reads the PDF with the specialist and records the model on the statement", %{user: user} do
      user = ai_fixture(user)

      agent =
        LLMStub.script([
          pdf_reply([
            txn("10/03/2026", "Compra no débito MERCADO", "1.234,56", "debit"),
            txn("12/03/2026", "Loja X - Parcela 2/6", 50, "debit"),
            txn("15/03/2026", "Transferência recebida", 100.5, "credit")
          ]),
          categorize_as("Alimentação")
        ])

      assert {:ok, %{transaction_count: 3, statement_id: id}} =
               StatementProcessor.process(
                 "%PDF-1.4 fake",
                 "nubank",
                 "extrato",
                 user.id,
                 "extrato.pdf"
               )

      statement = Repo.get!(Banking.BankStatement, id)
      assert statement.ai_provider == "Google Gemini"
      assert statement.ai_model == "gemini-test-model"

      [{_model, [message]}, _categorize] = LLMStub.calls(agent)
      assert %ContentPart{type: :file, options: options} = hd(message.content)
      assert options[:media] == :pdf
      assert LLMStub.text(%{content: tl(message.content)}) =~ "Nubank"

      amounts =
        user.id
        |> Banking.list_transactions()
        |> Enum.map(&Decimal.to_string(&1.amount))
        |> Enum.sort()

      assert amounts == Enum.sort(["-1234.56", "-50", "100.5"])

      assert Enum.any?(Banking.list_transactions(user.id), &(&1.installment_total == 6))
    end

    test "the picked model processes the file", %{user: user} do
      user = ai_fixture(user)
      LLMStub.script([pdf_reply([txn("10/03/2026", "X", 10, "debit")]), categorize_as("Lazer")])
      [ref, _model] = user |> Grana.AI.general_choice() |> String.split("|")

      assert {:ok, %{statement_id: id}} =
               StatementProcessor.process(
                 "%PDF",
                 "nubank",
                 "fatura",
                 user.id,
                 "f.pdf",
                 Grana.AI.choice(ref, "gemini-pro")
               )

      assert Repo.get!(Banking.BankStatement, id).ai_model == "gemini-pro"
    end

    test "an unknown bank brings the detected bank and checks the document type", %{user: user} do
      user = ai_fixture(user)

      document = fn type ->
        Jason.encode!(%{
          "bank" => " Itau ",
          "document_type" => type,
          "transactions" => [txn("01/02/2026", "PIX", 20, "debit")]
        })
      end

      LLMStub.script([document.("fatura")])

      assert {:error, "O documento parece ser uma fatura, mas foi selecionado extrato." <> _} =
               StatementProcessor.process("%PDF", "outro", "extrato", user.id, "doc.pdf")

      LLMStub.script([document.("extrato"), categorize_as("Transferências")])

      assert {:ok, %{statement_id: id}} =
               StatementProcessor.process("%PDF", "outro", "extrato", user.id, "doc.pdf")

      assert %{bank: "itau", ai_model: "gemini-test-model"} = Repo.get!(Banking.BankStatement, id)
    end

    test "replies the parser cannot use become errors", %{user: user} do
      user = ai_fixture(user)

      LLMStub.script(["não sei ler"])

      assert {:error, "Falha ao processar resposta da IA"} =
               StatementProcessor.process("%PDF", "nubank", "extrato", user.id, "a.pdf")

      LLMStub.script([pdf_reply([%{"date" => "x"}, txn("99/99/2026", "Y", 1, "debit")])])

      assert {:error, "No transactions found in PDF"} =
               StatementProcessor.process("%PDF", "nubank", "extrato", user.id, "b.pdf")

      LLMStub.script([~s({"transactions": "nope"})])

      assert {:error, "Falha ao processar resposta da IA"} =
               StatementProcessor.process("%PDF", "outro", "extrato", user.id, "c.pdf")

      LLMStub.script([
        pdf_reply([
          txn("10/03/2026", "A", "10.00", "debit"),
          txn("11/03/2026", "B", "invalido", "debit")
        ])
      ])

      assert {:error, "Transações contêm valores ou campos inválidos"} =
               StatementProcessor.process("%PDF", "nubank", "extrato", user.id, "d.pdf")

      LLMStub.script([
        Jason.encode!(%{
          "bank" => "itau",
          "document_type" => "extrato",
          "document_total" => "500.00",
          "transactions" => [txn("10/03/2026", "A", "100.00", "debit")]
        })
      ])

      assert {:error, "Total das transações diverge do total do documento"} =
               StatementProcessor.process("%PDF", "outro", "extrato", user.id, "e.pdf")
    end

    test "without a provider the PDF cannot be read", %{user: user} do
      assert {:error, :no_api_key} =
               StatementProcessor.process("%PDF", "nubank", "extrato", user.id, "a.pdf")
    end
  end

  describe "categorization" do
    test "categorizes what rules and keywords left and records the model", %{user: user, csv: csv} do
      user = ai_fixture(user)
      LLMStub.script([categorize_as("Lazer")])

      assert {:ok, %{statement_id: id}} =
               StatementProcessor.process(csv, "nubank", "extrato", user.id, "extrato.csv")

      assert Repo.get!(Banking.BankStatement, id).ai_model == "gemini-test-model"

      lazer = Enum.find(Banking.list_categories(user.id), &(&1.name == "Lazer"))
      assert Enum.any?(Banking.list_transactions(user.id), &(&1.category_id == lazer.id))
    end

    test "a reply with the wrong count keeps the rule categories and records no model", %{
      user: user,
      csv: csv
    } do
      user = ai_fixture(user)
      LLMStub.script([~s(["Lazer"])])

      assert {:ok, %{statement_id: id}} =
               StatementProcessor.process(csv, "nubank", "extrato", user.id, "extrato.csv")

      assert Repo.get!(Banking.BankStatement, id).ai_model == nil
    end

    test "a provider error keeps the import going", %{user: user, csv: csv} do
      user = ai_fixture(user)
      LLMStub.script([{:error, "boom"}])

      assert {:ok, %{statement_id: id}} =
               StatementProcessor.process(csv, "nubank", "extrato", user.id, "extrato.csv")

      assert Repo.get!(Banking.BankStatement, id).ai_model == nil
    end

    test "invalid JSON is ignored", %{user: user, csv: csv} do
      user = ai_fixture(user)
      LLMStub.script(["sem json"])

      assert {:ok, _} =
               StatementProcessor.process(csv, "nubank", "extrato", user.id, "extrato.csv")
    end
  end
end
