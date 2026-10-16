defmodule Grana.AI.ChatModel do
  @moduledoc """
  Builds the LangChain chat model for a config resolved by `Grana.AI.resolve/3`.
  OpenAI-compatible services get the chat completions route of their base URL.
  """

  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.ChatModels.ChatGoogleAI
  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.ChatModels.ChatOpenAICompatible

  @default_receive_timeout 60_000

  @doc """
  Options: `:temperature`, `:max_tokens` (ignored by Gemini, which has no such field),
  `:receive_timeout` and `:stream`.
  """
  def new(%{provider: kind, model: model} = config, opts \\ []) do
    attrs =
      %{model: model, receive_timeout: opts[:receive_timeout] || @default_receive_timeout}
      |> put(:api_key, blank_to_nil(config[:api_key]))
      |> put(:temperature, opts[:temperature])
      |> put(:stream, opts[:stream])

    build(kind, attrs, config, opts[:max_tokens])
  end

  defp build("gemini", attrs, _config, _max_tokens), do: ChatGoogleAI.new!(attrs)

  defp build("anthropic", attrs, _config, max_tokens),
    do: attrs |> put(:max_tokens, max_tokens) |> ChatAnthropic.new!()

  defp build("openai", attrs, _config, max_tokens),
    do: attrs |> put(:max_tokens, max_tokens) |> ChatOpenAI.new!()

  defp build("openai_compatible", attrs, config, max_tokens) do
    endpoint = String.trim_trailing(config.base_url, "/") <> "/chat/completions"

    attrs
    |> Map.put(:endpoint, endpoint)
    |> put(:max_tokens, max_tokens)
    |> ChatOpenAICompatible.new!()
  end

  @doc "Same model with the provider's default temperature (for models that reject a custom one)."
  def default_temperature(%ChatOpenAI{} = model), do: %{model | temperature: 1.0}
  def default_temperature(%ChatAnthropic{} = model), do: %{model | temperature: 1.0}
  def default_temperature(%ChatGoogleAI{} = model), do: %{model | temperature: 1.0}
  def default_temperature(%ChatOpenAICompatible{} = model), do: %{model | temperature: nil}

  defp put(map, _key, nil), do: map
  defp put(map, key, value), do: Map.put(map, key, value)

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
