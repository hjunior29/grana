defmodule Grana.Investments.QuoteProvider do
  @moduledoc """
  Busca cotações de ativos via brapi.dev com cache ETS (TTL 30 min).
  """

  require Logger

  @table :quote_cache
  @ttl_ms :timer.minutes(30)
  @base_url "https://brapi.dev/api/quote"

  def get_quotes([]), do: {:ok, %{}}

  def get_quotes(tickers) when is_list(tickers) do
    tickers = tickers |> Enum.map(&String.upcase/1) |> Enum.uniq()

    ensure_table()
    {cached, missing} = split_cached(tickers)

    case fetch_missing(missing) do
      {:ok, fetched} ->
        {:ok, Map.merge(cached, fetched)}

      {:error, reason} ->
        Logger.warning("QuoteProvider: API fetch failed (#{inspect(reason)}), using stale cache")
        stale = lookup_stale(missing)
        {:ok, Map.merge(cached, stale)}
    end
  end

  defp split_cached(tickers) do
    now = System.monotonic_time(:millisecond)

    Enum.reduce(tickers, {%{}, []}, fn ticker, {cached, missing} ->
      case :ets.lookup(@table, ticker) do
        [{^ticker, data, ts}] when now - ts < @ttl_ms ->
          {Map.put(cached, ticker, data), missing}

        _ ->
          {cached, [ticker | missing]}
      end
    end)
  end

  defp lookup_stale(tickers) do
    Enum.reduce(tickers, %{}, fn ticker, acc ->
      case :ets.lookup(@table, ticker) do
        [{^ticker, data, _ts}] -> Map.put(acc, ticker, data)
        _ -> acc
      end
    end)
  end

  defp fetch_missing([]), do: {:ok, %{}}

  defp fetch_missing(tickers) do
    token = Application.get_env(:grana, :brapi_token)

    if is_nil(token) or token == "" do
      Logger.warning("QuoteProvider: BRAPI_TOKEN not configured")
      {:error, :no_token}
    else
      joined = Enum.join(tickers, ",")
      url = "#{@base_url}/#{joined}?token=#{token}"

      Logger.debug("QuoteProvider: fetching #{length(tickers)} tickers from brapi.dev")

      case Req.get(url, receive_timeout: 15_000) do
        {:ok, %Req.Response{status: 200, body: %{"results" => results}}} ->
          now = System.monotonic_time(:millisecond)

          map =
            results
            |> Enum.reduce(%{}, fn r, acc ->
              symbol = r["symbol"]

              data = %{
                price: decimal(r["regularMarketPrice"]),
                change: decimal(r["regularMarketChange"]),
                change_pct: r["regularMarketChangePercent"],
                previous_close: decimal(r["regularMarketPreviousClose"]),
                logo_url: r["logourl"]
              }

              :ets.insert(@table, {symbol, data, now})
              Map.put(acc, symbol, data)
            end)

          Logger.debug("QuoteProvider: fetched #{map_size(map)} quotes successfully")
          {:ok, map}

        {:ok, %Req.Response{status: status, body: body}} ->
          Logger.warning("QuoteProvider: API returned status #{status}: #{inspect(body)}")
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          Logger.warning("QuoteProvider: HTTP error: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:set, :public, :named_table])
      _ -> @table
    end
  end

  defp decimal(nil), do: Decimal.new(0)
  defp decimal(val) when is_float(val), do: Decimal.from_float(val)
  defp decimal(val) when is_integer(val), do: Decimal.new(val)
  defp decimal(val) when is_binary(val), do: Decimal.new(val)
end
