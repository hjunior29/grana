defmodule Grana.AI.Models do
  @moduledoc """
  Models available to a provider, read **from the provider's own API** (`/models`) and
  never from a list in the code: a new model shows up by itself.

  The raw list is then curated with the metadata of `Grana.AI.Catalog`: only models that
  take text and answer text with tool support stay, each family keeps its newest release,
  and families older than a year (next to the provider's newest model) are left out, so
  the picker shows what people actually use. A model the catalog does not know only stays
  when it is newer than everything the catalog has for that provider (released today);
  compatible services, whose models the catalog cannot cover, keep the keyword heuristics.
  Newest first.
  """

  alias Grana.AI.Catalog
  alias Grana.AI.HTTP
  alias Grana.Cache

  @typedoc "`pdf` says whether the model reads PDF files; nil when the catalog does not know it."
  @type model :: %{id: String.t(), name: String.t(), pdf: boolean() | nil}

  @not_chat ~w(embed tts whisper transcribe audio realtime live sora image imagen dall-e
               moderation veo search-preview guard rerank robotics computer-use)

  # Snapshots like gpt-4o-2024-11-20, claude-opus-4-5-20251101 or gemini-...-preview-04-2026.
  @dated ~r/-(\d{4}-\d{2}-\d{2}|\d{8}|\d{2}-\d{4}|\d{4})$/

  @gemini_url "https://generativelanguage.googleapis.com/v1beta/models"
  @anthropic_url "https://api.anthropic.com/v1/models"
  @anthropic_version "2023-06-01"
  @openai_url "https://api.openai.com/v1"

  @max_age_days 365

  # The list rarely changes: one hour of cache, successful answers only.
  @cache_ttl_seconds 3600

  @doc """
  Models for the provider config (`provider`, `api_key`, `base_url`), curated.

  Cached per provider + base URL + key (the key only as a hash), so a new key queries
  again. Errors are never cached.
  """
  @spec list(map()) :: {:ok, [model()]} | {:error, String.t()}
  def list(config) do
    # User 0 = shared: the list does not depend on the user's data, so it must survive
    # `Cache.invalidate_user/1` on every upload.
    Cache.get_or_store("ai_models", 0, cache_key(config), fn -> fetch(config) end,
      ttl_seconds: @cache_ttl_seconds,
      cache_if: &match?({:ok, _}, &1)
    )
  end

  @doc "Only what is already cached (no network): `{:ok, models}` or `:miss`."
  @spec cached(map()) :: {:ok, [model()]} | :miss
  def cached(config) do
    case Cache.peek("ai_models", 0, cache_key(config)) do
      {:ok, {:ok, models}} -> {:ok, models}
      _ -> :miss
    end
  end

  defp cache_key(config) do
    key_hash = :crypto.hash(:sha256, config[:api_key] || "")
    {config.provider, config[:base_url], key_hash}
  end

  defp fetch(config) do
    with {:ok, raw} <- fetch_raw(config) do
      {:ok, curate(config.provider, raw)}
    end
  end

  # Raw models: `%{id, name, created}` (`created` is a Date when the API gives one).
  defp fetch_raw(%{provider: "gemini"} = config) do
    with {:ok, body} <-
           fetch(@gemini_url, [{"x-goog-api-key", config.api_key}], [pageSize: 1000], config) do
      {:ok,
       for %{"name" => "models/" <> id} = m <- body["models"] || [],
           "generateContent" in (m["supportedGenerationMethods"] || []) do
         %{id: id, name: m["displayName"] || id, created: nil}
       end}
    end
  end

  defp fetch_raw(%{provider: "anthropic"} = config) do
    headers = [{"x-api-key", config.api_key}, {"anthropic-version", @anthropic_version}]

    with {:ok, body} <- fetch(@anthropic_url, headers, [limit: 1000], config) do
      {:ok,
       for %{"id" => id} = m <- body["data"] || [] do
         %{id: id, name: m["display_name"] || id, created: iso_date(m["created_at"])}
       end}
    end
  end

  defp fetch_raw(%{provider: kind} = config) when kind in ["openai", "openai_compatible"] do
    url = String.trim_trailing(base_url(config), "/") <> "/models"

    headers =
      if config[:api_key] in [nil, ""],
        do: [],
        else: [{"authorization", "Bearer #{config.api_key}"}]

    with {:ok, body} <- fetch(url, headers, [], config) do
      {:ok,
       for %{"id" => id} = m <- body["data"] || [] do
         %{id: id, name: id, created: unix_date(m["created"])}
       end}
    end
  end

  @doc """
  Curates a provider's raw list with the catalog. Public for the tests of the rules;
  `list/1` always goes through it.
  """
  @spec curate(String.t(), [map()]) :: [model()]
  def curate(kind, raw) do
    case Catalog.load() do
      {:ok, catalog} -> curate(kind, raw, catalog)
      :unavailable -> raw |> Enum.filter(&chat?(&1.id)) |> sort(kind) |> Enum.map(&public/1)
    end
  end

  @doc "Only the models that can read PDF files (unknown ones stay)."
  @spec for_pdf([model()]) :: [model()]
  def for_pdf(models), do: Enum.reject(models, &(&1[:pdf] == false))

  defp curate(kind, raw, catalog) do
    newest = Catalog.newest(catalog, kind)

    models =
      raw
      |> Enum.map(&annotate(&1, Catalog.lookup(catalog, kind, &1.id)))
      |> Enum.filter(&usable?(&1, newest))

    cutoff = cutoff(models)

    models
    |> Enum.reject(&(&1.released && Date.compare(&1.released, cutoff) == :lt))
    |> newest_per_family()
    |> sort(kind)
    |> Enum.map(&public/1)
  end

  defp annotate(model, nil),
    do: Map.merge(model, %{known?: false, released: model.created, pdf: nil})

  defp annotate(model, entry) do
    Map.merge(model, %{
      known?: true,
      family: entry.family,
      released: entry.released || model.created,
      text?: entry.text?,
      tools?: entry.tools?,
      pdf: entry.pdf?
    })
  end

  # Known models need text in and out plus tools. Unknown ones pass the heuristics and,
  # when the catalog covers the provider, must be newer than its newest model.
  defp usable?(%{known?: true} = model, _newest), do: model.text? and model.tools?

  defp usable?(model, newest) do
    chat?(model.id) and not Regex.match?(@dated, model.id) and
      (is_nil(newest) or (model.created != nil and Date.compare(model.created, newest) == :gt))
  end

  defp cutoff(models) do
    case models |> Enum.map(& &1.released) |> Enum.reject(&is_nil/1) do
      [] -> ~D[0000-01-01]
      dates -> dates |> Enum.max(Date) |> Date.add(-@max_age_days)
    end
  end

  # Within a family only the newest release stays; on the same date, the plain id
  # (`claude-haiku-4-5`) beats its dated snapshot.
  defp newest_per_family(models) do
    {known, unknown} = Enum.split_with(models, & &1.known?)

    kept =
      known
      |> Enum.group_by(& &1.family)
      |> Enum.map(fn {_family, members} ->
        Enum.max_by(members, &{iso(&1.released), -String.length(&1.id)})
      end)

    kept ++ unknown
  end

  # Newest first (models without a date last); Gemma and alike after the Geminis.
  defp sort(models, kind) do
    models
    |> Enum.sort_by(& &1.id, :desc)
    |> Enum.sort_by(&iso(&1[:released] || &1[:created]), :desc)
    |> Enum.sort_by(&(kind == "gemini" and not String.starts_with?(&1.id, "gemini")))
  end

  defp iso(nil), do: "0000-00-00"
  defp iso(date), do: Date.to_iso8601(date)

  defp public(model), do: %{id: model.id, name: model.name, pdf: model[:pdf]}

  @doc """
  Suggested default when the user has not chosen one: the first of the provider's
  "cheap and fast" family (many categorization calls), or the newest in the list.
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

  defp base_url(%{base_url: url}) when is_binary(url) and url != "", do: url
  defp base_url(_config), do: @openai_url

  defp chat?(id), do: not Enum.any?(@not_chat, &String.contains?(String.downcase(id), &1))

  defp unix_date(seconds) when is_integer(seconds) and seconds > 0,
    do: seconds |> DateTime.from_unix!() |> DateTime.to_date()

  defp unix_date(_value), do: nil

  defp iso_date(text) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, datetime, _offset} -> DateTime.to_date(datetime)
      _ -> nil
    end
  end

  defp iso_date(_value), do: nil

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
