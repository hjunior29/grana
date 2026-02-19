defmodule GranaiWeb.TransactionsExportController do
  use GranaiWeb, :controller

  alias Grana.Banking
  alias Grana.Banking.CsvExporter

  def export(conn, params) do
    user_id = conn.assigns.current_scope.user.id

    opts =
      []
      |> maybe_add(:search, params["search"])
      |> maybe_add(:bank, params["bank"])
      |> maybe_add(:statement_type, params["statement_type"])
      |> maybe_add(:type, params["type"])
      |> maybe_add(:category_id, params["category_id"])
      |> maybe_add(:date_from, parse_date(params["date_from"]))
      |> maybe_add(:date_to, parse_date(params["date_to"]))
      |> maybe_add(:amount_min, parse_decimal(params["amount_min"]))
      |> maybe_add(:amount_max, parse_decimal(params["amount_max"]))
      |> maybe_add(:internal, params["internal"])
      |> maybe_add(:bank_statement_id, parse_int(params["statement_id"]))

    opts =
      case params["filter"] do
        "uncategorized" -> Keyword.put(opts, :uncategorized, true)
        _ -> opts
      end

    transactions = Banking.list_transactions(user_id, opts)

    csv = CsvExporter.generate(transactions)
    rand = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    filename = "transacoes_#{Date.to_iso8601(Date.utc_today())}_#{rand}.csv"

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s[attachment; filename="#{filename}"])
    |> send_resp(200, csv)
  end

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, _key, ""), do: opts
  defp maybe_add(opts, _key, "all"), do: opts
  defp maybe_add(opts, key, val), do: Keyword.put(opts, key, val)

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil

  defp parse_decimal(str) do
    case Decimal.parse(str) do
      {d, _} -> d
      :error -> nil
    end
  end

  defp parse_int(nil), do: nil

  defp parse_int(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> nil
    end
  end
end
