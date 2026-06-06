defmodule Grana.Banking.CsvExporter do
  @separator ";"

  # Export completo: além dos campos visíveis, inclui Banco/Origem/Interna/
  # Parcela/Descrição Original/Identificador para que a própria plataforma
  # consiga reimportar tudo (round-trip) sem perder informação.
  @headers [
    "Data",
    "Descrição",
    "Valor",
    "Tipo",
    "Categoria",
    "Banco",
    "Origem",
    "Interna",
    "Parcela",
    "Descrição Original",
    "Identificador"
  ]

  def generate(transactions) do
    rows =
      transactions
      |> Enum.map(fn txn ->
        [
          format_date(txn.date),
          txn.description,
          format_amount(txn.amount),
          type_label(txn.type),
          category_name(txn),
          bank_name(txn),
          origin_label(txn),
          internal_label(txn.is_internal_transfer),
          installment_label(txn),
          txn.original_description || "",
          txn.identifier || ""
        ]
        |> Enum.map(&escape_field/1)
        |> Enum.join(@separator)
      end)

    [Enum.join(@headers, @separator), "\r\n", Enum.join(rows, "\r\n"), "\r\n"]
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

  defp bank_name(%{bank_statement: %{bank: bank}}) when is_binary(bank), do: bank
  defp bank_name(_), do: ""

  defp origin_label(%{bank_statement: %{statement_type: "fatura"}}), do: "Fatura"
  defp origin_label(%{bank_statement: %{statement_type: "extrato"}}), do: "Extrato"
  defp origin_label(_), do: ""

  defp internal_label(true), do: "Sim"
  defp internal_label(_), do: "Não"

  defp installment_label(%{installment_total: total, installment_current: current})
       when is_integer(total),
       do: "#{current}/#{total}"

  defp installment_label(_), do: ""

  defp escape_field(val) when is_binary(val) do
    if String.contains?(val, [";", "\"", "\n"]) do
      "\"" <> String.replace(val, "\"", "\"\"") <> "\""
    else
      val
    end
  end

  defp escape_field(val), do: to_string(val)
end
