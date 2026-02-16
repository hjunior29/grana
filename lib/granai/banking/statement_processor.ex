defmodule Granai.Banking.StatementProcessor do
  alias Granai.Banking
  alias Granai.Banking.Parsers.{Nubank, NubankFatura, Bradesco, BradescoFatura, PdfExtractor}
  alias Granai.Banking.AICategorizer

  def process(file_content, bank, user_id, filename) do
    categories = Banking.ensure_default_categories(user_id)

    parsed = parse_file(file_content, bank, filename)

    case parsed do
      {:error, reason} ->
        {:error, reason}

      [] ->
        {:error, "No transactions found in file"}

      transactions ->
        {period_start, period_end} = get_period(transactions)

        {:ok, statement} =
          Banking.create_statement(%{
            bank: bank,
            filename: filename,
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
              bank_statement_id: statement.id,
              user_id: user_id,
              category_id: txn.category_id
            }
          end)

        {count, _} = Banking.bulk_insert_transactions(entries)

        Banking.update_statement(statement, %{
          status: "completed",
          total_transactions: count
        })

        {:ok, %{statement_id: statement.id, transaction_count: count}}
    end
  end

  defp parse_file(file_content, bank, filename) do
    case file_type(filename) do
      :pdf ->
        case PdfExtractor.extract(file_content, bank) do
          {:ok, transactions} -> transactions
          {:error, reason} -> {:error, reason}
        end

      :csv ->
        parse_csv(file_content, bank)
    end
  end

  defp parse_csv(content, "bradesco") do
    case detect_bradesco_type(content) do
      :fatura -> BradescoFatura.parse(content)
      :extrato -> Bradesco.parse(content)
    end
  end

  defp parse_csv(content, "nubank") do
    case detect_nubank_type(content) do
      :fatura -> NubankFatura.parse(content)
      :extrato -> Nubank.parse(content)
    end
  end

  defp detect_nubank_type(content) do
    first_line = content |> String.split(~r/\r\n|\r|\n/, parts: 2) |> List.first("")

    cond do
      String.starts_with?(first_line, "date,title,amount") -> :fatura
      true -> :extrato
    end
  end

  defp detect_bradesco_type(content) do
    cond do
      String.contains?(content, "Fatura") -> :fatura
      String.contains?(content, "Valor(US$)") -> :fatura
      String.contains?(content, "Total da fatura") -> :fatura
      true -> :extrato
    end
  end

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

        case AICategorizer.categorize_batch(descriptions, categories) do
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

  defp get_period(transactions) do
    dates = Enum.map(transactions, & &1.date)
    {Enum.min(dates, Date), Enum.max(dates, Date)}
  end
end
