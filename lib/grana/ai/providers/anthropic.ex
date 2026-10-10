defmodule Grana.AI.Providers.Anthropic do
  @moduledoc """
  API de mensagens da Anthropic (Claude). Como na OpenAI, parâmetros que um modelo
  recusa (ex.: `temperature`) são removidos e o pedido é refeito, sem mapa por modelo.
  """

  @behaviour Grana.AI.Provider

  alias Grana.AI.HTTP

  @url "https://api.anthropic.com/v1/messages"
  @version "2023-06-01"
  @default_max_tokens 8192
  @max_retries 2

  @impl true
  def generate_content(prompt, config) do
    request(config, [%{type: "text", text: prompt}])
  end

  @impl true
  def generate_content_with_file(file_base64, mime, prompt, config) do
    type = if String.starts_with?(mime, "image/"), do: "image", else: "document"

    attachment = %{
      type: type,
      source: %{type: "base64", media_type: mime, data: file_base64}
    }

    request(config, [attachment, %{type: "text", text: prompt}])
  end

  defp request(config, content) do
    optional = if config[:temperature], do: %{"temperature" => config[:temperature]}, else: %{}
    do_request(config, content, optional, @max_retries)
  end

  defp do_request(config, content, optional, retries) do
    body =
      Map.merge(optional, %{
        "model" => config.model,
        "max_tokens" => config[:max_output_tokens] || @default_max_tokens,
        "messages" => [%{role: "user", content: content}]
      })

    case HTTP.post(@url, headers(config), body, config) do
      {:ok, response} ->
        {:ok, response}

      {:http_error, 400, error_body} = error when retries > 0 ->
        message = HTTP.message(error_body) || ""

        case Enum.find(Map.keys(optional), &String.contains?(message, &1)) do
          nil -> to_error(error, config)
          key -> do_request(config, content, Map.delete(optional, key), retries - 1)
        end

      {:http_error, _, _} = error ->
        to_error(error, config)

      {:error, _} = error ->
        error
    end
  end

  defp to_error({:http_error, status, body}, config),
    do: {:error, HTTP.friendly_error(status, body, config[:name] || "a Anthropic")}

  defp headers(config) do
    [{"x-api-key", config.api_key}, {"anthropic-version", @version}]
  end

  @doc false
  def version, do: @version
end
