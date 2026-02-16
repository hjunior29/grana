defmodule Custo.Banking.AICategorizer do
  def categorize_batch(descriptions, categories) when is_list(descriptions) do
    api_key = Application.get_env(:custo, :gemini_api_key) || System.get_env("GEMINI_API_KEY")

    case api_key do
      nil -> {:error, "GEMINI_API_KEY not configured"}
      key -> do_categorize(descriptions, categories, key)
    end
  end

  defp do_categorize(descriptions, categories, api_key) do
    category_names = Enum.map(categories, & &1.name) |> Enum.join(", ")

    numbered_descriptions =
      descriptions
      |> Enum.with_index(1)
      |> Enum.map(fn {desc, i} -> "#{i}. #{desc}" end)
      |> Enum.join("\n")

    prompt = """
    Categorize each bank transaction below into one of these categories: #{category_names}

    Transactions:
    #{numbered_descriptions}

    Return ONLY a JSON array of category names in the same order, like: ["Alimentação", "Transporte", ...]
    If unsure, use "Sem Categoria". No explanation, just the JSON array.
    """

    url =
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=#{api_key}"

    body = %{
      contents: [%{parts: [%{text: prompt}]}],
      generationConfig: %{temperature: 0.1, maxOutputTokens: 2048}
    }

    case Req.post(url, json: body) do
      {:ok, %{status: 200, body: response_body}} ->
        parse_response(response_body, categories)

      {:ok, %{status: status, body: body}} ->
        {:error, "Gemini API error: #{status} - #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  defp parse_response(response_body, categories) do
    text =
      response_body
      |> get_in(["candidates", Access.at(0), "content", "parts", Access.at(0), "text"])
      |> to_string()

    json_text =
      case Regex.run(~r/\[.*\]/s, text) do
        [match] -> match
        _ -> text
      end

    case Jason.decode(json_text) do
      {:ok, category_names} when is_list(category_names) ->
        cat_map = Map.new(categories, fn c -> {c.name, c.id} end)

        result =
          Enum.map(category_names, fn name ->
            Map.get(cat_map, name, Map.get(cat_map, "Sem Categoria"))
          end)

        {:ok, result}

      _ ->
        {:error, "Failed to parse AI response"}
    end
  end
end
