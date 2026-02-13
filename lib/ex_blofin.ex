defmodule ExBlofin do
  @moduledoc """
  Elixir client for the BloFin API.

  Provides a unified interface for perpetual futures trading, copy trading,
  account management, market data, and real-time WebSocket streaming.

  ## Quick Start

      # Create an authenticated client
      client = ExBlofin.new("api_key", "secret_key", "passphrase")

      # Public market data (no auth needed)
      client = ExBlofin.new(nil, nil, nil)
      {:ok, instruments} = ExBlofin.get_instruments(client)
      {:ok, tickers} = ExBlofin.get_tickers(client, instId: "BTC-USDT")

      # Account info
      client = ExBlofin.new("api_key", "secret_key", "passphrase")
      {:ok, balance} = ExBlofin.get_balance(client)
      {:ok, positions} = ExBlofin.get_positions(client)

      # Trading
      {:ok, result} = ExBlofin.market_order(client, "BTC-USDT", "buy", "net", "10")
      {:ok, result} = ExBlofin.limit_order(client, "BTC-USDT", "buy", "net", "10", "50000.0")

  ## Demo Trading

      client = ExBlofin.new("api_key", "secret_key", "passphrase", demo: true)

  ## Configuration

      # config/config.exs (all optional, sensible defaults provided)
      config :ex_blofin,
        config: [
          base_url: "https://openapi.blofin.com",
          demo_url: "https://demo-trading-openapi.blofin.com",
          ws_public_url: "wss://openapi.blofin.com/ws/public",
          ws_private_url: "wss://openapi.blofin.com/ws/private",
          ws_copy_trading_url: "wss://openapi.blofin.com/ws/copytrading/private"
        ]

  ## WebSocket Streaming

      # Public market data
      {:ok, pid} = ExBlofin.WebSocket.PublicConnection.start_link()
      ExBlofin.WebSocket.PublicConnection.add_subscriber(pid, self())
      ExBlofin.WebSocket.PublicConnection.subscribe(pid, [
        %{"channel" => "trades", "instId" => "BTC-USDT"}
      ])
      # Receive: {:blofin_event, :trades, [%ExBlofin.WebSocket.Message.TradeEvent{...}]}

      # Private account/order updates
      {:ok, pid} = ExBlofin.WebSocket.PrivateConnection.start_link(
        api_key: "key", secret_key: "secret", passphrase: "pass"
      )
      ExBlofin.WebSocket.PrivateConnection.add_subscriber(pid, self())
      ExBlofin.WebSocket.PrivateConnection.subscribe(pid, [%{"channel" => "orders"}])
      # Receive: {:blofin_event, :orders, [%ExBlofin.WebSocket.Message.OrderEvent{...}]}
  """

  alias ExBlofin.{
    Account,
    Affiliate,
    Asset,
    Client,
    CopyTrading,
    MarketData,
    Tax,
    Trading,
    User
  }

  # ============================================================================
  # Client
  # ============================================================================

  @doc "Creates a new BloFin API client. Pass nil for all credentials for public-only usage."
  defdelegate new(api_key, secret_key, passphrase, opts \\ []), to: Client

  @doc "Verifies API credentials by making a test request."
  defdelegate verify_credentials(api_key, secret_key, passphrase, demo \\ false), to: Client

  @doc "Performs a health check on the client connection."
  defdelegate healthcheck(client), to: Client

  # ============================================================================
  # Market Data (Public)
  # ============================================================================

  @doc "Returns available instruments."
  defdelegate get_instruments(client, opts \\ []), to: MarketData

  @doc "Returns ticker data."
  defdelegate get_tickers(client, opts \\ []), to: MarketData

  @doc "Returns order book data."
  defdelegate get_books(client, inst_id, opts \\ []), to: MarketData

  @doc "Returns recent trades."
  defdelegate get_trades(client, inst_id, opts \\ []), to: MarketData

  @doc "Returns mark price."
  defdelegate get_mark_price(client, opts \\ []), to: MarketData

  @doc "Returns current funding rate."
  defdelegate get_funding_rate(client, opts \\ []), to: MarketData

  @doc "Returns funding rate history."
  defdelegate get_funding_rate_history(client, inst_id, opts \\ []), to: MarketData

  @doc "Returns candlestick data."
  defdelegate get_candles(client, inst_id, opts \\ []), to: MarketData

  @doc "Returns index candles."
  defdelegate get_index_candles(client, inst_id, opts \\ []), to: MarketData

  @doc "Returns mark price candles."
  defdelegate get_mark_price_candles(client, inst_id, opts \\ []), to: MarketData

  # ============================================================================
  # Account
  # ============================================================================

  @doc "Returns account balance."
  defdelegate get_balance(client, opts \\ []), to: Account

  @doc "Returns current positions."
  defdelegate get_positions(client, opts \\ []), to: Account

  @doc "Returns margin mode."
  defdelegate get_margin_mode(client, opts \\ []), to: Account

  @doc "Sets margin mode."
  defdelegate set_margin_mode(client, params), to: Account

  @doc "Returns position mode."
  defdelegate get_position_mode(client, opts \\ []), to: Account

  @doc "Sets position mode."
  defdelegate set_position_mode(client, params), to: Account

  @doc "Returns leverage info."
  defdelegate get_batch_leverage_info(client, opts \\ []), to: Account

  @doc "Sets leverage."
  defdelegate set_leverage(client, params), to: Account

  @doc "Returns account config."
  defdelegate get_config(client), to: Account

  # ============================================================================
  # Asset
  # ============================================================================

  @doc "Returns asset balances."
  defdelegate get_balances(client, opts \\ []), to: Asset

  @doc "Transfers between accounts."
  defdelegate transfer(client, params), to: Asset

  @doc "Returns asset bills history."
  defdelegate get_bills(client, opts \\ []), to: Asset

  @doc "Returns withdrawal history."
  defdelegate get_withdrawal_history(client, opts \\ []), to: Asset

  @doc "Returns deposit history."
  defdelegate get_deposit_history(client, opts \\ []), to: Asset

  @doc "Applies demo money."
  defdelegate apply_demo_money(client), to: Asset

  # ============================================================================
  # Trading
  # ============================================================================

  @doc "Places a single order."
  defdelegate place_order(client, params), to: Trading

  @doc "Places multiple orders in batch."
  defdelegate place_batch_orders(client, params), to: Trading

  @doc "Cancels a single order."
  defdelegate cancel_order(client, params), to: Trading

  @doc "Cancels multiple orders in batch."
  defdelegate cancel_batch_orders(client, params), to: Trading

  @doc "Returns pending orders."
  defdelegate get_pending_orders(client, opts \\ []), to: Trading

  @doc "Returns order detail."
  defdelegate get_order_detail(client, opts \\ []), to: Trading

  @doc "Returns order history."
  defdelegate get_order_history(client, opts \\ []), to: Trading

  @doc "Places a take-profit/stop-loss order."
  defdelegate place_tpsl_order(client, params), to: Trading

  @doc "Cancels a TPSL order."
  defdelegate cancel_tpsl_order(client, params), to: Trading

  @doc "Returns TPSL orders."
  defdelegate get_tpsl_orders(client, opts \\ []), to: Trading

  @doc "Returns TPSL order detail."
  defdelegate get_tpsl_order_detail(client, opts \\ []), to: Trading

  @doc "Returns TPSL order history."
  defdelegate get_tpsl_order_history(client, opts \\ []), to: Trading

  @doc "Places an algo order."
  defdelegate place_algo_order(client, params), to: Trading

  @doc "Cancels an algo order."
  defdelegate cancel_algo_order(client, params), to: Trading

  @doc "Returns algo orders."
  defdelegate get_algo_orders(client, opts \\ []), to: Trading

  @doc "Returns algo order history."
  defdelegate get_algo_order_history(client, opts \\ []), to: Trading

  @doc "Returns trade history."
  defdelegate get_trade_history(client, opts \\ []), to: Trading

  @doc "Returns order price range."
  defdelegate get_order_price_range(client, opts \\ []), to: Trading

  @doc "Closes a position."
  defdelegate close_position(client, params), to: Trading

  @doc "Convenience: places a market order."
  defdelegate market_order(client, inst_id, side, position_side, size), to: Trading

  @doc "Convenience: places a limit order."
  defdelegate limit_order(client, inst_id, side, position_side, size, price), to: Trading

  @doc "Validates order parameters."
  defdelegate validate_order_params(params), to: Trading

  # ============================================================================
  # Copy Trading
  # ============================================================================

  @doc "Returns copy trading instruments."
  defdelegate get_copy_trading_instruments(client, opts \\ []),
    to: CopyTrading,
    as: :get_instruments

  @doc "Returns copy trading account config."
  defdelegate get_copy_trading_account_config(client),
    to: CopyTrading,
    as: :get_account_config

  @doc "Returns copy trading balance."
  defdelegate get_copy_trading_balance(client, opts \\ []),
    to: CopyTrading,
    as: :get_balance

  @doc "Places a copy trading order."
  defdelegate place_copy_trading_order(client, params),
    to: CopyTrading,
    as: :place_order

  @doc "Closes a copy trading position."
  defdelegate close_copy_trading_position(client, params),
    to: CopyTrading,
    as: :close_position

  # ============================================================================
  # User
  # ============================================================================

  @doc "Returns API key info."
  defdelegate get_api_key_info(client), to: User

  # ============================================================================
  # Affiliate
  # ============================================================================

  @doc "Returns affiliate info."
  defdelegate get_affiliate_info(client), to: Affiliate, as: :get_info

  @doc "Returns referral code."
  defdelegate get_referral_code(client), to: Affiliate

  # ============================================================================
  # Tax
  # ============================================================================

  @doc "Returns tax deposit history."
  defdelegate get_tax_deposit_history(client, opts \\ []),
    to: Tax,
    as: :get_deposit_history

  @doc "Returns tax withdrawal history."
  defdelegate get_tax_withdraw_history(client, opts \\ []),
    to: Tax,
    as: :get_withdraw_history

  @doc "Returns tax futures trade history."
  defdelegate get_tax_futures_trade_history(client, opts \\ []),
    to: Tax,
    as: :get_futures_trade_history

  @doc "Returns tax spot trade history."
  defdelegate get_tax_spot_trade_history(client, opts \\ []),
    to: Tax,
    as: :get_spot_trade_history
end
