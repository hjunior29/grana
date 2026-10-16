defmodule Grana.LLMStub do
  @moduledoc """
  Scripts the replies of the LangChain chat models in tests by stubbing their `call/3`,
  the network boundary. Each model call takes the next reply in order:

    * a string: the assistant's text;
    * `{:tool, name, arguments}` or `{:tools, [{name, arguments}]}`: tool calls;
    * `{:error, message}`: a provider error;
    * `{:stream, parts}`: streamed parts, each a text or `{:thinking, text}`;
    * a function receiving the messages sent and returning any of the above.

  When the model streams (`stream: true`), text replies arrive word by word through the
  model's `on_llm_new_delta` callbacks, as with a real provider: as `ContentPart`s for
  Gemini and Anthropic, as plain strings for the OpenAI formats.

  Returns the pid of an agent that records the messages of every call (`calls/1`).
  """

  import Mimic

  alias LangChain.LangChainError
  alias LangChain.Message
  alias LangChain.Message.ContentPart
  alias LangChain.Message.ToolCall
  alias LangChain.MessageDelta

  @models [
    LangChain.ChatModels.ChatGoogleAI,
    LangChain.ChatModels.ChatOpenAI,
    LangChain.ChatModels.ChatAnthropic,
    LangChain.ChatModels.ChatOpenAICompatible
  ]

  def script(replies) do
    agent = ExUnit.Callbacks.start_supervised!({Agent, fn -> {replies, []} end}, id: make_ref())

    for module <- @models do
      stub(module, :call, fn model, messages, _tools -> next(agent, model, messages) end)
    end

    agent
  end

  @doc "Text of a message or tool result, for assertions."
  def text(%{content: content}), do: LangChain.Message.ContentPart.content_to_string(content)

  @doc "Every call made so far: `{model, messages}`, oldest first."
  def calls(agent), do: agent |> Agent.get(&elem(&1, 1)) |> Enum.reverse()

  defp next(agent, model, messages) do
    reply =
      Agent.get_and_update(agent, fn
        {[reply | rest], calls} -> {reply, {rest, [{model, messages} | calls]}}
        {[], _calls} -> raise "Grana.LLMStub: no scripted reply left"
      end)

    reply |> resolve(messages) |> to_response(model)
  end

  defp resolve(reply, messages) when is_function(reply, 1), do: reply.(messages)
  defp resolve(reply, _messages), do: reply

  defp to_response(text, %{stream: true} = model) when is_binary(text),
    do: to_response({:stream, String.split(text, ~r/(?<=\s)/, trim: true)}, model)

  # Like Anthropic, a thinking block comes first (index 0) and the text after it.
  defp to_response({:stream, parts}, model) do
    text_index = if Enum.any?(parts, &match?({:thinking, _}, &1)), do: 1, else: 0
    last = length(parts) - 1

    deltas =
      for {part, i} <- Enum.with_index(parts) do
        MessageDelta.new!(%{
          role: :assistant,
          content: content(model, part),
          index: if(match?({:thinking, _}, part), do: 0, else: text_index),
          status: if(i == last, do: :complete, else: :incomplete)
        })
      end

    Enum.each(deltas, &LangChain.Utils.fire_streamed_callback(model, [&1]))
    {:ok, deltas}
  end

  defp to_response(text, _model) when is_binary(text), do: {:ok, [Message.new_assistant!(text)]}

  defp to_response({:tool, name, arguments}, model),
    do: to_response({:tools, [{name, arguments}]}, model)

  defp to_response({:tools, calls}, _model) do
    tool_calls =
      for {name, arguments} <- calls do
        ToolCall.new!(%{
          call_id: "call_#{System.unique_integer([:positive])}",
          name: name,
          arguments: arguments,
          status: :complete
        })
      end

    {:ok, [Message.new_assistant!(%{tool_calls: tool_calls})]}
  end

  defp to_response({:error, message}, _model),
    do: {:error, LangChainError.exception(message: message)}

  defp content(_model, {:thinking, text}), do: ContentPart.new!(%{type: :thinking, content: text})

  defp content(%module{}, text)
       when module in [LangChain.ChatModels.ChatGoogleAI, LangChain.ChatModels.ChatAnthropic],
       do: ContentPart.text!(text)

  defp content(_model, text), do: text
end
