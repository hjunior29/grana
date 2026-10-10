defmodule Grana.AI.Providers.OpenAI do
  @moduledoc """
  API de chat completions da OpenAI e de qualquer serviço compatível (OpenRouter,
  Groq, Together, Ollama, LM Studio...), pelo `base_url` do provedor.

  Os parâmetros que variam de modelo para modelo (`temperature`, `max_tokens` vs
  `max_completion_tokens`, `reasoning_effort`) não são mapeados por modelo: se a API
  recusa um deles, ele é ajustado ou removido e o pedido é refeito. Assim modelos
  novos funcionam sem mexer no código.
  """

  @behaviour Grana.AI.Provider

  alias Grana.AI.HTTP

  @default_base_url "https://api.openai.com/v1"
  @max_retries 3

  @impl true
  def generate_content(prompt, config) do
    chat(config, [%{role: "user", content: prompt}])
  end

  @impl true
  def generate_content_with_file(file_base64, mime, prompt, config) do
    data_url = "data:#{mime};base64,#{file_base64}"

    attachment =
      if String.starts_with?(mime, "image/"),
        do: %{type: "image_url", image_url: %{url: data_url}},
        else: %{type: "file", file: %{filename: "documento.pdf", file_data: data_url}}

    chat(config, [%{role: "user", content: [%{type: "text", text: prompt}, attachment]}])
  end

  defp chat(config, messages) do
    params =
      %{}
      |> put_param("temperature", config[:temperature])
      |> put_param(max_tokens_key(config), config[:max_output_tokens])

    request(config, messages, params, @max_retries)
  end

  # A OpenAI exige max_completion_tokens nos modelos novos; os compatíveis ainda
  # usam max_tokens. Se errar, o retry troca.
  defp max_tokens_key(%{provider: "openai"}), do: "max_completion_tokens"
  defp max_tokens_key(_config), do: "max_tokens"

  defp put_param(params, _key, nil), do: params
  defp put_param(params, key, value), do: Map.put(params, key, value)

  defp request(config, messages, params, retries) do
    body = Map.merge(params, %{"model" => config.model, "messages" => messages})

    case HTTP.post(url(config), headers(config), body, config) do
      {:ok, response} ->
        {:ok, response}

      {:http_error, 400, error_body} = error when retries > 0 ->
        case adjust(params, HTTP.message(error_body)) do
          {:ok, adjusted} -> request(config, messages, adjusted, retries - 1)
          :error -> to_error(error, config)
        end

      {:http_error, _, _} = error ->
        to_error(error, config)

      {:error, _} = error ->
        error
    end
  end

  defp adjust(params, message) when is_binary(message) do
    cond do
      Map.has_key?(params, "max_tokens") and String.contains?(message, "max_completion_tokens") ->
        {:ok,
         params
         |> Map.put("max_completion_tokens", params["max_tokens"])
         |> Map.delete("max_tokens")}

      key = Enum.find(Map.keys(params), &String.contains?(message, &1)) ->
        {:ok, Map.delete(params, key)}

      true ->
        :error
    end
  end

  defp adjust(_params, _message), do: :error

  defp to_error({:http_error, status, body}, config),
    do: {:error, HTTP.friendly_error(status, body, label(config))}

  defp label(%{name: name}) when is_binary(name), do: name
  defp label(_), do: "o provedor de IA"

  defp url(config), do: String.trim_trailing(base_url(config), "/") <> "/chat/completions"

  @doc false
  def base_url(config) do
    case config[:base_url] do
      url when is_binary(url) and url != "" -> url
      _ -> @default_base_url
    end
  end

  defp headers(%{api_key: key}) when is_binary(key) and key != "",
    do: [{"authorization", "Bearer #{key}"}]

  defp headers(_config), do: []
end
