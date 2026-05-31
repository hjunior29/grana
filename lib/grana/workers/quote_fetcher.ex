defmodule Grana.Workers.QuoteFetcher do
  @moduledoc """
  Cron worker that refreshes stock quotes in the ETS cache every 30 minutes.
  """
  use Oban.Worker, queue: :quotes, max_attempts: 3

  require Logger

  alias Grana.Investments

  @impl Oban.Worker
  def perform(_job) do
    tickers = Investments.all_active_tickers_global()

    case tickers do
      [] ->
        Logger.info("QuoteFetcher: no active tickers to fetch")
        :ok

      tickers ->
        Logger.info("QuoteFetcher: refreshing #{length(tickers)} tickers")

        {:ok, quotes} = Investments.QuoteProvider.get_quotes(tickers)
        Logger.info("QuoteFetcher: refreshed #{map_size(quotes)} quotes")
        :ok
    end
  end
end
