defmodule Granai.AI.Providers.Gemini do
  @behaviour Granai.AI.Provider

  @base_url "https://generativelanguage.googleapis.com/v1beta/models"

  @impl true
  def generate_content(prompt, config) do
    url = "#{@base_url}/#{config.model}:generateContent?key=#{config.api_key}"

    body = %{
      contents: [%{parts: [%{text: prompt}]}],
      generationConfig: generation_config(config)
    }

    do_request(url, body, config)
  end

  @impl true
  def generate_content_with_file(file_base64, mime, prompt, config) do
    url = "#{@base_url}/#{config.model}:generateContent?key=#{config.api_key}"

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

    case Req.post(url, [json: body] ++ opts) do
      {:ok, %{status: 200, body: resp}} ->
        {:ok, resp}

      {:ok, %{status: status, body: resp_body}} ->
        {:error, "API error: #{status} - #{inspect(resp_body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end
end
