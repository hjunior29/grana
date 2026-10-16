defmodule Grana.Agents.SearchBuilder do
  @moduledoc """
  Turns a request in natural language into an advanced search query
  (`Grana.Banking.Search`). Before writing it, the model can look at the user's own
  merchants and preview what a query finds, so a request like "health" also catches the
  user's health plan even when it sits in another category. The query is submitted
  through a tool that validates it with the real parser and retries on errors, so only
  queries that run come back. When the request is not a search, it answers with a short
  text instead.
  """

  @behaviour Grana.Agents.Specialist

  alias Grana.AI
  alias Grana.AI.ChatModel
  alias Grana.AI.LLM
  alias Grana.Agents.DataTools
  alias Grana.Banking
  alias Grana.Banking.Search
  alias LangChain.Chains.LLMChain
  alias LangChain.Chains.LLMChain.Modes.UntilToolUsed
  alias LangChain.Function
  alias LangChain.Message

  @tool_name "submit_query"
  @max_runs 8
  @retries 2

  @impl true
  def key, do: "search"

  @doc """
  Returns `{:ok, %{kind: :query, query:, explanation:} | %{kind: :text, text:}}` with
  `:ai_provider` and `:ai_model`, or `{:error, reason}`.
  """
  def run(user_id, request, choice \\ nil) do
    with {:ok, config} <- AI.resolve(user_id, key(), choice),
         {:ok, chain} <- user_id |> build_chain(request, config) |> run_chain(@retries) do
      {:ok, Map.merge(result(chain), %{ai_provider: config.name, ai_model: config.model})}
    end
  end

  # Runs until the query is submitted (or the model answers in text). A rejected query
  # also ends the run, so the chain goes on for another try while there are retries.
  defp run_chain(chain, retries) do
    opts = [mode: UntilToolUsed, tool_names: [@tool_name], max_runs: @max_runs]

    with {:ok, chain} <- LLM.run(chain, opts) do
      if rejected?(chain) and retries > 0, do: run_chain(chain, retries - 1), else: {:ok, chain}
    end
  end

  defp rejected?(%{last_message: %Message{role: :tool, tool_results: results}}),
    do: Enum.any?(results, &(&1.name == @tool_name and &1.is_error))

  defp rejected?(_chain), do: false

  @impl true
  def tool(%{user_id: user_id}) do
    Function.new!(%{
      name: "build_search",
      description:
        "Builds an advanced search query for the transactions screen from a request in " <>
          "natural language. Returns the query and a link that opens it.",
      parameters_schema: %{
        type: "object",
        properties: %{
          request: %{type: "string", description: "What the user wants to find."}
        },
        required: ["request"]
      },
      function: fn %{"request" => request}, _context ->
        case run(user_id, request) do
          {:ok, %{kind: :query} = result} ->
            {:ok, Jason.encode!(Map.take(result, [:query, :explanation])), result}

          {:ok, %{kind: :text, text: text}} ->
            {:ok, text}

          {:error, reason} ->
            {:error, error_text(reason)}
        end
      end
    })
  end

  defp build_chain(user_id, request, config) do
    %{llm: ChatModel.new(config, temperature: 0.1, max_tokens: 1024)}
    |> LLMChain.new!()
    |> LLMChain.add_message(Message.new_system!(system_prompt(user_id)))
    |> LLMChain.add_message(Message.new_user!(request))
    |> LLMChain.add_tools([
      DataTools.list_merchants(user_id),
      DataTools.preview_query(user_id),
      submit_tool()
    ])
  end

  defp submit_tool do
    Function.new!(%{
      name: @tool_name,
      description: "Submits the advanced search query. It is validated before being accepted.",
      parameters_schema: %{
        type: "object",
        properties: %{
          query: %{type: "string", description: "The query in the advanced search syntax."},
          explanation: %{
            type: "string",
            description:
              "One short sentence in Brazilian Portuguese saying what it finds, naming " <>
                "the merchants you included beyond the obvious ones."
          }
        },
        required: ["query", "explanation"]
      },
      function: fn args, _context -> validate(args) end
    })
  end

  defp validate(%{"query" => query} = args) do
    case Search.parse(query) do
      {:ok, %Search{ast: nil}} ->
        {:error, "The query is empty. Submit a query that filters something."}

      {:ok, _search} ->
        {:ok, "Query accepted.",
         %{query: String.trim(query), explanation: args["explanation"] || ""}}

      {:error, reason} ->
        {:error, "Invalid query: #{reason} Fix it and call #{@tool_name} again."}
    end
  end

  defp result(chain) do
    case accepted_query(chain) do
      %{query: _} = accepted -> Map.put(accepted, :kind, :query)
      nil -> %{kind: :text, text: LLM.last_text(chain)}
    end
  end

  defp accepted_query(chain) do
    chain.messages
    |> Enum.flat_map(&(&1.tool_results || []))
    |> Enum.filter(&(&1.name == @tool_name and not &1.is_error))
    |> List.last()
    |> case do
      nil -> nil
      tool_result -> tool_result.processed_content
    end
  end

  defp error_text(:no_api_key), do: "No AI provider is configured."
  defp error_text(reason), do: to_string(reason)

  defp system_prompt(user_id) do
    categories = user_id |> Banking.list_categories() |> Enum.map_join(", ", & &1.name)
    banks = user_id |> Banking.available_banks() |> Enum.join(", ")

    """
    You write queries for the advanced transaction search of Grana, a personal finance app
    used in Brazil. Turn the user's request into one query and submit it with the
    #{@tool_name} tool. If the request is not something a search can answer, do not call
    the tool: reply with one short sentence in Brazilian Portuguese explaining what you can do.

    Think beyond the category names. When the request names a concept (health, transport,
    food delivery, a person, a service), call list_merchants to see the user's actual
    merchants and include the ones that belong to that concept even if they sit in another
    category or none (a health plan under "Pagamentos" still is health). Use preview_query
    to check what a candidate query finds and adjust it before submitting; one or two
    previews are enough.

    #{syntax_reference()}

    The user's categories: #{categories}.
    The user's banks: #{if banks == "", do: "none yet", else: banks}.
    Today is #{Date.utc_today()}.
    """
  end

  @doc "Reference of the search syntax, shared with the chat coordinator."
  def syntax_reference do
    """
    Search syntax (like PubMed or Scopus):
    - Operators in uppercase: AND (a space also means AND), OR, NOT. Parentheses group.
      Precedence: NOT, then AND, then OR.
    - A term without a field matches the description or the category, ignoring case and
      accents. "exact phrase" in quotes; pix* for prefixes (* any sequence, ? one char);
      /regex/ for regular expressions.
    - Fields (field:value), with fixed names and values:
      description:<text>, category:<category name>, bank:<bank>,
      statement_type:extrato|fatura (extrato = bank account, fatura = credit card bill),
      source:upload|open_finance,
      type:credit|debit|income|expense|investment (income, expense and investment follow
      the dashboard totals: expense excludes investments),
      amount (absolute value, no sign): amount > 100, amount:50..200,
      date: date:2026-03, date:2026-03-15, date:2026, date>=2026-01-01,
      date>=today-90d, date>=today-3m, date>=today-1y, date:2026-01..2026-03,
      year:2026, month:3 or month:mar, month:dec..feb, day:1..5,
      installments:N (1 means paid at once), installments>1,
      internal:true|false (transfers between the user's own accounts),
      recurrence:fixed|variable.
    - Comparisons >, >=, <, <= work with amount, date, year, month, day and installments.
    Examples:
      (uber OR 99 OR cabify) AND type:expense
      category:alimentacao AND date>=today-3m
      recurrence:fixed NOT internal:true
      description:pix* AND amount > 1000
    """
  end
end
