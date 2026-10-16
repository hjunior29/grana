defmodule GranaWeb.ChatHTML do
  @moduledoc """
  Renders a chat answer. The coordinator writes a small HTML fragment; only a fixed set
  of tags and classes survives here (everything else is dropped, scripts and attributes
  included), money values get the privacy span, and the agent's tone classes become the
  app's money colors. Answers saved before HTML (plain text) are wrapped in paragraphs.
  """

  alias Grana.Banking.PrivateNames

  @tags ~w(p br ul ol li strong b em i small table thead tbody tr th td span dl dt dd)
  @classes %{
    "income" => "ui-money-receita",
    "expense" => "ui-money-despesa",
    "muted" => "ui-text-secondary",
    "num" => "ui-num"
  }

  @tag_pattern ~r/<\/?(#{Enum.join(@tags, "|")})[\s>\/]/i

  @money ~r/[+-]?(?:R\$\s?-?(?:\d{1,3}(?:\.\d{3})+|\d+)(?:,\d{1,2})?|\b[A-Z]{3} (?:\d{1,3}(?:\.\d{3})+|\d+),\d{2})/u

  @doc """
  Safe HTML for the screen, as `{:safe, iodata}`. `names` is the user's
  `Grana.Banking.PrivateNames.pattern/1`: known names get the privacy-name span.
  """
  @spec render(String.t() | nil, Regex.t() | nil) :: Phoenix.HTML.safe()
  def render(content, names \\ nil) do
    content
    |> to_string()
    |> as_html()
    |> LazyHTML.from_fragment()
    |> LazyHTML.to_tree()
    |> Enum.flat_map(&clean(&1, names))
    |> LazyHTML.from_tree()
    |> LazyHTML.to_html()
    |> Phoenix.HTML.raw()
  end

  @doc "Same as `render/2` for an answer still being written: a half-typed tag is dropped."
  @spec render_partial(String.t(), Regex.t() | nil) :: Phoenix.HTML.safe()
  def render_partial(content, names \\ nil),
    do: content |> String.replace(~r/<[^>]*$/, "") |> render(names)

  # Plain-text answers (saved before HTML): paragraphs on blank lines, breaks elsewhere.
  defp as_html(content) do
    cond do
      String.trim(content) == "" ->
        ""

      Regex.match?(@tag_pattern, content) ->
        content

      true ->
        content
        |> String.trim()
        |> String.split(~r/\n{2,}/)
        |> Enum.map_join(fn paragraph ->
          escaped = paragraph |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
          "<p>" <> String.replace(escaped, "\n", "<br>") <> "</p>"
        end)
    end
  end

  defp clean({tag, attrs, children}, names) when tag in @tags do
    [{tag, clean_attrs(attrs), Enum.flat_map(children, &clean(&1, names))}]
  end

  # Unknown tags vanish but their content stays.
  defp clean({_tag, _attrs, children}, names), do: Enum.flat_map(children, &clean(&1, names))

  defp clean(text, names) when is_binary(text) do
    Enum.flat_map(PrivateNames.split(text, names), fn
      {name, true} -> [{"span", [{"class", "ui-private-name"}], [name]}]
      {part, false} -> money_parts(part)
    end)
  end

  defp clean(_comment, _names), do: []

  defp clean_attrs(attrs) do
    classes =
      for {"class", value} <- attrs,
          name <- String.split(value),
          class = @classes[name],
          do: class

    if classes == [], do: [], else: [{"class", Enum.join(Enum.uniq(classes), " ")}]
  end

  # Money values get their own span, which "hide values" covers (see `UIComponents.private_text`).
  defp money_parts(text) do
    @money
    |> Regex.split(text, include_captures: true)
    |> Enum.with_index()
    |> Enum.reject(fn {part, _index} -> part == "" end)
    |> Enum.map(fn
      {part, index} when rem(index, 2) == 1 ->
        {"span", [{"class", "ui-private whitespace-nowrap"}], [part]}

      {part, _index} ->
        part
    end)
  end
end
