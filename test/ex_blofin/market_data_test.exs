defmodule ExBlofin.MarketDataTest do
  use ExUnit.Case, async: true

  alias ExBlofin.{Fixtures, MarketData}

  @stub_name :market_data_stub

  describe "get_instruments/2" do
    test "returns instruments on success" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/api/v1/market/instruments"
        assert conn.method == "GET"
        Req.Test.json(conn, Fixtures.sample_instruments_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, instruments} = MarketData.get_instruments(client)
      assert [%{"instId" => "BTC-USDT"} | _] = instruments
    end

    test "passes instType as query param" do
      Req.Test.expect(@stub_name, fn conn ->
        query = URI.decode_query(conn.query_string)
        assert query["instType"] == "SWAP"
        Req.Test.json(conn, Fixtures.sample_instruments_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, _} = MarketData.get_instruments(client, instType: "SWAP")
    end
  end

  describe "get_tickers/2" do
    test "returns tickers on success" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/api/v1/market/tickers"
        Req.Test.json(conn, Fixtures.sample_tickers_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, tickers} = MarketData.get_tickers(client)
      assert [%{"instId" => "BTC-USDT", "last" => "50000.0"} | _] = tickers
    end

    test "filters by instId" do
      Req.Test.expect(@stub_name, fn conn ->
        query = URI.decode_query(conn.query_string)
        assert query["instId"] == "BTC-USDT"
        Req.Test.json(conn, Fixtures.sample_tickers_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, _} = MarketData.get_tickers(client, instId: "BTC-USDT")
    end
  end

  describe "get_books/3" do
    test "returns order book" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/api/v1/market/books"
        query = URI.decode_query(conn.query_string)
        assert query["instId"] == "BTC-USDT"
        Req.Test.json(conn, Fixtures.sample_books_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, [book]} = MarketData.get_books(client, "BTC-USDT")
      assert is_list(book["asks"])
      assert is_list(book["bids"])
    end

    test "passes size parameter" do
      Req.Test.expect(@stub_name, fn conn ->
        query = URI.decode_query(conn.query_string)
        assert query["size"] == "5"
        Req.Test.json(conn, Fixtures.sample_books_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, _} = MarketData.get_books(client, "BTC-USDT", size: "5")
    end
  end

  describe "get_trades/3" do
    test "returns recent trades" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/api/v1/market/trades"
        query = URI.decode_query(conn.query_string)
        assert query["instId"] == "BTC-USDT"
        Req.Test.json(conn, Fixtures.sample_trades_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, trades} = MarketData.get_trades(client, "BTC-USDT")
      assert [%{"tradeId" => "12345"} | _] = trades
    end
  end

  describe "get_mark_price/2" do
    test "returns mark prices" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/api/v1/market/mark-price"
        Req.Test.json(conn, Fixtures.sample_mark_price_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, prices} = MarketData.get_mark_price(client)
      assert [%{"instId" => "BTC-USDT", "markPrice" => _} | _] = prices
    end
  end

  describe "get_funding_rate/2" do
    test "returns funding rates" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/api/v1/market/funding-rate"
        Req.Test.json(conn, Fixtures.sample_funding_rate_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, rates} = MarketData.get_funding_rate(client)
      assert [%{"instId" => "BTC-USDT", "fundingRate" => _} | _] = rates
    end
  end

  describe "get_funding_rate_history/3" do
    test "returns historical funding rates" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/api/v1/market/funding-rate-history"
        query = URI.decode_query(conn.query_string)
        assert query["instId"] == "BTC-USDT"
        Req.Test.json(conn, Fixtures.sample_funding_rate_history_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, history} = MarketData.get_funding_rate_history(client, "BTC-USDT")
      assert [%{"fundingRate" => _} | _] = history
    end
  end

  describe "get_candles/3" do
    test "returns candlestick data" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/api/v1/market/candles"
        query = URI.decode_query(conn.query_string)
        assert query["instId"] == "BTC-USDT"
        Req.Test.json(conn, Fixtures.sample_candles_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, candles} = MarketData.get_candles(client, "BTC-USDT")
      assert is_list(candles)
    end

    test "passes bar and limit params" do
      Req.Test.expect(@stub_name, fn conn ->
        query = URI.decode_query(conn.query_string)
        assert query["bar"] == "1D"
        assert query["limit"] == "50"
        Req.Test.json(conn, Fixtures.sample_candles_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, _} = MarketData.get_candles(client, "BTC-USDT", bar: "1D", limit: "50")
    end
  end

  describe "get_index_candles/3" do
    test "returns index candlestick data" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/api/v1/market/index-candles"
        Req.Test.json(conn, Fixtures.sample_candles_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, candles} = MarketData.get_index_candles(client, "BTC-USDT")
      assert is_list(candles)
    end
  end

  describe "get_mark_price_candles/3" do
    test "returns mark price candlestick data" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/api/v1/market/mark-price-candles"
        Req.Test.json(conn, Fixtures.sample_candles_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, candles} = MarketData.get_mark_price_candles(client, "BTC-USDT")
      assert is_list(candles)
    end
  end

  describe "valid_candle_bars/0" do
    test "returns list of valid bar sizes" do
      bars = MarketData.valid_candle_bars()
      assert is_list(bars)
      assert "1m" in bars
      assert "1H" in bars
      assert "1D" in bars
    end
  end

  describe "error handling" do
    test "returns api_error for BloFin error code" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.error_response("60012", "Invalid request"))
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:error, {:api_error, "60012", "Invalid request"}} =
               MarketData.get_instruments(client)
    end

    test "returns :rate_limited for 429" do
      Req.Test.expect(@stub_name, fn conn ->
        conn
        |> Plug.Conn.put_status(429)
        |> Req.Test.json(%{"msg" => "Rate limit exceeded"})
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:error, :rate_limited} = MarketData.get_instruments(client)
    end
  end
end
