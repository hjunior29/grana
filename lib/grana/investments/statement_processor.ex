defmodule Grana.Investments.StatementProcessor do
  alias Grana.Investments
  alias Grana.Investments.Parsers.{B3Xlsx, GenericCsv, PdfExtractor}

  def process(file_content, institution_slug, user_id, filename) do
    institution = resolve_institution(institution_slug, user_id)

    parsed = parse_file(file_content, institution_slug, filename, user_id)

    case parsed do
      {:error, reason} ->
        {:error, reason}

      [] ->
        {:error, "Nenhuma transação encontrada no arquivo"}

      transactions when is_list(transactions) ->
        do_process(transactions, institution, user_id, filename)
    end
  end

  defp resolve_institution("b3", user_id) do
    Investments.ensure_b3_institution(user_id)
  end

  defp resolve_institution(slug, user_id) do
    case Investments.get_institution_by_slug(slug, user_id) do
      nil -> raise "Instituição não encontrada: #{slug}"
      inst -> inst
    end
  end

  defp do_process(transactions, institution, user_id, filename) do
    {period_start, period_end} = get_period(transactions)

    {:ok, statement} =
      Investments.create_statement(%{
        filename: filename,
        user_id: user_id,
        institution_id: institution.id,
        period_start: period_start,
        period_end: period_end,
        status: "processing"
      })

    entries =
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
          statement_id: statement.id,
          institution_id: institution.id
        }
      end)

    {count, _} = Investments.bulk_insert_transactions(entries)

    Investments.update_statement(statement, %{
      status: "completed",
      total_transactions: count
    })

    {:ok, %{statement_id: statement.id, transaction_count: count}}
  end

  defp parse_file(file_content, "b3", filename, _user_id) do
    case file_type(filename) do
      :xlsx -> B3Xlsx.parse(file_content)
      :pdf -> PdfExtractor.extract(file_content, "b3")
      :csv -> {:error, "B3 não suporta CSV. Use XLSX (recomendado) ou PDF."}
    end
  end

  defp parse_file(file_content, _institution_slug, filename, user_id) do
    case file_type(filename) do
      :csv -> GenericCsv.parse(file_content)
      :pdf -> PdfExtractor.extract(file_content, user_id)
      :xlsx -> {:error, "Apenas B3 suporta XLSX. Use CSV (recomendado) ou PDF."}
    end
  end

  defp file_type(filename) do
    case Path.extname(String.downcase(filename)) do
      ".pdf" -> :pdf
      ".xlsx" -> :xlsx
      ".xls" -> :xlsx
      _ -> :csv
    end
  end

  defp get_period(transactions) do
    dates = Enum.map(transactions, & &1.date)
    {Enum.min(dates, Date), Enum.max(dates, Date)}
  end
end
