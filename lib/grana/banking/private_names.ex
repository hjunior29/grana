defmodule Grana.Banking.PrivateNames do
  @moduledoc """
  Pattern of the user's known names (merchants and people from the transactions) for the
  privacy mode: the screens mark these names in free text written by the AI so "hide
  names" covers them. Built from the data, cached per user and dropped with any upload.
  """

  alias Grana.Banking.Merchants
  alias Grana.Cache

  @min_length 4

  @doc "A regex matching any known name, case-insensitive, or nil when there is none."
  @spec pattern(pos_integer()) :: Regex.t() | nil
  def pattern(user_id) do
    Cache.get_or_store("banking:private_names", user_id, :all, fn -> build(user_id) end)
  end

  @doc "Splits `text` into `{part, name?}` pairs."
  @spec split(String.t(), Regex.t() | nil) :: [{String.t(), boolean()}]
  def split(text, nil), do: [{text, false}]

  def split(text, pattern) do
    pattern
    |> Regex.split(text, include_captures: true)
    |> Enum.with_index()
    |> Enum.reject(fn {part, _index} -> part == "" end)
    |> Enum.map(fn {part, index} -> {part, rem(index, 2) == 1} end)
  end

  defp build(user_id) do
    names =
      user_id
      |> Merchants.names()
      |> Enum.filter(&(String.length(&1) >= @min_length))
      |> Enum.sort_by(&String.length/1, :desc)

    if names == [] do
      nil
    else
      alternatives = Enum.map_join(names, "|", &Regex.escape/1)
      Regex.compile!("(?<![\\p{L}\\p{N}])(?:#{alternatives})(?![\\p{L}\\p{N}])", "iu")
    end
  end
end
