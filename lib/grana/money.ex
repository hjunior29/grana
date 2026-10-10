defmodule Grana.Money do
  @moduledoc "Formatação de valores monetários no padrão brasileiro."

  @doc "Formata valores monetários (`R$ 1.234,56`; outras moedas com o código)."
  def format(amount, currency \\ "BRL")
  def format(nil, _currency), do: "—"

  def format(%Decimal{} = amount, currency) do
    sign = if Decimal.negative?(amount), do: "-", else: ""
    symbol = if currency in [nil, "BRL"], do: "R$", else: currency
    "#{sign}#{symbol} #{br_number(amount)}"
  end

  defp br_number(amount) do
    [int_part, dec_part] =
      amount
      |> Decimal.abs()
      |> Decimal.round(2)
      |> Decimal.to_string(:normal)
      |> String.split(".")
      |> case do
        [int_part] -> [int_part, "00"]
        parts -> parts
      end

    int_part =
      int_part
      |> String.reverse()
      |> String.to_charlist()
      |> Enum.chunk_every(3)
      |> Enum.join(".")
      |> String.reverse()

    "#{int_part},#{String.pad_trailing(dec_part, 2, "0")}"
  end
end
