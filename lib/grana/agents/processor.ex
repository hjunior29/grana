defmodule Grana.Agents.Processor do
  @moduledoc """
  Statement processing specialist: reads transactions from PDFs the deterministic parsers
  cannot handle and categorizes what the user's rules and keywords left uncategorized.
  `Grana.Banking.StatementProcessor` resolves the config once per file and records the
  model on the statement whenever this specialist is used.
  """

  @behaviour Grana.Agents.Specialist

  alias Grana.AI.ChatModel
  alias Grana.AI.LLM
  alias Grana.AI.PromptSanitizer
  alias Grana.Banking.Parsers.InstallmentParser
  alias LangChain.Chains.LLMChain
  alias LangChain.Message
  alias LangChain.Message.ContentPart

  @impl true
  def key, do: "processing"

  alias Grana.Banking.Parsers.PdfText

  @doc """
  Transactions in the PDF, an account statement (`"extrato"`) or a card bill (`"fatura"`).
  For `"outro"` (unknown bank) it also returns the detected bank and document type:
  `{:ok, transactions, %{detected_bank:, detected_type:}}`.
  """
  def extract_pdf(pdf_bytes, bank, config, statement_type \\ "extrato") do
    prompt = pdf_prompt(bank, statement_type)

    message =
      case PdfText.extract(pdf_bytes) do
        {:ok, text} ->
          sanitized_text = redact_sensitive_info(text)

          Message.new_user!(
            "#{prompt}\n\nDocument text:\n#{PromptSanitizer.wrap_transactions(sanitized_text)}"
          )

        _ ->
          Message.new_user!([
            ContentPart.file!(Base.encode64(pdf_bytes), media: :pdf, filename: "statement.pdf"),
            ContentPart.text!(prompt)
          ])
      end

    case call(message, config, max_tokens: 16_384, receive_timeout: 180_000) do
      {:ok, text} when bank == "outro" -> parse_document(text)
      {:ok, text} -> parse_transactions(text)
      {:error, reason} -> {:error, reason}
    end
  end

  defp redact_sensitive_info(text) do
    text
    |> String.replace(~r/\b\d{3}\.?\d{3}\.?\d{3}-?\d{2}\b/, "[CPF]")
    |> String.replace(~r/\b(ag[eê]ncia|ag\.?|conta|c\/c)\s*[:.]?\s*[\d\-]+/i, "[CONTA]")
  end

  @doc "Category id for each description, in order (uncategorized when unsure)."
  def categorize(descriptions, categories, config) do
    numbered =
      descriptions
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {description, i} ->
        "#{i}. #{PromptSanitizer.sanitize_description(description)}"
      end)

    prompt = """
    Categorize each bank transaction below into one of these categories:
    #{Enum.map_join(categories, ", ", & &1.name)}

    Transactions:
    #{PromptSanitizer.wrap_transactions(numbered)}

    Return ONLY a JSON array with the category names in the same order, like
    ["Alimentação", "Transporte"]. When unsure, use "Sem Categoria".
    """

    case call(Message.new_user!(prompt), config, max_tokens: 4096) do
      {:ok, text} -> category_ids(text, categories)
      {:error, reason} -> {:error, reason}
    end
  end

  defp call(message, config, opts) do
    %{llm: ChatModel.new(config, Keyword.put(opts, :temperature, 0.1))}
    |> LLMChain.new!()
    |> LLMChain.add_message(message)
    |> LLM.run()
    |> case do
      {:ok, chain} -> {:ok, LLM.last_text(chain)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp category_ids(text, categories) do
    by_name = Map.new(categories, &{&1.name, &1.id})

    case decode(text, ~r/\[.*\]/s) do
      {:ok, names} when is_list(names) ->
        {:ok, Enum.map(names, &Map.get(by_name, &1, by_name["Sem Categoria"]))}

      _ ->
        {:error, "Failed to parse AI response"}
    end
  end

  defp parse_transactions(text) do
    case decode(text, ~r/\[.*\]/s) do
      {:ok, items} when is_list(items) ->
        found(items)

      _ ->
        case decode(text, ~r/\{.*\}/s) do
          {:ok, %{"transactions" => items} = document} when is_list(items) ->
            with {:ok, transactions} <- found(items),
                 :ok <- validate_document_total(transactions, document["document_total"]) do
              {:ok, transactions}
            end

          _ ->
            {:error, "Falha ao processar resposta da IA"}
        end
    end
  end

  defp parse_document(text) do
    case decode(text, ~r/\{.*\}/s) do
      {:ok, %{"transactions" => items} = document} when is_list(items) ->
        with {:ok, transactions} <- found(items),
             :ok <- validate_document_total(transactions, document["document_total"]) do
          {:ok, transactions,
           %{
             detected_bank: detected_bank(document["bank"]),
             detected_type: document["document_type"] || "extrato"
           }}
        end

      _ ->
        {:error, "Falha ao processar resposta da IA"}
    end
  end

  defp validate_document_total(transactions, total_val) when not is_nil(total_val) do
    case to_decimal(total_val) do
      %Decimal{} = expected_total ->
        actual_total =
          transactions
          |> Enum.reduce(Decimal.new(0), fn t, acc ->
            Decimal.add(acc, Decimal.abs(t.amount))
          end)

        diff = Decimal.abs(Decimal.sub(actual_total, expected_total))

        if Decimal.compare(diff, Decimal.new("0.05")) == :gt do
          {:error, "Total das transações diverge do total do documento"}
        else
          :ok
        end

      _ ->
        :ok
    end
  end

  defp validate_document_total(_transactions, _total_val), do: :ok

  defp detected_bank(bank) when is_binary(bank), do: bank |> String.trim() |> String.downcase()
  defp detected_bank(_bank), do: "desconhecido"

  defp found(items) do
    transactions = Enum.map(items, &to_transaction/1)

    cond do
      transactions == [] or Enum.all?(transactions, &is_nil/1) ->
        {:error, "No transactions found in PDF"}

      Enum.any?(transactions, &is_nil/1) ->
        {:error, "Transações contêm valores ou campos inválidos"}

      true ->
        {:ok, transactions}
    end
  end

  defp decode(text, pattern) do
    json = with [match] <- Regex.run(pattern, text), do: match
    Jason.decode(json || text)
  end

  defp to_transaction(%{
         "date" => date,
         "description" => description,
         "amount" => amount,
         "type" => type
       })
       when is_binary(date) and is_binary(description) and type in ["credit", "debit"] do
    with {:ok, date} <- parse_date(date),
         %Decimal{} = value <- to_decimal(amount) do
      original = String.trim(description)
      {cleaned, current, total} = InstallmentParser.extract(original)

      %{
        date: date,
        amount: if(type == "debit", do: Decimal.negate(value), else: value),
        type: type,
        identifier: nil,
        description: cleaned,
        original_description: original,
        installment_current: current,
        installment_total: total,
        installment_group_id: InstallmentParser.generate_group_id(cleaned, total)
      }
    else
      _ -> nil
    end
  end

  defp to_transaction(_item), do: nil

  # The model may copy a two-digit year as printed ("05/06/26"), which would be year 26.
  defp parse_date(text) do
    with [day, month, year] <- String.split(text, "/"),
         {d, ""} <- Integer.parse(day),
         {m, ""} <- Integer.parse(month),
         {y, ""} <- Integer.parse(year) do
      Date.new(if(y < 100, do: 2000 + y, else: y), m, d)
    end
  end

  defp to_decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)

  defp to_decimal(value) when is_binary(value) do
    cleaned = Regex.replace(~r/[^\d.,\-]/, value, "")

    case cleaned |> normalize_number() |> Decimal.parse() do
      {decimal, ""} -> decimal
      _ -> nil
    end
  end

  defp to_decimal(_value), do: nil

  # "1.234,56" or "1234,56" would otherwise stop at the comma and lose the cents.
  defp normalize_number(text) do
    text = String.trim(text)

    cond do
      String.contains?(text, ",") and String.contains?(text, ".") ->
        text |> String.replace(".", "") |> String.replace(",", ".")

      String.contains?(text, ",") ->
        String.replace(text, ",", ".")

      true ->
        text
    end
  end

  @transaction_fields """
  For each transaction:
  - date: DD/MM/YYYY
  - description: the full description exactly as printed (do not translate)
  - amount: absolute value as a decimal number with a dot (123.45, not 123,45)
  - type: "credit" for money coming in, "debit" for money going out
  """

  @common_rules """
  Rules:
  - Amounts are always positive.
  - Keep installment information in the description (e.g. "Parcela 1/3", "2/6").
  - For Pix transfers, include the name of the recipient or sender.
  """

  defp pdf_prompt("outro", _statement_type) do
    """
    Read this bank document PDF.
    1. Identify the issuing BANK: lowercase, no spaces or accents (itau, inter, c6bank, bancodobrasil).
    2. Identify the document type: "extrato" (bank account) or "fatura" (credit card bill).
    3. Extract ALL individual transactions.
    #{@transaction_fields}
    #{@common_rules}- Ignore subtotals, balances, headers and summary lines.
    - On a credit card bill, purchases, fees and interest are "debit"; the payment of the
      previous bill and refunds are "credit"; the previous balance is not a transaction.

    Return ONLY JSON:
    {"bank": "itau", "document_type": "extrato", "transactions": [{"date": "01/01/2026", "description": "...", "amount": 100.00, "type": "debit"}]}
    """
  end

  defp pdf_prompt(bank, "fatura") do
    """
    Extract ALL transactions from this #{bank_name(bank)} credit card bill PDF.
    #{@transaction_fields}
    #{@common_rules}- Dates are often printed as DD/MM: take the year from the bill's issue or due
      date, and a month later than the due month belongs to the previous year.
    - Purchases, fees, interest, insurance, annual fee and IOF are "debit".
    - The payment of the previous bill ("PAGTO. POR DEB EM C/C", "Pagamento recebido") and
      refunds (values printed negative) are "credit".
    - Read every card section ("Cartão 1234 XXXX XXXX 5678" and the like): each holder or
      card number lists its own transactions.
    - Use the amount in R$; the US$ column and the exchange rate are not amounts.
    - An installment keeps its "n/N" in the description even when glued to the name
      ("LOJA*EXEMPLO01/02" is "LOJA*EXEMPLO 01/02"), with the date printed.
    - Ignore "SALDO ANTERIOR", the bill summary ("Resumo da fatura", "Total da fatura"),
      payment options, minimum payment, installment offers and the rates table.

    Return ONLY a JSON array:
    [{"date": "04/05/2026", "description": "PAGTO. POR DEB EM C/C", "amount": 1850.40, "type": "credit"}]
    """
  end

  defp pdf_prompt("nubank", _statement_type) do
    """
    Extract ALL transactions from this Nubank bank statement PDF.
    #{@transaction_fields}
    #{@common_rules}- Ignore the "Total de entradas" and "Total de saídas" lines: they are subtotals.
    - Ignore opening balance, closing balance and net yield lines.
    - Transactions after "Total de entradas" are credits; after "Total de saídas", debits.
    - The description includes the kind (e.g. "Compra no débito") and the merchant or person.

    Return ONLY a JSON array:
    [{"date": "01/01/2026", "description": "Pagamento de fatura", "amount": 15.00, "type": "debit"}]
    """
  end

  defp pdf_prompt("bradesco", _statement_type) do
    """
    Extract ALL transactions from this Bradesco bank statement PDF. It comes in two layouts:
    "Bradesco Celular" (aligned columns, debits unsigned in the Débito column) and
    "Bradesco Internet Banking" (debits printed with a minus sign, "- 60,00", in columns
    that do not line up with the header).
    #{@transaction_fields}
    #{@common_rules}- Dates may have a two-digit year ("05/06/26"): write the full year (05/06/2026).
    - A transaction spans several lines: its kind ("Pix Enviado", "Pagto Cobranca"), the
      line with the Docto. number and the amount, and the counterparty ("Des: name",
      "Rem: name" or the payee alone). Append the counterparty after " - ".
    - The date is the DD/MM/YY(YY) at the start of a line; a transaction without one has the
      date of the transaction above it. A bare "DD/MM" after a name is the Pix date, not
      the posting date.
    - An amount with a minus sign is a "debit"; otherwise the column says it: Crédito is
      "credit", Débito is "debit". A line with values in both columns is two transactions.
    - The last number of a line, under Saldo (R$), is the running balance: never a
      transaction and never part of an amount.
    - Ignore "SALDO ANTERIOR", "COD. LANC. 0", the "Total" line and the whole
      "Saldos Invest Fácil" table after it.

    Return ONLY a JSON array:
    [{"date": "06/02/2026", "description": "Pix Qrcode Din - Padaria Exemplo", "amount": 27.35, "type": "debit"}]
    """
  end

  defp pdf_prompt(_bank, _statement_type) do
    """
    Extract ALL transactions from this bank statement PDF.
    #{@transaction_fields}
    #{@common_rules}- Ignore subtotals, balances and headers.

    Return ONLY a JSON array:
    [{"date": "01/01/2026", "description": "...", "amount": 100.00, "type": "debit"}]
    """
  end

  defp bank_name("nubank"), do: "Nubank"
  defp bank_name("bradesco"), do: "Bradesco"
  defp bank_name(_bank), do: "bank"
end
