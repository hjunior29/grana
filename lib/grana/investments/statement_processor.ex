defmodule Grana.Investments.StatementProcessor do
  alias Grana.Investments
  alias Grana.Investments.Parsers.{B3Xlsx, GcbCsv, GenericCsv, PdfExtractor}

  def process(file_content, institution_slug, user_id, filename) do
    institution = resolve_institution(institution_slug, user_id)

    case parse_file(file_content, institution_slug, filename, user_id) do
      {:error, reason} ->
        {:error, reason}

      {transactions, warnings} ->
        case transactions do
          [] ->
            {:error, "Nenhuma transação encontrada no arquivo"}

          _ ->
            do_process(transactions, warnings, institution, user_id, filename)
        end
    end
  end

  defp resolve_institution("b3", user_id) do
    Investments.ensure_b3_institution(user_id)
  end

  defp resolve_institution("gcb", user_id) do
    Investments.ensure_gcb_institution(user_id)
  end

  defp resolve_institution(slug, user_id) do
    case Investments.get_institution_by_slug(slug, user_id) do
      nil -> raise "Instituição não encontrada: #{slug}"
      inst -> inst
    end
  end

  defp do_process(transactions, warnings, institution, user_id, filename) do
    {period_start, period_end} = get_period(transactions)

    pre_entries =
      Enum.map(transactions, fn txn ->
        %{
          date: txn.date,
          asset_name: txn.asset_name,
          asset_ticker: txn[:asset_ticker],
          asset_type: txn.asset_type,
          operation: txn.operation,
          quantity: txn[:quantity] || Decimal.new(0),
          unit_price: txn[:unit_price] || Decimal.new(0),
          total_amount: txn.total_amount,
          fees: txn[:fees] || Decimal.new(0),
          identifier: txn[:identifier],
          original_description: txn[:original_description],
          user_id: user_id,
          institution_id: institution.id
        }
      end)

    new_entries = deduplicate(pre_entries, user_id)

    if new_entries == [] do
      {:error, "Todas as transações deste arquivo já foram importadas anteriormente"}
    else
      result =
        Grana.Repo.transaction(fn ->
          case Investments.create_statement(%{
                 filename: filename,
                 user_id: user_id,
                 institution_id: institution.id,
                 period_start: period_start,
                 period_end: period_end,
                 status: "processing"
               }) do
            {:ok, statement} ->
              entries = Enum.map(new_entries, &Map.put(&1, :statement_id, statement.id))

              {count, _} = Investments.bulk_insert_transactions(entries)

              {:ok, _} =
                Investments.update_statement(statement, %{
                  status: "completed",
                  total_transactions: count
                })

              %{statement_id: statement.id, transaction_count: count, warnings: warnings}

            {:error, _changeset} ->
              Grana.Repo.rollback(:duplicate_statement)
          end
        end)

      case result do
        {:ok, data} ->
          # Proventos recém-importados podem casar com créditos de rendimento já
          # presentes no extrato bancário — reconcilia para não contar em dobro.
          Grana.Banking.detect_internal_transfers(user_id)
          {:ok, data}

        {:error, :duplicate_statement} ->
          {:error, "Este extrato já foi importado anteriormente"}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Normalize parser return values to {transactions, warnings}
  defp parse_file(file_content, institution_slug, filename, user_id) do
    result = do_parse_file(file_content, institution_slug, filename, user_id)
    normalize_parse_result(result)
  end

  defp do_parse_file(file_content, "b3", filename, _user_id) do
    case file_type(filename) do
      :xlsx -> B3Xlsx.parse(file_content)
      :pdf -> PdfExtractor.extract(file_content, "b3")
      :csv -> {:error, "B3 não suporta CSV. Use XLSX (recomendado) ou PDF."}
    end
  end

  defp do_parse_file(file_content, "gcb", filename, _user_id) do
    case file_type(filename) do
      :csv -> GcbCsv.parse(file_content)
      :pdf -> PdfExtractor.extract(file_content, "gcb")
      :xlsx -> {:error, "GCB não suporta XLSX. Use CSV (recomendado) ou PDF."}
    end
  end

  defp do_parse_file(file_content, _institution_slug, filename, user_id) do
    case file_type(filename) do
      :csv -> GenericCsv.parse(file_content)
      :pdf -> PdfExtractor.extract(file_content, user_id)
      :xlsx -> {:error, "Apenas B3 suporta XLSX. Use CSV (recomendado) ou PDF."}
    end
  end

  # Normalize different parser return formats to {transactions, warnings} or {:error, reason}
  defp normalize_parse_result({:error, _} = error), do: error

  defp normalize_parse_result({transactions, warnings})
       when is_list(transactions) and is_list(warnings),
       do: {transactions, warnings}

  defp normalize_parse_result({:ok, transactions, warnings}) when is_list(transactions),
    do: {transactions, warnings}

  defp normalize_parse_result({:ok, transactions}) when is_list(transactions),
    do: {transactions, []}

  defp normalize_parse_result(transactions) when is_list(transactions), do: {transactions, []}

  defp file_type(filename) do
    case Path.extname(String.downcase(filename)) do
      ".pdf" -> :pdf
      ".xlsx" -> :xlsx
      ".xls" -> :xlsx
      _ -> :csv
    end
  end

  defp deduplicate(entries, user_id) do
    dates = Enum.map(entries, & &1.date)
    date_from = Enum.min(dates, Date)
    date_to = Enum.max(dates, Date)

    existing =
      Investments.list_transactions(user_id, date_from: date_from, date_to: date_to)

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

  defp fingerprint(%{date: date, asset_name: name, operation: op, total_amount: amount}) do
    normalized_amount = amount |> Decimal.round(2) |> Decimal.to_string(:normal)
    {date, String.downcase(String.trim(name)), op, normalized_amount}
  end

  defp get_period(transactions) do
    dates = Enum.map(transactions, & &1.date)
    {Enum.min(dates, Date), Enum.max(dates, Date)}
  end
end
