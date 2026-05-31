defmodule Grana.Banking.Parsers.Nubank do
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
    case String.split(line, ",", parts: 4) do
      [date_str, value_str, identifier, description] ->
        with {:ok, date} <- parse_date(String.trim(date_str)),
             amount when not is_nil(amount) <- parse_amount(String.trim(value_str)) do
          type = if Decimal.compare(amount, 0) == :lt, do: "debit", else: "credit"

          trimmed_desc = String.trim(description)
          cleaned_desc = clean_description(trimmed_desc)
          {final_desc, inst_current, inst_total} = InstallmentParser.extract(cleaned_desc)
          group_id = InstallmentParser.generate_group_id(final_desc, inst_total)

          %{
            date: date,
            amount: amount,
            type: type,
            identifier: String.trim(identifier),
            description: final_desc,
            original_description: trimmed_desc,
            installment_current: inst_current,
            installment_total: inst_total,
            installment_group_id: group_id
          }
        else
          _ -> nil
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

  defp parse_amount(value_str) do
    case Decimal.parse(value_str) do
      {decimal, _rest} -> decimal
      :error -> nil
    end
  end

  defp clean_description(desc) do
    desc
    |> String.replace(~r/\s*-\s*[\d•]+\.[\d•]+\/[\d•]+-[\d•]+.*$/, "")
    |> String.replace(~r/\s*-\s*[\d•]+\.[\d•]+\.[\d•]+\/[\d•]+-[\d•]+.*$/, "")
    |> String.replace(~r/\s+\(.*\)$/, "")
    |> String.trim()
  end
end
