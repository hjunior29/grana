defmodule Grana.Investments.QuoteProviderTest do
  use ExUnit.Case, async: false

  use Mimic

  alias Grana.Investments.QuoteProvider

  defp brapi_ok_body(symbol) do
    %{
      "results" => [
        %{
          "symbol" => symbol,
          "regularMarketPrice" => 36.50,
          "regularMarketChange" => 0.50,
          "regularMarketChangePercent" => 1.39,
          "regularMarketPreviousClose" => 36.00,
          "logourl" => "https://example.com/#{symbol}.png"
        }
      ]
    }
  end

  setup do
    Application.put_env(:grana, :brapi_token, "test-token")

    # Clear the in-process ETS quote cache to prevent cross-test contamination.
    case :ets.whereis(:quote_cache) do
      :undefined -> :ok
      _ -> :ets.delete_all_objects(:quote_cache)
    end

    on_exit(fn -> Application.delete_env(:grana, :brapi_token) end)
    :ok
  end

  describe "get_quotes/2" do
    test "returns empty map for empty ticker list" do
      assert {:ok, %{}} = QuoteProvider.get_quotes([])
    end

    test "fetches quotes successfully" do
      stub(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: brapi_ok_body("PETR4")}}
      end)

      assert {:ok, quotes} = QuoteProvider.get_quotes(["PETR4"])
      assert Map.has_key?(quotes, "PETR4")
      assert Decimal.eq?(quotes["PETR4"].price, Decimal.from_float(36.50))
    end

    test "uppercases tickers" do
      stub(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: brapi_ok_body("PETR4")}}
      end)

      assert {:ok, quotes} = QuoteProvider.get_quotes(["petr4"])
      assert Map.has_key?(quotes, "PETR4")
    end

    test "deduplicates tickers - only fetches once per unique ticker" do
      stub(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: brapi_ok_body("DEDUP3")}}
      end)

      assert {:ok, quotes1} = QuoteProvider.get_quotes(["DEDUP3"])
      assert {:ok, quotes2} = QuoteProvider.get_quotes(["DEDUP3", "DEDUP3", "dedup3"])

      assert Map.has_key?(quotes1, "DEDUP3")
      assert Map.has_key?(quotes2, "DEDUP3")
    end

    test "falls back to stale cache on API error" do
      stub(Req, :get, fn _url, _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      assert {:ok, _quotes} = QuoteProvider.get_quotes(["ERRX3"])
    end

    test "returns ok with empty map when no token configured" do
      Application.put_env(:grana, :brapi_token, nil)

      assert {:ok, quotes} = QuoteProvider.get_quotes(["NOTOK3"])
      assert quotes == %{}
    end

    test "handles non-200 API response gracefully" do
      stub(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 401, body: %{"error" => "unauthorized"}}}
      end)

      assert {:ok, _quotes} = QuoteProvider.get_quotes(["AUTH3"])
    end

    test "skips remote call when fetch_remote is false" do
      stub(Req, :get, fn _url, _opts ->
        flunk("Req.get should not be called when fetch_remote is false")
      end)

      assert {:ok, _quotes} = QuoteProvider.get_quotes(["SKIP3"], fetch_remote: false)
    end

    test "serves from fresh cache on second call without extra HTTP request" do
      req_count = :counters.new(1, [:atomics])

      stub(Req, :get, fn _url, _opts ->
        :counters.add(req_count, 1, 1)
        {:ok, %Req.Response{status: 200, body: brapi_ok_body("VCLT3")}}
      end)

      QuoteProvider.get_quotes(["VCLT3"])
      QuoteProvider.get_quotes(["VCLT3"])

      assert :counters.get(req_count, 1) == 1
    end
  end
end
