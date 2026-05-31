defmodule Grana.Banking.Parsers.Bradesco do
  alias Grana.Banking.Parsers.InstallmentParser

  def parse(csv_content) do
    csv_content
    |> String.split("\n")
    |> Enum.drop(2)
    |> Enum.reject(&is_metadata_line?/1)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.map(&parse_line/1)
    |> Enum.reject(&is_nil/1)
  end

  defp is_metadata_line?(line) do
    trimmed = String.trim(line)

    # Primeiro campo do CSV (separado por ";"), p/ detectar a linha de "Total"
    # sem descartar transações cujo histórico contenha a palavra (ex.: "TOTAL POSTO").
    first_field =
      trimmed |> String.split(";") |> List.first() |> to_string() |> String.trim()

    trimmed == "" or
      String.starts_with?(trimmed, ";") or
      String.starts_with?(trimmed, "Filtro") or
      String.starts_with?(trimmed, "Os dados") or
      String.starts_with?(trimmed, "Últimos") or
      String.starts_with?(trimmed, "Extrato") or
      String.starts_with?(first_field, "Total") or
      Regex.match?(~r/^;+$/, trimmed)
  end

  defp parse_line(line) do
    case String.split(line, ";") do
      [date_str, historico, _docto, credito, debito | _rest] ->
        case parse_date(String.trim(date_str)) do
          {:ok, date} ->
            {amount, type} = parse_amount(String.trim(credito), String.trim(debito))

            case amount do
              nil ->
                nil

              _ ->
                trimmed_desc = String.trim(historico)
                cleaned_desc = clean_description(trimmed_desc)
                {final_desc, inst_current, inst_total} = InstallmentParser.extract(cleaned_desc)
                group_id = InstallmentParser.generate_group_id(final_desc, inst_total)

                %{
                  date: date,
                  amount: amount,
                  type: type,
                  identifier: nil,
                  description: final_desc,
                  original_description: trimmed_desc,
                  installment_current: inst_current,
                  installment_total: inst_total,
                  installment_group_id: group_id
                }
            end

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp parse_date(date_str) do
    with [day, month, year] <- String.split(date_str, "/"),
         {d, ""} <- Integer.parse(day),
         {m, ""} <- Integer.parse(month),
         {y, ""} <- Integer.parse(year) do
      Date.new(y, m, d)
    else
      _ -> :error
    end
  end

  defp parse_amount(credito, debito) do
    credit_val = parse_br_number(credito)
    debit_val = parse_br_number(debito)

    cond do
      credit_val && Decimal.compare(credit_val, 0) == :gt ->
        {credit_val, "credit"}

      debit_val && Decimal.compare(debit_val, 0) == :gt ->
        {Decimal.negate(debit_val), "debit"}

      credit_val ->
        {credit_val, "credit"}

      true ->
        {nil, nil}
    end
  end

  defp parse_br_number(str) do
    cleaned = String.trim(str)

    case cleaned do
      "" ->
        nil

      " " ->
        nil

      _ ->
        cleaned
        |> String.replace(".", "")
        |> String.replace(",", ".")
        |> Decimal.new()
    end
  rescue
    _ -> nil
  end

  defp clean_description(desc) do
    desc
    |> String.replace(~r/\*$/, "")
    |> String.trim()
  end
end
