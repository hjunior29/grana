defmodule Granai.Banking.CsvExporter do
  @bom <<0xEF, 0xBB, 0xBF>>
  @separator ";"
  @headers ["Data", "Descrição", "Valor", "Tipo", "Categoria"]

  def generate(transactions) do
    rows =
      transactions
      |> Enum.map(fn txn ->
        [
          format_date(txn.date),
          txn.description,
          format_amount(txn.amount),
          type_label(txn.type),
          category_name(txn)
        ]
        |> Enum.map(&escape_field/1)
        |> Enum.join(@separator)
      end)

    [@bom, Enum.join(@headers, @separator), "\r\n", Enum.join(rows, "\r\n"), "\r\n"]
    |> IO.iodata_to_binary()
  end

  defp format_date(date) do
    Calendar.strftime(date, "%d/%m/%Y")
  end

  defp format_amount(amount) do
    amount
    |> Decimal.abs()
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
    |> String.replace(".", ",")
  end

  defp type_label("credit"), do: "Receita"
  defp type_label("debit"), do: "Despesa"
  defp type_label(_), do: ""

  defp category_name(%{category: %{name: name}}), do: name
  defp category_name(_), do: "Sem Categoria"

  defp escape_field(val) when is_binary(val) do
    if String.contains?(val, [";", "\"", "\n"]) do
      "\"" <> String.replace(val, "\"", "\"\"") <> "\""
    else
      val
    end
  end

  defp escape_field(val), do: to_string(val)
end
