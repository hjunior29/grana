defmodule Grana.AI.Catalog do
  @moduledoc """
  Model metadata from models.dev, an open catalog maintained by the community: family,
  release date, modalities and tool support for the models of every provider. It never
  decides what exists (the provider's API does); it only tells what each listed model is,
  so `Grana.AI.Models` can keep the text models and the recent ones without a list in
  the code. Fetched once a day; when unreachable, callers fall back to heuristics.
  """

  alias Grana.AI.HTTP
  alias Grana.Cache

  @url "https://models.dev/api.json"
  @cache_ttl_seconds 86_400

  @providers %{"gemini" => ["google"], "openai" => ["openai"], "anthropic" => ["anthropic"]}

  @type entry :: %{
          family: String.t(),
          released: Date.t() | nil,
          text?: boolean(),
          tools?: boolean(),
          pdf?: boolean()
        }

  @doc "The catalog grouped by provider (`%{provider => %{id => entry}}`), or `:unavailable`."
  @spec load() :: {:ok, map()} | :unavailable
  def load do
    Cache.get_or_store("ai_catalog", 0, :models_dev, &fetch/0,
      ttl_seconds: @cache_ttl_seconds,
      cache_if: &match?({:ok, _}, &1)
    )
  end

  @doc """
  The entry of `id` for a provider kind. Compatible services (OpenRouter, Ollama...) carry
  models from anyone, so for them the whole catalog is searched.
  """
  @spec lookup(map(), String.t(), String.t()) :: entry() | nil
  def lookup(catalog, kind, id) do
    providers = Map.get(@providers, kind, Map.keys(catalog))
    Enum.find_value(providers, fn provider -> get_in(catalog, [provider, id]) end)
  end

  @doc "Release date of the provider's newest model in the catalog (nil for compatible services)."
  @spec newest(map(), String.t()) :: Date.t() | nil
  def newest(catalog, kind) do
    for provider <- Map.get(@providers, kind, []),
        {_id, %{released: %Date{} = date}} <- Map.get(catalog, provider, %{}),
        reduce: nil do
      nil -> date
      acc -> if Date.compare(date, acc) == :gt, do: date, else: acc
    end
  end

  defp fetch do
    case HTTP.get(@url, []) do
      {:ok, body} when is_map(body) -> {:ok, compact(body)}
      _ -> :unavailable
    end
  end

  # Only what the curation needs stays in memory (the full catalog is several megabytes).
  defp compact(body) do
    Map.new(body, fn {provider, %{"models" => models}} ->
      {provider, Map.new(models, fn {id, model} -> {id, entry(model)} end)}
    end)
  end

  defp entry(model) do
    modalities = model["modalities"] || %{}

    %{
      family: model["family"] || "",
      released: parse_date(model["release_date"]),
      text?: "text" in (modalities["input"] || []) and modalities["output"] == ["text"],
      tools?: model["tool_call"] == true,
      pdf?: "pdf" in (modalities["input"] || [])
    }
  end

  defp parse_date(text) when is_binary(text) do
    case Date.from_iso8601(text) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(_text), do: nil
end
