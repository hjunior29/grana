defmodule Granai.AI.Providers.Gemini do
  @behaviour Granai.AI.Provider

  @base_url "https://generativelanguage.googleapis.com/v1beta/models"

  @impl true
  def generate_content(prompt, config) do
    url = "#{@base_url}/#{config.model}:generateContent"

    body = %{
      contents: [%{parts: [%{text: prompt}]}],
      generationConfig: generation_config(config)
    }

    do_request(url, body, config)
  end

  @impl true
  def generate_content_with_file(file_base64, mime, prompt, config) do
    url = "#{@base_url}/#{config.model}:generateContent"

    body = %{
      contents: [
        %{
          parts: [
            %{inline_data: %{mime_type: mime, data: file_base64}},
            %{text: prompt}
          ]
        }
      ],
      generationConfig: generation_config(config)
    }

    do_request(url, body, config)
  end

  defp generation_config(config) do
    %{}
    |> maybe_put(:temperature, config[:temperature])
    |> maybe_put(:maxOutputTokens, config[:max_output_tokens])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)

  defp do_request(url, body, config) do
    opts =
      if config[:receive_timeout],
        do: [receive_timeout: config.receive_timeout],
        else: []

    headers = [{"x-goog-api-key", config.api_key}]

    case Req.post(url, [json: body, headers: headers] ++ opts) do
      {:ok, %{status: 200, body: resp}} ->
        {:ok, resp}

      {:ok, %{status: status, body: resp_body}} ->
        {:error, friendly_error(status, resp_body)}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, "A requisição demorou demais. Tente novamente."}

      {:error, %Req.TransportError{reason: :econnrefused}} ->
        {:error, "Não foi possível conectar ao servidor da API. Verifique sua conexão."}

      {:error, _reason} ->
        {:error, "Falha na conexão com a API. Verifique sua internet e tente novamente."}
    end
  end

  defp friendly_error(400, %{"error" => %{"status" => "INVALID_ARGUMENT"}}),
    do: "API Key inválida. Verifique sua chave nas Configurações."

  defp friendly_error(403, _),
    do: "API Key sem permissão. Verifique se a chave está ativa no Google AI Studio."

  defp friendly_error(429, _),
    do: "Limite de requisições atingido. Aguarde alguns minutos e tente novamente."

  defp friendly_error(500, _),
    do: "Erro interno do servidor da Google. Tente novamente em instantes."

  defp friendly_error(503, _),
    do: "Serviço temporariamente indisponível. Tente novamente em instantes."

  defp friendly_error(status, %{"error" => %{"message" => msg}}),
    do: "Erro da API (#{status}): #{msg}"

  defp friendly_error(status, _),
    do: "Erro inesperado da API (código #{status}). Tente novamente."
end
