defmodule ExBlofin.MarketData do
  @moduledoc """
  BloFin API - Public market data endpoints.

  All endpoints in this module are public and do not require authentication.

  ## Examples

      client = ExBlofin.Client.new(nil, nil, nil)

      {:ok, instruments} = ExBlofin.MarketData.get_instruments(client)
      {:ok, tickers} = ExBlofin.MarketData.get_tickers(client, instId: "BTC-USDT")
      {:ok, candles} = ExBlofin.MarketData.get_candles(client, "BTC-USDT", bar: "1H")
  """

  alias ExBlofin.Client

  import ExBlofin.Helpers, only: [build_query: 2]

  @type client :: Req.Request.t()
  @type response :: {:ok, term()} | {:error, term()}

  @valid_candle_bars ~w(1m 3m 5m 15m 30m 1H 2H 4H 6H 8H 12H 1D 3D 1W 1M)

  # ===========================================================================
  # Instruments
  # ===========================================================================

  @doc """
  Lists available trading instruments.

  ## Options

    - `:instType` - Instrument type (e.g., "SWAP")
    - `:instId` - Specific instrument ID (e.g., "BTC-USDT")

  ## Examples

      {:ok, instruments} = MarketData.get_instruments(client)
      {:ok, instruments} = MarketData.get_instruments(client, instType: "SWAP")
  """
  @spec get_instruments(client(), keyword()) :: response()
  def get_instruments(client, opts \\ []) do
    params = build_query(opts, [:instType, :instId])

    client
    |> Req.get(url: "/api/v1/market/instruments", params: params)
    |> Client.handle_response()
  end

  # ===========================================================================
  # Tickers
  # ===========================================================================

  @doc """
  Retrieves latest price snapshots, bid/ask, and 24h volume.

  ## Options

    - `:instId` - Specific instrument ID (e.g., "BTC-USDT")

  ## Examples

      {:ok, tickers} = MarketData.get_tickers(client)
      {:ok, tickers} = MarketData.get_tickers(client, instId: "BTC-USDT")
  """
  @spec get_tickers(client(), keyword()) :: response()
  def get_tickers(client, opts \\ []) do
    params = build_query(opts, [:instId])

    client
    |> Req.get(url: "/api/v1/market/tickers", params: params)
    |> Client.handle_response()
  end

  # ===========================================================================
  # Order Book
  # ===========================================================================

  @doc """
  Retrieves order book depth for an instrument.

  ## Options

    - `:size` - Number of levels (default: 20, max: 200)

  ## Examples

      {:ok, books} = MarketData.get_books(client, "BTC-USDT")
      {:ok, books} = MarketData.get_books(client, "BTC-USDT", size: "5")
  """
  @spec get_books(client(), String.t(), keyword()) :: response()
  def get_books(client, inst_id, opts \\ []) do
    params =
      [instId: inst_id]
      |> Keyword.merge(build_query(opts, [:size]))

    client
    |> Req.get(url: "/api/v1/market/books", params: params)
    |> Client.handle_response()
  end

  # ===========================================================================
  # Recent Trades
  # ===========================================================================

  @doc """
  Retrieves recent transactions for an instrument.

  ## Options

    - `:limit` - Maximum number of results (default: 100, max: 500)

  ## Examples

      {:ok, trades} = MarketData.get_trades(client, "BTC-USDT")
      {:ok, trades} = MarketData.get_trades(client, "BTC-USDT", limit: "50")
  """
  @spec get_trades(client(), String.t(), keyword()) :: response()
  def get_trades(client, inst_id, opts \\ []) do
    params =
      [instId: inst_id]
      |> Keyword.merge(build_query(opts, [:limit]))

    client
    |> Req.get(url: "/api/v1/market/trades", params: params)
    |> Client.handle_response()
  end

  # ===========================================================================
  # Mark Price
  # ===========================================================================

  @doc """
  Retrieves index and mark prices.

  ## Options

    - `:instId` - Specific instrument ID

  ## Examples

      {:ok, prices} = MarketData.get_mark_price(client)
      {:ok, prices} = MarketData.get_mark_price(client, instId: "BTC-USDT")
  """
  @spec get_mark_price(client(), keyword()) :: response()
  def get_mark_price(client, opts \\ []) do
    params = build_query(opts, [:instId])

    client
    |> Req.get(url: "/api/v1/market/mark-price", params: params)
    |> Client.handle_response()
  end

  # ===========================================================================
  # Funding Rate
  # ===========================================================================

  @doc """
  Retrieves current funding rates.

  ## Options

    - `:instId` - Specific instrument ID

  ## Examples

      {:ok, rates} = MarketData.get_funding_rate(client)
      {:ok, rates} = MarketData.get_funding_rate(client, instId: "BTC-USDT")
  """
  @spec get_funding_rate(client(), keyword()) :: response()
  def get_funding_rate(client, opts \\ []) do
    params = build_query(opts, [:instId])

    client
    |> Req.get(url: "/api/v1/market/funding-rate", params: params)
    |> Client.handle_response()
  end

  @doc """
  Retrieves historical funding rates for an instrument.

  ## Options

    - `:before` - Pagination cursor (return records before this timestamp)
    - `:after` - Pagination cursor (return records after this timestamp)
    - `:limit` - Maximum number of results (default: 100, max: 100)

  ## Examples

      {:ok, history} = MarketData.get_funding_rate_history(client, "BTC-USDT")
  """
  @spec get_funding_rate_history(client(), String.t(), keyword()) :: response()
  def get_funding_rate_history(client, inst_id, opts \\ []) do
    params =
      [instId: inst_id]
      |> Keyword.merge(build_query(opts, [:before, :after, :limit]))

    client
    |> Req.get(url: "/api/v1/market/funding-rate-history", params: params)
    |> Client.handle_response()
  end

  # ===========================================================================
  # Candlesticks
  # ===========================================================================

  @doc """
  Retrieves candlestick data for an instrument.

  ## Options

    - `:bar` - Bar size (default: "1H"). Valid: #{Enum.join(@valid_candle_bars, ", ")}
    - `:before` - Pagination cursor
    - `:after` - Pagination cursor
    - `:limit` - Maximum results (default: 100, max: 300)

  ## Examples

      {:ok, candles} = MarketData.get_candles(client, "BTC-USDT")
      {:ok, candles} = MarketData.get_candles(client, "BTC-USDT", bar: "1D", limit: "50")
  """
  @spec get_candles(client(), String.t(), keyword()) :: response()
  def get_candles(client, inst_id, opts \\ []) do
    params =
      [instId: inst_id]
      |> Keyword.merge(build_query(opts, [:bar, :before, :after, :limit]))

    client
    |> Req.get(url: "/api/v1/market/candles", params: params)
    |> Client.handle_response()
  end

  @doc """
  Retrieves index candlestick data for an instrument.

  Same options as `get_candles/3`.
  """
  @spec get_index_candles(client(), String.t(), keyword()) :: response()
  def get_index_candles(client, inst_id, opts \\ []) do
    params =
      [instId: inst_id]
      |> Keyword.merge(build_query(opts, [:bar, :before, :after, :limit]))

    client
    |> Req.get(url: "/api/v1/market/index-candles", params: params)
    |> Client.handle_response()
  end

  @doc """
  Retrieves mark price candlestick data for an instrument.

  Same options as `get_candles/3`.
  """
  @spec get_mark_price_candles(client(), String.t(), keyword()) :: response()
  def get_mark_price_candles(client, inst_id, opts \\ []) do
    params =
      [instId: inst_id]
      |> Keyword.merge(build_query(opts, [:bar, :before, :after, :limit]))

    client
    |> Req.get(url: "/api/v1/market/mark-price-candles", params: params)
    |> Client.handle_response()
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  @doc """
  Returns the list of valid candle bar sizes.
  """
  @spec valid_candle_bars() :: list(String.t())
  def valid_candle_bars, do: @valid_candle_bars

end
