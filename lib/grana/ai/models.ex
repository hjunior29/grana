defmodule Grana.AI.Models do
  @moduledoc """
  Catálogo de modelos lido **da própria API de cada provedor** (`/models`), em vez de
  uma lista no código: um modelo novo aparece sozinho, sem deploy. Só ficam os modelos
  de texto/chat, descartados por palavras que indicam outra capacidade (embedding,
  áudio, imagem...), e a lista vem do mais novo para o mais antigo.
  """

  alias Grana.AI.HTTP
  alias Grana.AI.Providers.OpenAI

  @type model :: %{id: String.t(), name: String.t()}

  @not_chat ~w(embed tts whisper transcribe audio realtime image imagen dall-e moderation
               veo search-preview guard rerank robotics computer-use)

  @gemini_url "https://generativelanguage.googleapis.com/v1beta/models"
  @anthropic_url "https://api.anthropic.com/v1/models"

  @doc "Modelos disponíveis para a configuração do provedor (`kind`, `api_key`, `base_url`)."
  @spec list(map()) :: {:ok, [model()]} | {:error, String.t()}
  def list(%{provider: "gemini"} = config) do
    with {:ok, body} <-
           fetch(@gemini_url, [{"x-goog-api-key", config.api_key}], [pageSize: 1000], config) do
      models =
        for %{"name" => "models/" <> id} = m <- body["models"] || [],
            "generateContent" in (m["supportedGenerationMethods"] || []),
            chat?(id) do
          %{id: id, name: m["displayName"] || id}
        end

      {:ok, models |> Enum.sort_by(& &1.id, :desc) |> Enum.sort_by(&gemini_first/1)}
    end
  end

  def list(%{provider: "anthropic"} = config) do
    headers = [
      {"x-api-key", config.api_key},
      {"anthropic-version", Grana.AI.Providers.Anthropic.version()}
    ]

    with {:ok, body} <- fetch(@anthropic_url, headers, [limit: 1000], config) do
      # A Anthropic já devolve do mais novo para o mais antigo.
      {:ok,
       for(%{"id" => id} = m <- body["data"] || [], do: %{id: id, name: m["display_name"] || id})}
    end
  end

  def list(%{provider: kind} = config) when kind in ["openai", "openai_compatible"] do
    url = String.trim_trailing(OpenAI.base_url(config), "/") <> "/models"

    headers =
      if config[:api_key] in [nil, ""],
        do: [],
        else: [{"authorization", "Bearer #{config.api_key}"}]

    with {:ok, body} <- fetch(url, headers, [], config) do
      models =
        for %{"id" => id} = m <- body["data"] || [], chat?(id), do: {m["created"] || 0, id}

      {:ok, models |> Enum.sort(:desc) |> Enum.map(fn {_created, id} -> %{id: id, name: id} end)}
    end
  end

  @doc """
  Modelo sugerido como padrão quando o usuário ainda não escolheu: o primeiro da
  família "barata e rápida" do provedor (muitas chamadas de categorização), ou o mais
  novo da lista.
  """
  @spec suggest(String.t(), [model()]) :: String.t() | nil
  def suggest(_kind, []), do: nil

  def suggest(kind, models) do
    pattern = preferred(kind)
    found = pattern && Enum.find(models, &Regex.match?(pattern, &1.id))
    (found || hd(models)).id
  end

  defp preferred("gemini"), do: ~r/flash(?!.*(lite|exp|preview|image))/
  defp preferred("anthropic"), do: ~r/sonnet/
  defp preferred("openai"), do: ~r/^gpt-[\d.]+-mini$/
  defp preferred(_), do: nil

  defp chat?(id), do: not Enum.any?(@not_chat, &String.contains?(String.downcase(id), &1))

  # Gemma e afins vêm depois dos Gemini; dentro de cada grupo, o mais novo primeiro.
  defp gemini_first(%{id: "gemini" <> _}), do: 0
  defp gemini_first(_), do: 1

  defp fetch(url, headers, params, config) do
    case HTTP.get(url, headers, params) do
      {:ok, body} when is_map(body) ->
        {:ok, body}

      {:ok, _other} ->
        {:error, "A resposta do provedor não parece uma lista de modelos. Confira o endereço."}

      {:http_error, status, body} ->
        {:error, HTTP.friendly_error(status, body, config[:name] || "o provedor")}

      {:error, _} = error ->
        error
    end
  end
end
