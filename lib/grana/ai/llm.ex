defmodule Grana.AI.LLM do
  @moduledoc """
  Runs LangChain chains for the specialists. A model that rejects a custom temperature
  (reasoning models) is retried once with the provider default, a streamed run that fails
  is retried once without streaming (some compatible servers handle it badly), and
  failures come back as messages for the user.
  """

  alias Grana.AI.ChatModel
  alias LangChain.Chains.LLMChain
  alias LangChain.LangChainError
  alias LangChain.Message
  alias LangChain.Message.ContentPart

  @spec run(LLMChain.t(), keyword()) :: {:ok, LLMChain.t()} | {:error, String.t()}
  def run(%LLMChain{} = chain, opts \\ []) do
    case LLMChain.run(chain, opts) do
      {:ok, chain} ->
        {:ok, chain}

      # The "until tool used" mode also hands back the tool result that ended the run.
      {:ok, chain, _tool_result} ->
        {:ok, chain}

      {:error, _chain, error} ->
        cond do
          temperature_error?(error) ->
            chain |> Map.update!(:llm, &ChatModel.default_temperature/1) |> retry(opts)

          chain.llm.stream ->
            chain |> Map.update!(:llm, &%{&1 | stream: false}) |> retry(opts)

          true ->
            {:error, message(error)}
        end
    end
  end

  defp retry(chain, opts) do
    case LLMChain.run(chain, opts) do
      {:ok, chain} -> {:ok, chain}
      {:ok, chain, _tool_result} -> {:ok, chain}
      {:error, _chain, error} -> {:error, message(error)}
    end
  end

  @doc "Text of the chain's last message."
  def last_text(%LLMChain{last_message: %Message{content: content}}),
    do: ContentPart.content_to_string(content) || ""

  def last_text(_chain), do: ""

  defp temperature_error?(%LangChainError{message: message}) when is_binary(message),
    do: String.contains?(String.downcase(message), "temperature")

  defp temperature_error?(_error), do: false

  defp message(%LangChainError{type: "timeout"}),
    do: "A IA demorou demais para responder. Tente novamente."

  defp message(%LangChainError{type: "exceeded_max_runs"}),
    do: "A IA não chegou a uma resposta. Tente reformular o pedido."

  defp message(%LangChainError{type: type}) when type in ["rate_limited", "too_many_requests"],
    do: "Limite de requisições do provedor atingido. Aguarde alguns minutos e tente novamente."

  defp message(%LangChainError{message: message}) when is_binary(message) do
    redacted = Regex.replace(~r/([?&]key=)[^&\s]+/, message, "\\1[redigido]")
    "A IA respondeu com erro: #{redacted}"
  end

  defp message(_error), do: "Não foi possível falar com a IA. Tente novamente."
end
