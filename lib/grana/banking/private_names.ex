defmodule Grana.Banking.PrivateNames do
  @moduledoc """
  Pattern of the user's known names (merchants and people from the transactions) for the
  privacy mode: the screens mark these names in free text written by the AI so "hide
  names" covers them. Built from the data, cached per user and dropped with any upload.
  """

  alias Grana.Banking.Merchants
  alias Grana.Cache

  @min_length 4

  @doc """
  Regexes that together match any known name, case-insensitive, or nil when there is
  none. Several because PCRE limits the size of one: a few years of statements already
  have more names than fit in a single alternation.
  """
  @spec pattern(pos_integer()) :: [Regex.t()] | nil
  def pattern(user_id) do
    Cache.get_or_store("banking:private_names", user_id, :all, fn -> build(user_id) end)
  end

  @doc "Splits `text` into `{part, name?}` pairs."
  @spec split(String.t(), [Regex.t()] | nil) :: [{String.t(), boolean()}]
  def split(text, nil), do: [{text, false}]

  def split(text, patterns) do
    {parts, rest} =
      text
      |> matches(patterns, 0)
      |> Enum.flat_map_reduce(0, fn {start, length}, from ->
        {[
           {binary_part(text, from, start - from), false},
           {binary_part(text, start, length), true}
         ], start + length}
      end)

    Enum.reject(parts ++ [{binary_part(text, rest, byte_size(text) - rest), false}], fn
      {part, _name?} -> part == ""
    end)
  end

  # As one regex would: the leftmost name, and the longest one among those starting
  # there. The offset keeps the lookbehind seeing the text before it.
  defp matches(text, patterns, offset) do
    patterns
    |> Enum.flat_map(&(Regex.run(&1, text, return: :index, offset: offset) || []))
    |> Enum.min_by(fn {start, length} -> {start, -length} end, fn -> nil end)
    |> case do
      nil -> []
      {start, length} -> [{start, length} | matches(text, patterns, start + length)]
    end
  end

  defp build(user_id) do
    names =
      user_id
      |> Merchants.names()
      |> Enum.filter(&(String.length(&1) >= @min_length))
      |> Enum.sort_by(&String.length/1, :desc)

    if names == [], do: nil, else: compile(names)
  end

  # Halves the names until each part compiles, instead of guessing the size limit:
  # it depends on the characters (accents take more room in a case-insensitive regex).
  defp compile([_name] = names), do: [Regex.compile!(source(names), "iu")]

  defp compile(names) do
    case Regex.compile(source(names), "iu") do
      {:ok, regex} ->
        [regex]

      {:error, _too_large} ->
        {longer, shorter} = Enum.split(names, div(length(names), 2))
        compile(longer) ++ compile(shorter)
    end
  end

  defp source(names) do
    "(?<![\\p{L}\\p{N}])(?:#{Enum.map_join(names, "|", &Regex.escape/1)})(?![\\p{L}\\p{N}])"
  end
end
