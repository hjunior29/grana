defmodule Grana.Banking.Parsers.InstallmentParser do
  @doc """
  Extracts installment information from transaction descriptions.

  Returns `{cleaned_description, current, total}` or `{description, nil, nil}`.
  """
  def extract(description) do
    patterns = [
      # "Netflix - Parcela 3/12" or "Netflix - Parc 3/12" or "Netflix - Parc. 3/12"
      ~r/\s*-\s*[Pp]arc(?:ela)?\.?\s*(\d+)\/(\d+)\s*$/,
      # "TIMES OFFICE 1/3" (Bradesco style - number at end with space before)
      ~r/\s+(\d+)\/(\d+)\s*$/
    ]

    Enum.reduce_while(patterns, {description, nil, nil}, fn pattern, acc ->
      case Regex.run(pattern, description) do
        [match, current_str, total_str] ->
          current = String.to_integer(current_str)
          total = String.to_integer(total_str)

          if current >= 1 and current <= total and total >= 2 and total <= 48 do
            cleaned = String.replace(description, match, "") |> String.trim()
            {:halt, {cleaned, current, total}}
          else
            {:cont, acc}
          end

        _ ->
          {:cont, acc}
      end
    end)
  end

  @doc """
  Generates a group ID to link installments of the same purchase across months.
  Uses SHA256 hash of normalized description + total installments.
  """
  def generate_group_id(cleaned_description, total) when is_integer(total) and total >= 2 do
    key = "#{String.downcase(String.trim(cleaned_description))}|#{total}"

    :crypto.hash(:sha256, key)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  def generate_group_id(_, _), do: nil
end
