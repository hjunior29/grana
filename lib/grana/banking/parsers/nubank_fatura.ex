defmodule Grana.Banking.Parsers.NubankFatura do
  alias Grana.Banking.Parsers.InstallmentParser

  def parse(csv_content) do
    csv_content
    |> String.split("\n")
    |> Enum.drop(1)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.map(&parse_line/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_line(line) do
    case parse_csv_line(line) do
      [date_str, title, amount_str] ->
        case parse_date(String.trim(date_str)) do
          {:ok, date} ->
            csv_amount = Decimal.new(String.trim(amount_str))
            amount = Decimal.negate(csv_amount)
            type = if Decimal.compare(amount, 0) == :lt, do: "debit", else: "credit"

            trimmed_title = String.trim(title)
            {cleaned_desc, inst_current, inst_total} = InstallmentParser.extract(trimmed_title)
            group_id = InstallmentParser.generate_group_id(cleaned_desc, inst_total)

            %{
              date: date,
              amount: amount,
              type: type,
              identifier: nil,
              description: cleaned_desc,
              original_description: trimmed_title,
              installment_current: inst_current,
              installment_total: inst_total,
              installment_group_id: group_id
            }

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp parse_csv_line(line) do
    case Regex.run(~r/^([^,]+),("(?:[^"]|"")*"|[^,]+),(.+)$/, line) do
      [_, date, title, amount] ->
        title = unquote_csv(title)
        [date, title, amount]

      _ ->
        nil
    end
  end

  defp unquote_csv(<<"\"", _::binary>> = val) do
    val
    |> String.slice(1..-2//1)
    |> String.replace(~S(""), "\"")
  end

  defp unquote_csv(val), do: val

  defp parse_date(date_str) do
    case String.split(date_str, "-") do
      [year, month, day] ->
        Date.new(
          String.to_integer(year),
          String.to_integer(month),
          String.to_integer(day)
        )

      _ ->
        :error
    end
  end
end
