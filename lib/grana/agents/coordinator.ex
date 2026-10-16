defmodule Grana.Agents.Coordinator do
  @moduledoc """
  The chat coordinator. It answers with the deterministic data tools
  (`Grana.Agents.ChatTools`) and delegates to the specialists that expose a tool when
  the conversation asks for them. Each specialist runs with its own default model.

  The final answer is streamed: `notify` gets `{:delta, text}` as it is written and
  `{:tool, name}` as each tool starts (text written before a tool call is discarded).

  Earlier answers are replayed as text together with the tool results they used, so
  follow-up questions can rely on that data without depending on any provider's format
  for past tool calls (the model can change from one message to the next).
  """

  @behaviour Grana.Agents.Specialist

  alias Grana.Agents.Analyst
  alias Grana.Agents.ChatTools
  alias Grana.Agents.SearchBuilder
  alias Grana.AI
  alias Grana.AI.ChatModel
  alias Grana.AI.LLM
  alias LangChain.Chains.LLMChain
  alias LangChain.Message
  alias LangChain.Message.ContentPart
  alias LangChain.MessageDelta

  @specialists [Analyst, SearchBuilder]
  @max_runs 12
  @result_limit 4_000

  @impl true
  def key, do: "chat"

  @doc """
  `history` is the conversation, oldest first, ending with the user's message. Returns
  `{:ok, %{content:, tool_calls:, ai_provider:, ai_model:}}`.
  """
  def run(user_id, history, choice \\ nil, notify \\ fn _event -> :ok end) do
    with {:ok, config} <- AI.resolve(user_id, key(), choice),
         {:ok, chain} <- user_id |> build_chain(history, config, notify) |> run_chain() do
      {:ok,
       %{
         content: LLM.last_text(chain),
         tool_calls: tool_calls(chain.exchanged_messages),
         ai_provider: config.name,
         ai_model: config.model
       }}
    end
  end

  defp run_chain(chain), do: LLM.run(chain, mode: :while_needs_response, max_runs: @max_runs)

  defp build_chain(user_id, history, config, notify) do
    context = %{user_id: user_id}

    model =
      ChatModel.new(config,
        temperature: 0.3,
        max_tokens: 4096,
        receive_timeout: 120_000,
        stream: true
      )

    %{llm: model}
    |> LLMChain.new!()
    |> LLMChain.add_message(Message.new_system!(system_prompt()))
    |> LLMChain.add_messages(Enum.map(history, &to_message/1))
    |> LLMChain.add_tools(ChatTools.all(context) ++ Enum.map(@specialists, & &1.tool(context)))
    |> LLMChain.add_callback(%{
      on_tool_execution_started: fn _chain, call, _function -> notify.({:tool, call.name}) end,
      on_llm_new_delta: fn _chain, deltas ->
        case Enum.map_join(deltas, &delta_text/1) do
          "" -> :ok
          text -> notify.({:delta, text})
        end
      end
    })
  end

  defp delta_text(%MessageDelta{content: text}) when is_binary(text), do: text
  defp delta_text(%MessageDelta{content: %ContentPart{type: :text, content: text}}), do: text
  defp delta_text(_delta), do: ""

  defp to_message(%{role: "user", content: content}), do: Message.new_user!(content)

  defp to_message(%{role: "assistant", content: content, tool_calls: []}),
    do: Message.new_assistant!(content)

  defp to_message(%{role: "assistant", content: content, tool_calls: calls}) do
    data =
      Enum.map_join(calls, "\n", fn call ->
        "- #{call["name"]}(#{Jason.encode!(call["arguments"] || %{})}): #{call["result"]}"
      end)

    Message.new_assistant!(
      "#{content}\n\n[consulted data]\n<consulted_data>\n#{data}\n</consulted_data>"
    )
  end

  defp tool_calls(messages) do
    calls =
      for %Message{tool_calls: [_ | _] = calls} <- messages,
          call <- calls,
          into: %{},
          do: {call.call_id, call.arguments || %{}}

    for %Message{tool_results: [_ | _] = results} <- messages, result <- results do
      %{
        "name" => result.name,
        "arguments" => Map.get(calls, result.tool_call_id, %{}),
        "result" => result.content |> ContentPart.content_to_string() |> truncate(),
        "error" => result.is_error
      }
      |> Map.merge(details(result.name, result.processed_content))
    end
  end

  defp details("build_search", %{query: query}), do: %{"query" => query}

  defp details("analyze_period", %{ai_provider: provider, ai_model: model}),
    do: %{"ai_provider" => provider, "ai_model" => model}

  defp details(_name, _processed), do: %{}

  defp truncate(nil), do: ""

  defp truncate(text) do
    if String.length(text) > @result_limit,
      do: String.slice(text, 0, @result_limit) <> "…",
      else: text
  end

  defp system_prompt do
    """
    You are the assistant of Grana, a personal finance app used in Brazil. You talk with
    the app's owner about their own money: transactions, statements (extrato) and credit
    card bills (fatura), by month, year, bank, category, income or expenses.

    Always reply in Brazilian Portuguese, short and direct.

    Rules:
    - Every number must come from a tool. Call the tools before answering; never estimate
      or invent values, periods, merchants or categories.
    - Use get_data_overview when you do not know which periods, banks or categories exist.
    - For a concept (health, transport, delivery, a person), call list_merchants first and
      search the merchants that belong to it, even the ones filed under another category.
    - Prefer the totals the tools return over doing arithmetic yourself.
    - For a full analysis of a month or a year (score, insights, tips), call analyze_period.
    - When the user wants a search for the transactions screen, call build_search and give
      the query back exactly as returned.
    - If the data needed is not available, say so plainly.
    - Money in the Brazilian format (R$ 1.234,56). Dates as DD/MM/YYYY.
    - Answer as an HTML fragment, not Markdown and not a full document. Allowed tags:
      p, br, strong, em, small, ul, ol, li, table, thead, tbody, tr, th, td, dl, dt, dd,
      span. Anything else is removed.
    - Lay the numbers out so they are easy to scan: a table when comparing several
      items or periods, a list for a few items, a sentence for one figure. Keep text
      short: one or two sentences around the data, no long explanations.
    - Classes you may use: class="income" on money coming in, class="expense" on money
      going out, class="muted" for secondary notes, class="num" on table cells with
      numbers. No other attributes.
    - Earlier answers may end with a "[consulted data]" note listing the tool results
      they used. You can rely on it, but never write such a note yourself.

    Today is #{Date.utc_today()}.
    """
  end
end
