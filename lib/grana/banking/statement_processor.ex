defmodule Grana.Banking.StatementProcessor do
  alias Grana.Banking
  alias Grana.Banking.Parsers.{Nubank, NubankFatura, Bradesco, BradescoFatura, PdfExtractor}
  alias Grana.Banking.AICategorizer

  def process(file_content, bank, statement_type, user_id, filename) do
    categories = Banking.ensure_default_categories(user_id)

    parsed = parse_file(file_content, bank, statement_type, filename, user_id)

    case parsed do
      {:error, reason} ->
        {:error, reason}

      [] ->
        {:error, "No transactions found in file"}

      {transactions, detected_bank} when is_list(transactions) ->
        do_process(transactions, detected_bank, statement_type, user_id, filename, categories)

      transactions when is_list(transactions) ->
        do_process(transactions, bank, statement_type, user_id, filename, categories)
    end
  end

  defp do_process(transactions, bank, statement_type, user_id, filename, categories) do
    {period_start, period_end} = get_period(transactions)

    {:ok, statement} =
      Banking.create_statement(%{
        bank: bank,
        filename: filename,
        statement_type: statement_type,
        user_id: user_id,
        period_start: period_start,
        period_end: period_end,
        status: "processing"
      })

    categorized_transactions = categorize_all(transactions, categories, user_id)

    entries =
      Enum.map(categorized_transactions, fn txn ->
        %{
          date: txn.date,
          description: txn.description,
          original_description: txn.original_description,
          amount: txn.amount,
          type: txn.type,
          identifier: txn.identifier,
          installment_current: txn[:installment_current],
          installment_total: txn[:installment_total],
          installment_group_id: txn[:installment_group_id],
          bank_statement_id: statement.id,
          user_id: user_id,
          category_id: txn.category_id
        }
      end)

    entries = deduplicate(entries, user_id)

    {count, _} = Banking.bulk_insert_transactions(entries)

    Banking.update_statement(statement, %{
      status: "completed",
      total_transactions: count
    })

    Banking.detect_internal_transfers(user_id)

    {:ok, %{statement_id: statement.id, transaction_count: count}}
  end

  defp parse_file(file_content, "outro", statement_type, filename, user_id) do
    case file_type(filename) do
      :pdf ->
        case PdfExtractor.extract(file_content, "outro", user_id) do
          {:ok, transactions, %{detected_bank: detected_bank, detected_type: detected_type}} ->
            if detected_type != statement_type do
              type_label = if detected_type == "fatura", do: "uma fatura", else: "um extrato"
              selected_label = if statement_type == "fatura", do: "fatura", else: "extrato"

              {:error,
               "O documento parece ser #{type_label}, mas foi selecionado #{selected_label}. Selecione o tipo correto e tente novamente."}
            else
              {transactions, detected_bank}
            end

          {:error, reason} ->
            {:error, reason}
        end

      :csv ->
        {:error, "Arquivos CSV não são suportados para \"Outro banco\". Use PDF."}
    end
  end

  defp parse_file(file_content, bank, statement_type, filename, user_id) do
    case file_type(filename) do
      :pdf ->
        case PdfExtractor.extract(file_content, bank, user_id) do
          {:ok, transactions} -> transactions
          {:error, reason} -> {:error, reason}
        end

      :csv ->
        parse_csv(file_content, bank, statement_type)
    end
  end

  defp parse_csv(content, "nubank", "fatura"), do: NubankFatura.parse(content)
  defp parse_csv(content, "nubank", "extrato"), do: Nubank.parse(content)
  defp parse_csv(content, "bradesco", "fatura"), do: BradescoFatura.parse(content)
  defp parse_csv(content, "bradesco", "extrato"), do: Bradesco.parse(content)

  defp file_type(filename) do
    case Path.extname(String.downcase(filename)) do
      ".pdf" -> :pdf
      _ -> :csv
    end
  end

  defp categorize_all(transactions, categories, user_id) do
    rule_categorized =
      Enum.map(transactions, fn txn ->
        category_id = Banking.categorize_transaction(txn.description, user_id)
        Map.put(txn, :category_id, category_id)
      end)

    uncategorized_cat = Banking.get_uncategorized_category(user_id)
    uncategorized_id = if uncategorized_cat, do: uncategorized_cat.id

    uncategorized =
      rule_categorized
      |> Enum.filter(fn txn ->
        txn.category_id == uncategorized_id || is_nil(txn.category_id)
      end)

    case uncategorized do
      [] ->
        rule_categorized

      items ->
        descriptions = Enum.map(items, & &1.description)

        case AICategorizer.categorize_batch(descriptions, categories, user_id) do
          {:ok, ai_category_ids} ->
            ai_map =
              Enum.zip(descriptions, ai_category_ids)
              |> Map.new()

            Enum.map(rule_categorized, fn txn ->
              case Map.get(ai_map, txn.description) do
                nil ->
                  txn

                cat_id when txn.category_id == uncategorized_id or is_nil(txn.category_id) ->
                  Map.put(txn, :category_id, cat_id || uncategorized_id)

                _ ->
                  txn
              end
            end)

          {:error, _} ->
            rule_categorized
        end
    end
  end

  defp deduplicate(entries, user_id) do
    dates = Enum.map(entries, & &1.date)
    date_from = Enum.min(dates, Date)
    date_to = Enum.max(dates, Date)

    existing =
      Banking.list_transactions(user_id, date_from: date_from, date_to: date_to)

    existing_freq =
      existing
      |> Enum.map(&fingerprint/1)
      |> Enum.frequencies()

    {kept, _freq} =
      Enum.reduce(entries, {[], existing_freq}, fn entry, {acc, freq} ->
        key = fingerprint(entry)
        count = Map.get(freq, key, 0)

        if count > 0 do
          {acc, Map.put(freq, key, count - 1)}
        else
          {[entry | acc], freq}
        end
      end)

    Enum.reverse(kept)
  end

  defp fingerprint(%{date: date, description: desc, amount: amount}) do
    normalized_amount = amount |> Decimal.round(2) |> Decimal.to_string(:normal)
    {date, String.downcase(String.trim(desc)), normalized_amount}
  end

  defp get_period(transactions) do
    dates = Enum.map(transactions, & &1.date)
    {Enum.min(dates, Date), Enum.max(dates, Date)}
  end
end
