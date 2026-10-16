defmodule Grana.Banking.StatementProcessor do
  @moduledoc """
  Imports one statement file: parses it (deterministic parsers first, the processing
  specialist for PDFs they cannot read), categorizes, deduplicates and saves. When the
  specialist is used, its provider and model are recorded on the statement.
  """

  alias Grana.AI
  alias Grana.Agents.Processor
  alias Grana.Banking

  alias Grana.Banking.Parsers.{
    Nubank,
    NubankFatura,
    Bradesco,
    BradescoFatura,
    BradescoPdf,
    PdfText
  }

  require Logger
  alias Grana.Banking.KeywordCategorizer
  alias Grana.OpenFinance

  @doc "`choice` picks the model for this file (`Grana.AI.choice/2`); nil uses the default."
  def process(file_content, bank, statement_type, user_id, filename, choice \\ nil) do
    categories = Banking.ensure_default_categories(user_id)
    ai = fn -> AI.resolve(user_id, Processor.key(), choice) end

    case parse_file(file_content, bank, statement_type, filename, ai) do
      {:error, reason} ->
        {:error, reason}

      {:ok, [], _bank, _config} ->
        {:error, "No transactions found in file"}

      {:ok, transactions, bank, pdf_config} ->
        {categorized, categorize_config} = categorize_all(transactions, categories, user_id, ai)

        save(
          categorized,
          bank,
          statement_type,
          user_id,
          filename,
          pdf_config || categorize_config
        )
    end
  end

  defp save(transactions, bank, statement_type, user_id, filename, ai_config) do
    {period_start, period_end} = get_period(transactions)

    transaction_result =
      Grana.Repo.transaction(fn ->
        case Banking.create_statement(%{
               bank: bank,
               filename: filename,
               statement_type: statement_type,
               user_id: user_id,
               period_start: period_start,
               period_end: period_end,
               status: "processing",
               ai_provider: ai_config && ai_config.name,
               ai_model: ai_config && ai_config.model
             }) do
          {:ok, statement} ->
            entries =
              Enum.map(transactions, fn txn ->
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

            # The upload wins over Open Finance for the period it covers: those
            # transactions leave before deduplication, which compares with other uploads.
            OpenFinance.release_period(user_id, bank, statement_type, period_start, period_end)

            entries = deduplicate(entries, user_id)

            {count, _} = Banking.bulk_insert_transactions(entries)

            {:ok, _} =
              Banking.update_statement(statement, %{
                status: "completed",
                total_transactions: count
              })

            %{statement_id: statement.id, transaction_count: count}

          {:error, changeset} ->
            Grana.Repo.rollback(
              {:duplicate_statement,
               Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)}
            )
        end
      end)

    case transaction_result do
      {:ok, result} ->
        OpenFinance.uploads_changed(user_id)

        case Banking.detect_internal_transfers(user_id) do
          :ok -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end

      {:error, {:duplicate_statement, _}} ->
        {:error, "Este extrato já foi importado anteriormente"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_file(file_content, "outro", statement_type, filename, ai) do
    case file_type(filename) do
      :pdf -> read_unknown_bank(file_content, statement_type, ai)
      :csv -> {:error, "Arquivos CSV não são suportados para \"Outro banco\". Use PDF."}
    end
  end

  defp parse_file(file_content, bank, statement_type, filename, ai) do
    case file_type(filename) do
      :pdf -> parse_pdf(file_content, bank, statement_type, ai)
      :csv -> csv_result(parse_csv(file_content, bank, statement_type), bank)
    end
  end

  defp csv_result({:error, reason}, _bank), do: {:error, reason}
  defp csv_result(transactions, bank), do: {:ok, transactions, bank, nil}

  defp read_unknown_bank(file_content, statement_type, ai) do
    with {:ok, config} <- ai.(),
         {:ok, transactions, %{detected_bank: bank, detected_type: detected_type}} <-
           Processor.extract_pdf(file_content, "outro", config) do
      if detected_type == statement_type do
        {:ok, transactions, bank, config}
      else
        found = if detected_type == "fatura", do: "uma fatura", else: "um extrato"
        selected = if statement_type == "fatura", do: "fatura", else: "extrato"

        {:error,
         "O documento parece ser #{found}, mas foi selecionado #{selected}. Selecione o tipo correto e tente novamente."}
      end
    end
  end

  # Bradesco account statements go through pdftotext + regex first (no AI, no
  # hallucination). The specialist reads it only when the PDF has no text layer,
  # pdftotext is missing or nothing recognizable is found.
  defp parse_pdf(file_content, "bradesco" = bank, "extrato", ai) do
    case PdfText.extract(file_content) do
      {:ok, text} ->
        case BradescoPdf.parse(text) do
          [] ->
            Logger.info("BradescoPdf found no transactions; falling back to AI")
            read_pdf(file_content, bank, ai)

          transactions when is_list(transactions) ->
            log_reconciliation(text)
            {:ok, transactions, bank, nil}
        end

      {:error, reason} ->
        Logger.info("PdfText unavailable (#{inspect(reason)}); falling back to AI")
        read_pdf(file_content, bank, ai)
    end
  end

  defp parse_pdf(file_content, bank, _statement_type, ai), do: read_pdf(file_content, bank, ai)

  defp read_pdf(file_content, bank, ai) do
    with {:ok, config} <- ai.(),
         {:ok, transactions} <- Processor.extract_pdf(file_content, bank, config) do
      {:ok, transactions, bank, config}
    end
  end

  # Checks the extracted values against the balance printed on the statement. It never
  # blocks the import, only logs mismatches (a sign the layout changed).
  defp log_reconciliation(text) do
    case BradescoPdf.reconcile(text) do
      :ok ->
        :ok

      {:error, issues} ->
        Logger.warning(
          "BradescoPdf: #{length(issues)} balance reconciliation mismatch(es): " <>
            inspect(Enum.take(issues, 5))
        )
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

  # Rules first, then keywords, then the specialist for whatever is still uncategorized.
  # Returns the transactions and the AI config when the specialist was used.
  defp categorize_all(transactions, categories, user_id, ai) do
    category_map =
      Banking.categorize_transactions(Enum.map(transactions, & &1.description), user_id)

    uncategorized_id =
      case Banking.get_uncategorized_category(user_id) do
        nil -> nil
        category -> category.id
      end

    by_name = Map.new(categories, &{&1.name, &1.id})

    base =
      Enum.map(transactions, fn txn ->
        txn = Map.put(txn, :category_id, Map.get(category_map, txn.description))

        with true <- txn.category_id in [nil, uncategorized_id],
             name when is_binary(name) <- KeywordCategorizer.categorize(txn.description) do
          Map.put(txn, :category_id, by_name[name] || txn.category_id)
        else
          _ -> txn
        end
      end)

    case Enum.filter(base, &(&1.category_id in [nil, uncategorized_id])) do
      [] -> {base, nil}
      pending -> categorize_with_ai(base, pending, categories, uncategorized_id, ai)
    end
  end

  defp categorize_with_ai(base, pending, categories, uncategorized_id, ai) do
    descriptions = Enum.map(pending, & &1.description)

    with {:ok, config} <- ai.(),
         {:ok, ids} when length(ids) == length(descriptions) <-
           Processor.categorize(descriptions, categories, config) do
      # Matched by position: only applied when the counts are equal.
      by_description = descriptions |> Enum.zip(ids) |> Map.new()

      categorized =
        Enum.map(base, fn txn ->
          case Map.fetch(by_description, txn.description) do
            {:ok, id} when txn.category_id in [nil, uncategorized_id] ->
              Map.put(txn, :category_id, id || uncategorized_id)

            _ ->
              txn
          end
        end)

      {categorized, config}
    else
      {:ok, _mismatched} ->
        Logger.warning(
          "Processor: category count mismatch for #{length(descriptions)} descriptions; keeping rule-based categories"
        )

        {base, nil}

      _ ->
        {base, nil}
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
