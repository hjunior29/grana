defmodule Grana.Banking.Parsers.BradescoFatura do
  alias Grana.Banking.Parsers.{Encoding, InstallmentParser}

  def parse(csv_content) do
    content = Encoding.to_utf8(csv_content)
    lines = String.split(content, ~r/\r\n|\r|\n/)
    ref = extract_reference(lines)

    lines
    |> Enum.reject(&is_metadata_line?/1)
    |> Enum.map(&parse_line(&1, ref))
    |> Enum.reject(&is_nil/1)
  end

  # Data de referência da fatura (mês/ano do cabeçalho), usada para inferir o ano
  # de lançamentos no formato DD/MM na virada de ano.
  defp extract_reference(lines) do
    header = List.first(lines) || ""

    case Regex.run(~r/(\d{2})\/(\d{2})\/(\d{4})/, header) do
      [_, _day, month, year] ->
        {String.to_integer(year), String.to_integer(month)}

      _ ->
        today = Grana.LocalTime.today()
        {today.year, today.month}
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
      (String.contains?(trimmed, "Pr") and String.contains?(trimmed, "Per")) or
      String.starts_with?(trimmed, "Pagamento de contas") or
      String.starts_with?(trimmed, "Parcelamento") or
      String.starts_with?(trimmed, "Compras parceladas") or
      String.starts_with?(trimmed, "Rotativo") or
      String.starts_with?(trimmed, "Saque") or
      String.starts_with?(trimmed, "Credi") or
      Regex.match?(~r/^\(.+\)/, trimmed) or
      Regex.match?(~r/^[A-Z ]+;;;/, trimmed)
  end

  defp parse_line(line, ref) do
    case String.split(line, ";") do
      [date_str, description, _usd, brl | _] ->
        case parse_date(String.trim(date_str), ref) do
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
                    amount = Decimal.negate(val)
                    type = if Decimal.compare(amount, 0) == :lt, do: "debit", else: "credit"

                    trimmed_desc = String.trim(description)
                    cleaned_desc = clean_description(trimmed_desc)

                    {final_desc, inst_current, inst_total} =
                      InstallmentParser.extract(cleaned_desc)

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
            end

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp parse_date(date_str, {ref_year, ref_month}) do
    case String.split(date_str, "/") do
      [day, month] ->
        with {d, ""} <- Integer.parse(day),
             {m, ""} <- Integer.parse(month) do
          # Lançamento DD/MM sem ano: se o mês é posterior ao mês da fatura
          # (ex.: dezembro numa fatura de janeiro), pertence ao ano anterior.
          year = if m > ref_month, do: ref_year - 1, else: ref_year
          Date.new(year, m, d)
        else
          _ -> :error
        end

      [day, month, year_str] ->
        with {d, ""} <- Integer.parse(day),
             {m, ""} <- Integer.parse(month),
             {y, ""} <- Integer.parse(year_str) do
          Date.new(y, m, d)
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp parse_br_number(str) do
    cleaned = String.trim(str)

    case cleaned do
      "" ->
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
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
