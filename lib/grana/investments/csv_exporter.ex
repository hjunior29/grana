defmodule Grana.Investments.CsvExporter do
  alias Grana.Investments.Constants

  @separator ";"
  @headers [
    "Data",
    "Ativo",
    "Ticker",
    "Tipo Ativo",
    "Operação",
    "Quantidade",
    "Preço Unit.",
    "Valor Total",
    "Taxas",
    "Instituição",
    "Descrição Original",
    "Identificador"
  ]

  def generate(transactions) do
    rows =
      transactions
      |> Enum.map(fn txn ->
        [
          format_date(txn.date),
          txn.asset_name || "",
          txn.asset_ticker || "",
          Constants.asset_type_label(txn.asset_type),
          Constants.operation_label(txn.operation),
          format_decimal(txn.quantity),
          format_decimal(txn.unit_price),
          format_amount(txn.total_amount),
          format_decimal(txn.fees),
          institution_name(txn),
          txn.original_description || "",
          txn.identifier || ""
        ]
        |> Enum.map(&escape_field/1)
        |> Enum.join(@separator)
      end)

    [Enum.join(@headers, @separator), "\r\n", Enum.join(rows, "\r\n"), "\r\n"]
    |> IO.iodata_to_binary()
  end

  defp format_date(date), do: Calendar.strftime(date, "%d/%m/%Y")

  defp format_amount(amount) do
    amount
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
    |> String.replace(".", ",")
  end

  defp format_decimal(nil), do: ""

  defp format_decimal(%Decimal{} = d) do
    if Decimal.compare(d, 0) == :eq do
      ""
    else
      d |> Decimal.round(2) |> Decimal.to_string(:normal) |> String.replace(".", ",")
    end
  end

  defp institution_name(%{institution: %{name: name}}), do: name
  defp institution_name(_), do: ""

  defp escape_field(val) when is_binary(val) do
    if String.contains?(val, [";", "\"", "\n"]) do
      "\"" <> String.replace(val, "\"", "\"\"") <> "\""
    else
      val
    end
  end

  defp escape_field(val), do: to_string(val)
end
