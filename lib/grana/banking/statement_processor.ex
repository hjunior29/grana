defmodule Grana.Banking.StatementProcessor do
  alias Grana.Banking
  alias Grana.Banking.Parsers.{
    Nubank,
    NubankFatura,
    Bradesco,
    BradescoFatura,
    BradescoPdf,
    PdfText,
    PdfExtractor
  }

  require Logger
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

    categorized_transactions = categorize_all(transactions, categories, user_id)

    transaction_result =
      Grana.Repo.transaction(fn ->
        case Banking.create_statement(%{
               bank: bank,
               filename: filename,
               statement_type: statement_type,
               user_id: user_id,
               period_start: period_start,
               period_end: period_end,
               status: "processing"
             }) do
          {:ok, statement} ->
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
        parse_pdf(file_content, bank, statement_type, user_id)

      :csv ->
        parse_csv(file_content, bank, statement_type)
    end
  end

  # Extrato do Bradesco: tenta o parser determinístico (pdftotext + regex,
  # sem IA, sem alucinação). Cai no fallback de IA se o PDF não tiver camada de
  # texto, o pdftotext não estiver disponível, ou nada reconhecível for achado.
  defp parse_pdf(file_content, "bradesco" = bank, "extrato", user_id) do
    case PdfText.extract(file_content) do
      {:ok, text} ->
        case BradescoPdf.parse(text) do
          [] ->
            Logger.info("BradescoPdf não encontrou transações; usando fallback de IA")
            ai_pdf(file_content, bank, user_id)

          transactions when is_list(transactions) ->
            log_reconciliation(text)
            transactions
        end

      {:error, reason} ->
        Logger.info("PdfText indisponível (#{inspect(reason)}); usando fallback de IA")
        ai_pdf(file_content, bank, user_id)
    end
  end

  defp parse_pdf(file_content, bank, _statement_type, user_id) do
    ai_pdf(file_content, bank, user_id)
  end

  defp ai_pdf(file_content, bank, user_id) do
    case PdfExtractor.extract(file_content, bank, user_id) do
      {:ok, transactions} -> transactions
      {:error, reason} -> {:error, reason}
    end
  end

  # Confere os valores extraídos contra o saldo impresso no extrato. Não bloqueia
  # a importação — apenas registra divergências (sinal de mudança de layout).
  defp log_reconciliation(text) do
    case BradescoPdf.reconcile(text) do
      :ok ->
        :ok

      {:error, issues} ->
        Logger.warning(
          "BradescoPdf: #{length(issues)} divergência(s) de reconciliação saldo↔movimento: " <>
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

  defp categorize_all(transactions, categories, user_id) do
    descriptions = Enum.map(transactions, & &1.description)
    category_map = Banking.categorize_transactions(descriptions, user_id)

    rule_categorized =
      Enum.map(transactions, fn txn ->
        category_id = Map.get(category_map, txn.description)
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
          {:ok, ai_category_ids} when length(ai_category_ids) == length(descriptions) ->
            # zip casa por posição: só aplicamos se a contagem bater exatamente,
            # senão o alinhamento descrição↔categoria estaria quebrado.
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

          {:ok, _mismatched} ->
            require Logger

            Logger.warning(
              "AICategorizer: contagem divergente (#{length(descriptions)} descrições); mantendo categorização por regras"
            )

            rule_categorized

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
