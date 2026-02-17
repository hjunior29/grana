defmodule Granai.Banking.Parsers.BradescoFatura do
  alias Granai.Banking.Parsers.InstallmentParser

  def parse(csv_content) do
    content = normalize_encoding(csv_content)
    lines = String.split(content, ~r/\r\n|\r|\n/)
    year = extract_year(lines)

    lines
    |> Enum.reject(&is_metadata_line?/1)
    |> Enum.map(&parse_line(&1, year))
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_encoding(content) do
    case String.valid?(content) do
      true -> content
      false -> :unicode.characters_to_binary(content, :latin1, :utf8) |> ensure_binary()
    end
  end

  defp ensure_binary(result) when is_binary(result), do: result
  defp ensure_binary({:error, _, _}), do: ""
  defp ensure_binary({:incomplete, partial, _}), do: partial

  defp extract_year(lines) do
    header = List.first(lines) || ""

    case Regex.run(~r/(\d{2})\/(\d{2})\/(\d{4})/, header) do
      [_, _day, _month, year] -> String.to_integer(year)
      _ -> Date.utc_today().year
    end
  end

  defp is_metadata_line?(line) do
    trimmed = String.trim(line)

    trimmed == "" or
      String.starts_with?(trimmed, "Data:") or
      String.starts_with?(trimmed, "Data;") or
      String.contains?(trimmed, ";;;") or
      String.starts_with?(trimmed, "Total") or
      String.starts_with?(trimmed, "Resumo") or
      String.starts_with?(trimmed, "Saldo") or
      String.starts_with?(trimmed, "(") or
      String.starts_with?(trimmed, "Taxas") or
      String.starts_with?(trimmed, "Descri") or
      String.starts_with?(trimmed, "Cota") or
      String.contains?(trimmed, "ao M") or
      String.contains?(trimmed, "Pr") and String.contains?(trimmed, "Per") or
      String.starts_with?(trimmed, "Pagamento de contas") or
      String.starts_with?(trimmed, "Parcelamento") or
      String.starts_with?(trimmed, "Compras parceladas") or
      String.starts_with?(trimmed, "Rotativo") or
      String.starts_with?(trimmed, "Saque") or
      String.starts_with?(trimmed, "Credi") or
      Regex.match?(~r/^\(.+\)/, trimmed) or
      Regex.match?(~r/^[A-Z ]+;;;/, trimmed)
  end

  defp parse_line(line, year) do
    case String.split(line, ";") do
      [date_str, description, _usd, brl | _] ->
        case parse_date(String.trim(date_str), year) do
          {:ok, date} ->
            amount = parse_br_number(String.trim(brl))

            case amount do
              nil ->
                nil

              val ->
                case Decimal.compare(val, 0) do
                  :eq ->
                    nil

                  _ ->
                    trimmed_desc = String.trim(description)
                    cleaned_desc = clean_description(trimmed_desc)
                    {final_desc, inst_current, inst_total} = InstallmentParser.extract(cleaned_desc)
                    group_id = InstallmentParser.generate_group_id(final_desc, inst_total)

                    %{
                      date: date,
                      amount: Decimal.negate(val),
                      type: "debit",
                      identifier: nil,
                      description: final_desc,
                      original_description: trimmed_desc,
                      installment_current: inst_current,
                      installment_total: inst_total,
                      installment_group_id: group_id
                    }
                end
            end

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp parse_date(date_str, year) do
    case String.split(date_str, "/") do
      [day, month] ->
        Date.new(
          year,
          String.to_integer(month),
          String.to_integer(day)
        )

      [day, month, year_str] ->
        Date.new(
          String.to_integer(year_str),
          String.to_integer(month),
          String.to_integer(day)
        )

      _ ->
        :error
    end
  end

  defp parse_br_number(str) do
    cleaned = String.trim(str)

    case cleaned do
      "" -> nil
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
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
