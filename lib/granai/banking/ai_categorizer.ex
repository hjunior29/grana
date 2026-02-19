defmodule Grana.Banking.AICategorizer do
  alias Grana.Accounts
  alias Grana.AI.Provider

  def categorize_batch(descriptions, categories, user_id) when is_list(descriptions) do
    case Accounts.get_user_ai_config(user_id) do
      {:error, :no_api_key} -> {:error, :no_api_key}
      {:ok, config} -> do_categorize(descriptions, categories, config)
    end
  end

  defp do_categorize(descriptions, categories, config) do
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

    ai_config = Map.merge(config, %{temperature: 0.1, max_output_tokens: 2048})

    case Provider.generate_content(prompt, ai_config) do
      {:ok, response_body} -> parse_response(response_body, categories)
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_response(response_body, categories) do
    text = Provider.extract_text(response_body)

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
