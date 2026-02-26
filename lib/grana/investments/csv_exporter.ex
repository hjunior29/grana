defmodule Grana.Investments.CsvExporter do
  @bom <<0xEF, 0xBB, 0xBF>>
  @separator ";"
  @headers ["Data", "Ativo", "Ticker", "Tipo Ativo", "Operação", "Quantidade", "Preço Unit.", "Valor Total", "Taxas", "Instituição"]

  def generate(transactions) do
    rows =
      transactions
      |> Enum.map(fn txn ->
        [
          format_date(txn.date),
          txn.asset_name || "",
          txn.asset_ticker || "",
          asset_type_label(txn.asset_type),
          operation_label(txn.operation),
          format_decimal(txn.quantity),
          format_decimal(txn.unit_price),
          format_amount(txn.total_amount),
          format_decimal(txn.fees),
          institution_name(txn)
        ]
        |> Enum.map(&escape_field/1)
        |> Enum.join(@separator)
      end)

    [@bom, Enum.join(@headers, @separator), "\r\n", Enum.join(rows, "\r\n"), "\r\n"]
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

  defp operation_label("compra"), do: "Compra"
  defp operation_label("venda"), do: "Venda"
  defp operation_label("dividendo"), do: "Dividendo"
  defp operation_label("jcp"), do: "JCP"
  defp operation_label("rendimento"), do: "Rendimento"
  defp operation_label("amortizacao"), do: "Amortização"
  defp operation_label("taxa"), do: "Taxa"
  defp operation_label("outro"), do: "Outro"
  defp operation_label(op), do: op

  defp asset_type_label("acao"), do: "Ação"
  defp asset_type_label("fii"), do: "FII"
  defp asset_type_label("etf"), do: "ETF"
  defp asset_type_label("bdr"), do: "BDR"
  defp asset_type_label("renda_fixa"), do: "Renda Fixa"
  defp asset_type_label("tesouro"), do: "Tesouro"
  defp asset_type_label("cripto"), do: "Cripto"
  defp asset_type_label("fundo"), do: "Fundo"
  defp asset_type_label("nota_fiscal"), do: "Nota Fiscal"
  defp asset_type_label("debenture"), do: "Debênture"
  defp asset_type_label("precatorio"), do: "Precatório"
  defp asset_type_label("recebiveis"), do: "Receb. Judiciais"
  defp asset_type_label("cri"), do: "CRI"
  defp asset_type_label("cra"), do: "CRA"
  defp asset_type_label("op_estruturada"), do: "Op. Estruturada"
  defp asset_type_label("outro"), do: "Outro"
  defp asset_type_label(type), do: type

  defp escape_field(val) when is_binary(val) do
    if String.contains?(val, [";", "\"", "\n"]) do
      "\"" <> String.replace(val, "\"", "\"\"") <> "\""
    else
      val
    end
  end

  defp escape_field(val), do: to_string(val)
end
