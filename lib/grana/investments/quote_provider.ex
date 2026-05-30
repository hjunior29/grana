defmodule Grana.Investments.QuoteProvider do
  @moduledoc """
  Busca cotações de ativos via brapi.dev com cache ETS (TTL 30 min).
  """

  require Logger

  @table :quote_cache
  @ttl_ms :timer.minutes(30)
  @base_url "https://brapi.dev/api/quote"

  def get_quotes(tickers, opts \\ [])

  def get_quotes([], _opts), do: {:ok, %{}}

  def get_quotes(tickers, opts) when is_list(tickers) do
    tickers = tickers |> Enum.map(&String.upcase/1) |> Enum.uniq()

    ensure_table()
    {cached, missing} = split_cached(tickers)

    # When fetch_remote is false (e.g. a disconnected LiveView render), never make
    # the blocking external HTTP call — serve whatever is cached (fresh or stale).
    # The connected render / QuoteFetcher cron refreshes the cache.
    if Keyword.get(opts, :fetch_remote, true) do
      case fetch_missing(missing) do
        {:ok, fetched} ->
          {:ok, Map.merge(cached, fetched)}

        {:error, reason} ->
          Logger.warning(
            "QuoteProvider: API fetch failed (#{inspect(reason)}), using stale cache"
          )

          stale = lookup_stale(missing)
          {:ok, Map.merge(cached, stale)}
      end
    else
      {:ok, Map.merge(cached, lookup_stale(missing))}
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
      Logger.info(
        "QuoteProvider: fetching #{length(tickers)} tickers: #{Enum.join(tickers, ",")}"
      )

      results =
        tickers
        |> Task.async_stream(
          fn ticker -> {ticker, fetch_one(ticker, token)} end,
          max_concurrency: 3,
          timeout: 20_000
        )
        |> Enum.reduce(%{}, fn
          {:ok, {_ticker, {:ok, symbol, data}}}, acc ->
            Map.put(acc, symbol, data)

          {:ok, {ticker, {:error, reason}}}, acc ->
            Logger.warning("QuoteProvider: failed to fetch #{ticker}: #{inspect(reason)}")
            acc

          {:exit, reason}, acc ->
            Logger.warning("QuoteProvider: task exited: #{inspect(reason)}")
            acc
        end)

      Logger.info("QuoteProvider: fetched #{map_size(results)}/#{length(tickers)} quotes")
      {:ok, results}
    end
  end

  defp fetch_one(ticker, token) do
    url = "#{@base_url}/#{ticker}"

    # Token vai no header Authorization (não na query string), evitando vazar a
    # credencial em logs de acesso/proxy. brapi.dev aceita Bearer token.
    case Req.get(url,
           auth: {:bearer, token},
           receive_timeout: 15_000
         ) do
      {:ok, %Req.Response{status: 200, body: %{"results" => [r | _]}}} ->
        now = System.monotonic_time(:millisecond)
        symbol = r["symbol"]

        data = %{
          price: decimal(r["regularMarketPrice"]),
          change: decimal(r["regularMarketChange"]),
          change_pct: r["regularMarketChangePercent"],
          previous_close: decimal(r["regularMarketPreviousClose"]),
          logo_url: r["logourl"]
        }

        Logger.info("QuoteProvider: #{symbol} = R$ #{data.price}")
        :ets.insert(@table, {symbol, data, now})
        {:ok, symbol, data}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:set, :public, :named_table])
      _ -> @table
    end
  end

  defp decimal(nil), do: Decimal.new(0)
  defp decimal(val) when is_float(val), do: val |> Decimal.from_float() |> Decimal.round(8)
  defp decimal(val) when is_integer(val), do: Decimal.new(val)
  defp decimal(val) when is_binary(val), do: Decimal.new(val)
end
