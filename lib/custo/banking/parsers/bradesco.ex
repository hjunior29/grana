defmodule Custo.Banking.Parsers.Bradesco do
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

    trimmed == "" or
      String.starts_with?(trimmed, ";") or
      String.starts_with?(trimmed, "Filtro") or
      String.starts_with?(trimmed, "Os dados") or
      String.starts_with?(trimmed, "Últimos") or
      String.starts_with?(trimmed, "Extrato") or
      String.contains?(trimmed, "Total") or
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
                %{
                  date: date,
                  amount: amount,
                  type: type,
                  identifier: nil,
                  description: clean_description(String.trim(historico)),
                  original_description: String.trim(historico)
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
    case String.split(date_str, "/") do
      [day, month, year] ->
        Date.new(
          String.to_integer(year),
          String.to_integer(month),
          String.to_integer(day)
        )

      _ ->
        :error
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
