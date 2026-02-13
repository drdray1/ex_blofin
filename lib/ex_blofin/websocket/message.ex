defmodule ExBlofin.WebSocket.Message do
  @moduledoc """
  WebSocket message builder and parser for the BloFin API.

  Handles construction of subscribe/unsubscribe/login/ping messages
  and parsing of incoming WebSocket events into typed structs.

  ## BloFin WebSocket Protocol

  - Subscribe/Unsubscribe: `{"op": "subscribe", "args": [{"channel": "...", ...}]}`
  - Login: `{"op": "login", "args": [{"apiKey": "...", "passphrase": "...", ...}]}`
  - Ping/Pong: Application-level text frames (`"ping"` / `"pong"`)
  - Data events: `{"arg": {"channel": "...", ...}, "data": [...]}`
  - Control events: `{"event": "login", "code": "0", "msg": ""}`

  ## Channels

  ### Public
  - `trades` - Trade executions
  - `tickers` - Ticker updates
  - `books` - Full order book
  - `books5` - Top-5 order book
  - `funding-rate` - Funding rate updates
  - `candle*` - Candlestick data (e.g., `candle1m`, `candle5m`)

  ### Private (requires login)
  - `orders` - Order updates
  - `orders-algo` - Algo order updates
  - `positions` - Position updates
  - `account` - Account updates

  ### Copy Trading (requires login)
  - `copytrading-positions-by-contract` - Copy trading positions by contract
  - `copytrading-positions-by-order` - Copy trading positions by order
  - `copytrading-orders` - Copy trading order updates
  - `copytrading-account` - Copy trading account updates
  """

  alias ExBlofin.Auth

  # ============================================================================
  # Event Structs
  # ============================================================================

  defmodule TradeEvent do
    @moduledoc "Represents a trade event from the public WebSocket."
    defstruct [:inst_id, :trade_id, :price, :size, :side, :ts]

    @type t :: %__MODULE__{
            inst_id: String.t(),
            trade_id: String.t(),
            price: String.t(),
            size: String.t(),
            side: String.t(),
            ts: String.t()
          }
  end

  defmodule TickerEvent do
    @moduledoc "Represents a ticker event from the public WebSocket."
    defstruct [
      :inst_id,
      :last,
      :ask_price,
      :ask_size,
      :bid_price,
      :bid_size,
      :open_24h,
      :high_24h,
      :low_24h,
      :vol_24h,
      :vol_currency_24h,
      :ts
    ]

    @type t :: %__MODULE__{
            inst_id: String.t(),
            last: String.t(),
            ask_price: String.t(),
            ask_size: String.t() | nil,
            bid_price: String.t(),
            bid_size: String.t() | nil,
            open_24h: String.t() | nil,
            high_24h: String.t() | nil,
            low_24h: String.t() | nil,
            vol_24h: String.t() | nil,
            vol_currency_24h: String.t() | nil,
            ts: String.t()
          }
  end

  defmodule BookEvent do
    @moduledoc "Represents an order book event from the public WebSocket."
    defstruct [:inst_id, :asks, :bids, :ts, :checksum, :action]

    @type t :: %__MODULE__{
            inst_id: String.t(),
            asks: [[String.t()]],
            bids: [[String.t()]],
            ts: String.t(),
            checksum: integer() | nil,
            action: String.t() | nil
          }
  end

  defmodule CandleEvent do
    @moduledoc "Represents a candlestick event from the public WebSocket."
    defstruct [:inst_id, :ts, :open, :high, :low, :close, :vol, :vol_currency, :confirm]

    @type t :: %__MODULE__{
            inst_id: String.t(),
            ts: String.t(),
            open: String.t(),
            high: String.t(),
            low: String.t(),
            close: String.t(),
            vol: String.t(),
            vol_currency: String.t() | nil,
            confirm: String.t() | nil
          }
  end

  defmodule FundingRateEvent do
    @moduledoc "Represents a funding rate event from the public WebSocket."
    defstruct [:inst_id, :funding_rate, :next_funding_rate, :funding_time, :next_funding_time]

    @type t :: %__MODULE__{
            inst_id: String.t(),
            funding_rate: String.t(),
            next_funding_rate: String.t() | nil,
            funding_time: String.t(),
            next_funding_time: String.t() | nil
          }
  end

  defmodule OrderEvent do
    @moduledoc "Represents an order update event from the private WebSocket."
    defstruct [
      :order_id,
      :inst_id,
      :margin_mode,
      :position_side,
      :side,
      :order_type,
      :price,
      :size,
      :state,
      :fill_price,
      :fill_size,
      :fee,
      :pnl,
      :leverage,
      :create_time,
      :update_time
    ]

    @type t :: %__MODULE__{
            order_id: String.t(),
            inst_id: String.t(),
            margin_mode: String.t() | nil,
            position_side: String.t() | nil,
            side: String.t(),
            order_type: String.t(),
            price: String.t(),
            size: String.t(),
            state: String.t(),
            fill_price: String.t() | nil,
            fill_size: String.t() | nil,
            fee: String.t() | nil,
            pnl: String.t() | nil,
            leverage: String.t() | nil,
            create_time: String.t() | nil,
            update_time: String.t() | nil
          }
  end

  defmodule AlgoOrderEvent do
    @moduledoc "Represents an algo order update event from the private WebSocket."
    defstruct [
      :algo_id,
      :inst_id,
      :margin_mode,
      :position_side,
      :side,
      :order_type,
      :size,
      :state,
      :trigger_price,
      :trigger_type,
      :create_time,
      :update_time
    ]

    @type t :: %__MODULE__{
            algo_id: String.t(),
            inst_id: String.t(),
            margin_mode: String.t() | nil,
            position_side: String.t() | nil,
            side: String.t() | nil,
            order_type: String.t() | nil,
            size: String.t() | nil,
            state: String.t(),
            trigger_price: String.t() | nil,
            trigger_type: String.t() | nil,
            create_time: String.t() | nil,
            update_time: String.t() | nil
          }
  end

  defmodule PositionEvent do
    @moduledoc "Represents a position update event from the private WebSocket."
    defstruct [
      :position_id,
      :inst_id,
      :position_side,
      :positions,
      :available_positions,
      :average_price,
      :mark_price,
      :unrealized_pnl,
      :unrealized_pnl_ratio,
      :leverage,
      :margin_mode,
      :liquidation_price,
      :create_time,
      :update_time
    ]

    @type t :: %__MODULE__{
            position_id: String.t(),
            inst_id: String.t(),
            position_side: String.t(),
            positions: String.t(),
            available_positions: String.t() | nil,
            average_price: String.t(),
            mark_price: String.t() | nil,
            unrealized_pnl: String.t() | nil,
            unrealized_pnl_ratio: String.t() | nil,
            leverage: String.t() | nil,
            margin_mode: String.t() | nil,
            liquidation_price: String.t() | nil,
            create_time: String.t() | nil,
            update_time: String.t() | nil
          }
  end

  defmodule AccountEvent do
    @moduledoc "Represents an account update event from the private WebSocket."
    defstruct [:total_equity, :isolated_equity, :details, :ts]

    @type t :: %__MODULE__{
            total_equity: String.t(),
            isolated_equity: String.t() | nil,
            details: [map()],
            ts: String.t()
          }
  end

  defmodule CopyPositionEvent do
    @moduledoc "Represents a copy trading position event."
    defstruct [
      :inst_id,
      :position_side,
      :positions,
      :average_price,
      :unrealized_pnl,
      :leverage,
      :margin_mode,
      :update_time
    ]

    @type t :: %__MODULE__{
            inst_id: String.t(),
            position_side: String.t(),
            positions: String.t(),
            average_price: String.t(),
            unrealized_pnl: String.t() | nil,
            leverage: String.t() | nil,
            margin_mode: String.t() | nil,
            update_time: String.t() | nil
          }
  end

  defmodule CopyOrderEvent do
    @moduledoc "Represents a copy trading order event."
    defstruct [
      :order_id,
      :inst_id,
      :side,
      :order_type,
      :price,
      :size,
      :state,
      :fill_price,
      :fill_size,
      :create_time,
      :update_time
    ]

    @type t :: %__MODULE__{
            order_id: String.t(),
            inst_id: String.t(),
            side: String.t(),
            order_type: String.t() | nil,
            price: String.t() | nil,
            size: String.t(),
            state: String.t(),
            fill_price: String.t() | nil,
            fill_size: String.t() | nil,
            create_time: String.t() | nil,
            update_time: String.t() | nil
          }
  end

  defmodule CopyAccountEvent do
    @moduledoc "Represents a copy trading account event."
    defstruct [:total_equity, :details, :ts]

    @type t :: %__MODULE__{
            total_equity: String.t(),
            details: [map()],
            ts: String.t()
          }
  end

  # ============================================================================
  # Message Building
  # ============================================================================

  @doc """
  Builds a login message for WebSocket authentication.

  ## Parameters

    - `api_key` - BloFin API key
    - `secret_key` - BloFin secret key
    - `passphrase` - BloFin API passphrase
  """
  @spec build_login(String.t(), String.t(), String.t()) :: map()
  def build_login(api_key, secret_key, passphrase) do
    timestamp = Auth.generate_timestamp()
    nonce = Auth.generate_nonce()
    sign = Auth.compute_ws_signature(secret_key, timestamp, nonce)

    %{
      "op" => "login",
      "args" => [
        %{
          "apiKey" => api_key,
          "passphrase" => passphrase,
          "timestamp" => timestamp,
          "nonce" => nonce,
          "sign" => sign
        }
      ]
    }
  end

  @doc """
  Builds a subscribe message for one or more channels.

  ## Parameters

    - `channels` - List of channel arg maps, e.g. `[%{"channel" => "trades", "instId" => "BTC-USDT"}]`

  ## Examples

      build_subscribe([%{"channel" => "trades", "instId" => "BTC-USDT"}])
      #=> %{"op" => "subscribe", "args" => [%{"channel" => "trades", "instId" => "BTC-USDT"}]}
  """
  @spec build_subscribe([map()]) :: map()
  def build_subscribe(channels) when is_list(channels) do
    %{"op" => "subscribe", "args" => channels}
  end

  @doc """
  Builds an unsubscribe message for one or more channels.

  ## Parameters

    - `channels` - List of channel arg maps

  ## Examples

      build_unsubscribe([%{"channel" => "trades", "instId" => "BTC-USDT"}])
      #=> %{"op" => "unsubscribe", "args" => [%{"channel" => "trades", "instId" => "BTC-USDT"}]}
  """
  @spec build_unsubscribe([map()]) :: map()
  def build_unsubscribe(channels) when is_list(channels) do
    %{"op" => "unsubscribe", "args" => channels}
  end

  @doc """
  Returns the ping text frame content.

  BloFin uses application-level text-frame ping/pong, not WebSocket protocol pings.
  """
  @spec build_ping() :: String.t()
  def build_ping, do: "ping"

  @doc """
  Encodes a message map to JSON for sending over WebSocket.
  """
  @spec encode(map()) :: {:ok, String.t()} | {:error, term()}
  def encode(message) when is_map(message) do
    Jason.encode(message)
  end

  # ============================================================================
  # Event Parsing
  # ============================================================================

  @doc """
  Parses a raw WebSocket text frame into a typed event.

  ## Returns

    - `{:ok, channel_atom, [event_struct]}` - Data event with parsed structs
    - `{:ok, :login, result_map}` - Login response
    - `{:ok, :subscribe, arg_map}` - Subscribe confirmation
    - `{:ok, :unsubscribe, arg_map}` - Unsubscribe confirmation
    - `{:ok, :error, error_map}` - Error event
    - `{:ok, :pong, nil}` - Pong response
    - `{:error, reason}` - Parse failure
  """
  @spec parse(String.t()) ::
          {:ok, atom(), term()} | {:error, term()}
  def parse("pong"), do: {:ok, :pong, nil}

  def parse(raw) when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, data} -> parse_decoded(data)
      {:error, _} -> {:error, :invalid_json}
    end
  end

  @doc """
  Parses a decoded JSON map into a typed event.
  """
  @spec parse_decoded(map()) :: {:ok, atom(), term()} | {:error, term()}
  def parse_decoded(%{"event" => "login"} = data) do
    {:ok, :login, %{code: data["code"], msg: data["msg"]}}
  end

  def parse_decoded(%{"event" => "subscribe", "arg" => arg}) do
    {:ok, :subscribe, arg}
  end

  def parse_decoded(%{"event" => "unsubscribe", "arg" => arg}) do
    {:ok, :unsubscribe, arg}
  end

  def parse_decoded(%{"event" => "error"} = data) do
    {:ok, :error, %{code: data["code"], msg: data["msg"]}}
  end

  def parse_decoded(%{"arg" => %{"channel" => channel} = arg, "data" => data})
      when is_list(data) do
    inst_id = arg["instId"]
    parse_channel_data(channel, inst_id, data, arg)
  end

  def parse_decoded(_), do: {:error, :unknown_message_format}

  # ============================================================================
  # Channel Data Parsing
  # ============================================================================

  defp parse_channel_data("trades", _inst_id, data, _arg) do
    events = Enum.map(data, &parse_trade/1)
    {:ok, :trades, events}
  end

  defp parse_channel_data("tickers", _inst_id, data, _arg) do
    events = Enum.map(data, &parse_ticker/1)
    {:ok, :tickers, events}
  end

  defp parse_channel_data(book, _inst_id, data, arg) when book in ["books", "books5"] do
    events = Enum.map(data, &parse_book(&1, arg))
    channel = String.to_existing_atom(book)
    {:ok, channel, events}
  end

  defp parse_channel_data("funding-rate", _inst_id, data, _arg) do
    events = Enum.map(data, &parse_funding_rate/1)
    {:ok, :funding_rate, events}
  end

  defp parse_channel_data("candle" <> _period = channel, inst_id, data, _arg) do
    events = Enum.map(data, &parse_candle(&1, inst_id))
    {:ok, String.to_atom(channel), events}
  end

  defp parse_channel_data("orders", _inst_id, data, _arg) do
    events = Enum.map(data, &parse_order/1)
    {:ok, :orders, events}
  end

  defp parse_channel_data("orders-algo", _inst_id, data, _arg) do
    events = Enum.map(data, &parse_algo_order/1)
    {:ok, :orders_algo, events}
  end

  defp parse_channel_data("positions", _inst_id, data, _arg) do
    events = Enum.map(data, &parse_position/1)
    {:ok, :positions, events}
  end

  defp parse_channel_data("account", _inst_id, data, _arg) do
    events = Enum.map(data, &parse_account/1)
    {:ok, :account, events}
  end

  defp parse_channel_data("copytrading-positions-by-contract", _inst_id, data, _arg) do
    events = Enum.map(data, &parse_copy_position/1)
    {:ok, :copytrading_positions_by_contract, events}
  end

  defp parse_channel_data("copytrading-positions-by-order", _inst_id, data, _arg) do
    events = Enum.map(data, &parse_copy_position/1)
    {:ok, :copytrading_positions_by_order, events}
  end

  defp parse_channel_data("copytrading-orders", _inst_id, data, _arg) do
    events = Enum.map(data, &parse_copy_order/1)
    {:ok, :copytrading_orders, events}
  end

  defp parse_channel_data("copytrading-account", _inst_id, data, _arg) do
    events = Enum.map(data, &parse_copy_account/1)
    {:ok, :copytrading_account, events}
  end

  defp parse_channel_data(channel, _inst_id, data, _arg) do
    {:ok, String.to_atom(channel), data}
  end

  # ============================================================================
  # Individual Event Parsers
  # ============================================================================

  defp parse_trade(d) do
    %TradeEvent{
      inst_id: d["instId"],
      trade_id: d["tradeId"],
      price: d["price"],
      size: d["size"],
      side: d["side"],
      ts: d["ts"]
    }
  end

  defp parse_ticker(d) do
    %TickerEvent{
      inst_id: d["instId"],
      last: d["last"],
      ask_price: d["askPrice"],
      ask_size: d["askSize"],
      bid_price: d["bidPrice"],
      bid_size: d["bidSize"],
      open_24h: d["open24h"],
      high_24h: d["high24h"],
      low_24h: d["low24h"],
      vol_24h: d["vol24h"],
      vol_currency_24h: d["volCurrency24h"],
      ts: d["ts"]
    }
  end

  defp parse_book(d, arg) do
    %BookEvent{
      inst_id: arg["instId"],
      asks: d["asks"] || [],
      bids: d["bids"] || [],
      ts: d["ts"],
      checksum: d["checksum"],
      action: d["action"]
    }
  end

  defp parse_candle(d, inst_id) when is_list(d) do
    %CandleEvent{
      inst_id: inst_id,
      ts: Enum.at(d, 0),
      open: Enum.at(d, 1),
      high: Enum.at(d, 2),
      low: Enum.at(d, 3),
      close: Enum.at(d, 4),
      vol: Enum.at(d, 5),
      vol_currency: Enum.at(d, 6),
      confirm: Enum.at(d, 7)
    }
  end

  defp parse_candle(d, inst_id) when is_map(d) do
    %CandleEvent{
      inst_id: inst_id,
      ts: d["ts"],
      open: d["open"],
      high: d["high"],
      low: d["low"],
      close: d["close"],
      vol: d["vol"],
      vol_currency: d["volCurrency"],
      confirm: d["confirm"]
    }
  end

  defp parse_funding_rate(d) do
    %FundingRateEvent{
      inst_id: d["instId"],
      funding_rate: d["fundingRate"],
      next_funding_rate: d["nextFundingRate"],
      funding_time: d["fundingTime"],
      next_funding_time: d["nextFundingTime"]
    }
  end

  defp parse_order(d) do
    %OrderEvent{
      order_id: d["orderId"],
      inst_id: d["instId"],
      margin_mode: d["marginMode"],
      position_side: d["positionSide"],
      side: d["side"],
      order_type: d["orderType"],
      price: d["price"],
      size: d["size"],
      state: d["state"],
      fill_price: d["fillPrice"],
      fill_size: d["fillSize"],
      fee: d["fee"],
      pnl: d["pnl"],
      leverage: d["leverage"],
      create_time: d["createTime"],
      update_time: d["updateTime"]
    }
  end

  defp parse_algo_order(d) do
    %AlgoOrderEvent{
      algo_id: d["algoId"],
      inst_id: d["instId"],
      margin_mode: d["marginMode"],
      position_side: d["positionSide"],
      side: d["side"],
      order_type: d["orderType"],
      size: d["size"],
      state: d["state"],
      trigger_price: d["triggerPrice"],
      trigger_type: d["triggerType"],
      create_time: d["createTime"],
      update_time: d["updateTime"]
    }
  end

  defp parse_position(d) do
    %PositionEvent{
      position_id: d["positionId"],
      inst_id: d["instId"],
      position_side: d["positionSide"],
      positions: d["positions"],
      available_positions: d["availablePositions"],
      average_price: d["averagePrice"],
      mark_price: d["markPrice"],
      unrealized_pnl: d["unrealizedPnl"],
      unrealized_pnl_ratio: d["unrealizedPnlRatio"],
      leverage: d["leverage"],
      margin_mode: d["marginMode"],
      liquidation_price: d["liquidationPrice"],
      create_time: d["createTime"],
      update_time: d["updateTime"]
    }
  end

  defp parse_account(d) do
    %AccountEvent{
      total_equity: d["totalEquity"],
      isolated_equity: d["isolatedEquity"],
      details: d["details"] || [],
      ts: d["ts"]
    }
  end

  defp parse_copy_position(d) do
    %CopyPositionEvent{
      inst_id: d["instId"],
      position_side: d["positionSide"],
      positions: d["positions"],
      average_price: d["averagePrice"],
      unrealized_pnl: d["unrealizedPnl"],
      leverage: d["leverage"],
      margin_mode: d["marginMode"],
      update_time: d["updateTime"]
    }
  end

  defp parse_copy_order(d) do
    %CopyOrderEvent{
      order_id: d["orderId"],
      inst_id: d["instId"],
      side: d["side"],
      order_type: d["orderType"],
      price: d["price"],
      size: d["size"],
      state: d["state"],
      fill_price: d["fillPrice"],
      fill_size: d["fillSize"],
      create_time: d["createTime"],
      update_time: d["updateTime"]
    }
  end

  defp parse_copy_account(d) do
    %CopyAccountEvent{
      total_equity: d["totalEquity"],
      details: d["details"] || [],
      ts: d["ts"]
    }
  end
end
