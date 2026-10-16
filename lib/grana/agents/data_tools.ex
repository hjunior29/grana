defmodule Grana.Agents.DataTools do
  @moduledoc """
  Tools that let a specialist explore the user's data before answering: the merchants
  behind the transactions and a preview of what a search query finds. Shared by the
  search specialist and the chat coordinator.
  """

  alias Grana.Banking
  alias Grana.Banking.Merchants
  alias Grana.Banking.Search
  alias Grana.Money
  alias Grana.AI.PromptSanitizer
  alias LangChain.Function

  @preview_limit 15

  @doc "The user's merchants and counterparties by frequency, with their current category."
  def list_merchants(user_id) do
    Function.new!(%{
      name: "list_merchants",
      description:
        "The user's merchants and counterparties (from the transaction descriptions), most " <>
          "frequent first, with the category each one currently has. Use it to find which " <>
          "real merchants belong to a concept the user mentions, such as health or delivery.",
      parameters_schema: %{
        type: "object",
        properties: %{
          type: %{
            type: "string",
            enum: ["credit", "debit"],
            description: "Only income or only expenses."
          },
          months: %{type: "integer", description: "Only the last N months. Omit for everything."},
          limit: %{type: "integer", description: "How many merchants (default 60, max 200)."}
        },
        required: []
      },
      function: fn args, _context ->
        merchants =
          Merchants.list(user_id,
            type: args["type"],
            months: args["months"],
            limit: min(args["limit"] || 60, 200)
          )

        {:ok,
         Jason.encode!(
           Enum.map(merchants, fn m ->
             %{
               name: PromptSanitizer.sanitize_description(m.name),
               category: PromptSanitizer.sanitize_description(m.category),
               count: m.count,
               total: Money.format(m.total)
             }
           end)
         )}
      end
    })
  end

  @doc "Runs a candidate query and reports how many transactions it finds and which merchants."
  def preview_query(user_id) do
    Function.new!(%{
      name: "preview_query",
      description:
        "Runs a query in the advanced search syntax and returns how many transactions it " <>
          "finds, the total and the merchants matched, so you can adjust it before submitting.",
      parameters_schema: %{
        type: "object",
        properties: %{query: %{type: "string"}},
        required: ["query"]
      },
      function: fn %{"query" => query}, _context ->
        case Search.parse(query) do
          {:ok, search} ->
            found = Banking.search_transactions(user_id, search)

            merchants =
              found
              |> Enum.frequencies_by(& &1.description)
              |> Enum.sort_by(&elem(&1, 1), :desc)
              |> Enum.take(@preview_limit)
              |> Enum.map(fn {description, count} ->
                %{description: PromptSanitizer.sanitize_description(description), count: count}
              end)

            total =
              found
              |> Enum.map(&Decimal.abs(&1.amount))
              |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

            {:ok,
             Jason.encode!(%{
               count: length(found),
               total: Money.format(total),
               merchants: merchants
             })}

          {:error, reason} ->
            {:error, "Invalid query: #{reason}"}
        end
      end
    })
  end
end
