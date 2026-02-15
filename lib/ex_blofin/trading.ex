defmodule ExBlofin.Trading do
  @moduledoc """
  BloFin API - Trading endpoints.

  Provides functions for order placement, cancellation, TP/SL orders,
  algo/trigger orders, and trade history. All endpoints require authentication.

  ## Examples

      client = ExBlofin.Client.new("api_key", "secret_key", "passphrase")

      # Place a market order
      {:ok, result} = ExBlofin.Trading.place_order(client, %{
        "instId" => "BTC-USDT",
        "marginMode" => "cross",
        "positionSide" => "net",
        "side" => "buy",
        "orderType" => "market",
        "size" => "1"
      })

      # Convenience function
      {:ok, result} = ExBlofin.Trading.market_order(client, "BTC-USDT", "buy", "1")
  """

  alias ExBlofin.Client

  import ExBlofin.Helpers, only: [build_query: 2]

  @type client :: Req.Request.t()
  @type response :: {:ok, term()} | {:error, term()}

  @valid_sides ~w(buy sell)
  @valid_order_types ~w(market limit post_only fok ioc)
  @valid_margin_modes ~w(cross isolated)
  @valid_position_sides ~w(net long short)

  # ===========================================================================
  # Order Management
  # ===========================================================================

  @doc """
  Places a single order.

  ## Parameters

    - `"instId"` - Instrument ID (required)
    - `"marginMode"` - "cross" or "isolated" (required)
    - `"positionSide"` - "net", "long", or "short" (required)
    - `"side"` - "buy" or "sell" (required)
    - `"orderType"` - "market", "limit", "post_only", "fok", "ioc" (required)
    - `"size"` - Number of contracts (required)
    - `"price"` - Order price (required for limit orders)
    - `"reduceOnly"` - "true" or "false" (optional)
    - `"clientOrderId"` - User-assigned ID, max 32 chars (optional)
    - `"tpTriggerPrice"` - Take-profit trigger (optional)
    - `"tpOrderPrice"` - TP execution price, "-1" for market (optional)
    - `"slTriggerPrice"` - Stop-loss trigger (optional)
    - `"slOrderPrice"` - SL execution price, "-1" for market (optional)
    - `"brokerId"` - Broker ID, max 16 chars (optional)
  """
  @spec place_order(client(), map()) :: response()
  def place_order(client, params) do
    client
    |> Req.post(url: "/api/v1/trade/order", json: params)
    |> Client.handle_response()
  end

  @doc """
  Places multiple orders (up to 20).
  """
  @spec place_batch_orders(client(), list(map())) :: response()
  def place_batch_orders(client, orders) when is_list(orders) do
    client
    |> Req.post(url: "/api/v1/trade/batch-orders", json: orders)
    |> Client.handle_response()
  end

  @doc """
  Cancels a single order.

  ## Parameters

    - `"instId"` - Instrument ID (required)
    - `"orderId"` - Order ID (required, unless clientOrderId is provided)
    - `"clientOrderId"` - Client order ID (optional)
  """
  @spec cancel_order(client(), map()) :: response()
  def cancel_order(client, params) do
    client
    |> Req.post(url: "/api/v1/trade/cancel-order", json: params)
    |> Client.handle_response()
  end

  @doc """
  Cancels multiple orders.
  """
  @spec cancel_batch_orders(client(), list(map())) :: response()
  def cancel_batch_orders(client, orders) when is_list(orders) do
    client
    |> Req.post(url: "/api/v1/trade/cancel-batch-orders", json: orders)
    |> Client.handle_response()
  end

  @doc """
  Retrieves active/pending orders.

  ## Options

    - `:instId` - Filter by instrument
    - `:orderType` - Filter by order type
    - `:state` - Filter by state
    - `:before` - Pagination cursor
    - `:after` - Pagination cursor
    - `:limit` - Maximum results
  """
  @spec get_pending_orders(client(), keyword()) :: response()
  def get_pending_orders(client, opts \\ []) do
    params = build_query(opts, [:instId, :orderType, :state, :before, :after, :limit])

    client
    |> Req.get(url: "/api/v1/trade/orders-pending", params: params)
    |> Client.handle_response()
  end

  @doc """
  Retrieves details for a specific order.

  ## Options

    - `:orderId` - Order ID
    - `:clientOrderId` - Client order ID
    - `:instId` - Instrument ID
  """
  @spec get_order_detail(client(), keyword()) :: response()
  def get_order_detail(client, opts \\ []) do
    params = build_query(opts, [:orderId, :clientOrderId, :instId])

    client
    |> Req.get(url: "/api/v1/trade/order-detail", params: params)
    |> Client.handle_response()
  end

  @doc """
  Retrieves historical orders.

  ## Options

    - `:instId` - Filter by instrument
    - `:orderType` - Filter by order type
    - `:state` - Filter by state
    - `:before` - Pagination cursor
    - `:after` - Pagination cursor
    - `:limit` - Maximum results
  """
  @spec get_order_history(client(), keyword()) :: response()
  def get_order_history(client, opts \\ []) do
    params = build_query(opts, [:instId, :orderType, :state, :before, :after, :limit])

    client
    |> Req.get(url: "/api/v1/trade/order-history", params: params)
    |> Client.handle_response()
  end

  # ===========================================================================
  # TP/SL Orders
  # ===========================================================================

  @doc """
  Places a take-profit/stop-loss order.

  ## Parameters

    - `"instId"` - Instrument ID (required)
    - `"marginMode"` - "cross" or "isolated" (required)
    - `"positionSide"` - "net", "long", or "short" (required)
    - `"side"` - "buy" or "sell" (required)
    - `"size"` - Quantity, "-1" for entire position (required)
    - `"tpTriggerPrice"` - Take-profit trigger price
    - `"tpOrderPrice"` - TP execution price, "-1" for market
    - `"slTriggerPrice"` - Stop-loss trigger price
    - `"slOrderPrice"` - SL execution price, "-1" for market
  """
  @spec place_tpsl_order(client(), map()) :: response()
  def place_tpsl_order(client, params) do
    client
    |> Req.post(url: "/api/v1/trade/order-tpsl", json: params)
    |> Client.handle_response()
  end

  @doc """
  Cancels a TP/SL order.

  ## Parameters

    - `"instId"` - Instrument ID (required)
    - `"tpslId"` - TP/SL order ID (required)
  """
  @spec cancel_tpsl_order(client(), map()) :: response()
  def cancel_tpsl_order(client, params) do
    client
    |> Req.post(url: "/api/v1/trade/cancel-tpsl", json: params)
    |> Client.handle_response()
  end

  @doc """
  Retrieves active TP/SL orders.

  ## Options

    - `:instId` - Filter by instrument
    - `:tpslId` - Specific TP/SL order ID
    - `:before` - Pagination cursor
    - `:after` - Pagination cursor
    - `:limit` - Maximum results
  """
  @spec get_tpsl_orders(client(), keyword()) :: response()
  def get_tpsl_orders(client, opts \\ []) do
    params = build_query(opts, [:instId, :tpslId, :before, :after, :limit])

    client
    |> Req.get(url: "/api/v1/trade/orders-tpsl", params: params)
    |> Client.handle_response()
  end

  @doc """
  Retrieves details for a specific TP/SL order.

  ## Options

    - `:tpslId` - TP/SL order ID
    - `:instId` - Instrument ID
  """
  @spec get_tpsl_order_detail(client(), keyword()) :: response()
  def get_tpsl_order_detail(client, opts \\ []) do
    params = build_query(opts, [:tpslId, :instId])

    client
    |> Req.get(url: "/api/v1/trade/order-tpsl-detail", params: params)
    |> Client.handle_response()
  end

  @doc """
  Retrieves TP/SL order history.

  ## Options

    - `:instId` - Filter by instrument
    - `:before` - Pagination cursor
    - `:after` - Pagination cursor
    - `:limit` - Maximum results
  """
  @spec get_tpsl_order_history(client(), keyword()) :: response()
  def get_tpsl_order_history(client, opts \\ []) do
    params = build_query(opts, [:instId, :before, :after, :limit])

    client
    |> Req.get(url: "/api/v1/trade/order-tpsl-history", params: params)
    |> Client.handle_response()
  end

  # ===========================================================================
  # Algo/Trigger Orders
  # ===========================================================================

  @doc """
  Places an algorithmic (trigger) order.

  ## Parameters

    - `"instId"` - Instrument ID (required)
    - `"marginMode"` - "cross" or "isolated" (required)
    - `"positionSide"` - "net", "long", or "short" (required)
    - `"side"` - "buy" or "sell" (required)
    - `"size"` - Quantity (required)
    - `"orderType"` - "trigger" (required)
    - `"triggerPrice"` - Trigger price (required)
    - `"orderPrice"` - Execution price, "-1" for market (optional)
    - `"attachAlgoOrders"` - Attached TP/SL orders (optional)
  """
  @spec place_algo_order(client(), map()) :: response()
  def place_algo_order(client, params) do
    client
    |> Req.post(url: "/api/v1/trade/order-algo", json: params)
    |> Client.handle_response()
  end

  @doc """
  Cancels an algo order.

  ## Parameters

    - `"instId"` - Instrument ID (required)
    - `"algoId"` - Algo order ID (required)
  """
  @spec cancel_algo_order(client(), map()) :: response()
  def cancel_algo_order(client, params) do
    client
    |> Req.post(url: "/api/v1/trade/cancel-algo", json: params)
    |> Client.handle_response()
  end

  @doc """
  Retrieves active algo orders.

  ## Options

    - `:instId` - Filter by instrument
    - `:algoId` - Specific algo order ID
    - `:before` - Pagination cursor
    - `:after` - Pagination cursor
    - `:limit` - Maximum results
  """
  @spec get_algo_orders(client(), keyword()) :: response()
  def get_algo_orders(client, opts \\ []) do
    params = build_query(opts, [:instId, :algoId, :before, :after, :limit])

    client
    |> Req.get(url: "/api/v1/trade/orders-algo", params: params)
    |> Client.handle_response()
  end

  @doc """
  Retrieves algo order history.

  ## Options

    - `:instId` - Filter by instrument
    - `:before` - Pagination cursor
    - `:after` - Pagination cursor
    - `:limit` - Maximum results
  """
  @spec get_algo_order_history(client(), keyword()) :: response()
  def get_algo_order_history(client, opts \\ []) do
    params = build_query(opts, [:instId, :before, :after, :limit])

    client
    |> Req.get(url: "/api/v1/trade/order-algo-history", params: params)
    |> Client.handle_response()
  end

  # ===========================================================================
  # Other Trading Endpoints
  # ===========================================================================

  @doc """
  Retrieves trade execution history.

  ## Options

    - `:instId` - Filter by instrument
    - `:orderId` - Filter by order ID
    - `:before` - Pagination cursor
    - `:after` - Pagination cursor
    - `:limit` - Maximum results
  """
  @spec get_trade_history(client(), keyword()) :: response()
  def get_trade_history(client, opts \\ []) do
    params = build_query(opts, [:instId, :orderId, :before, :after, :limit])

    client
    |> Req.get(url: "/api/v1/trade/trade-history", params: params)
    |> Client.handle_response()
  end

  @doc """
  Retrieves the valid price range for orders on an instrument.

  ## Options

    - `:instId` - Instrument ID (required)
  """
  @spec get_order_price_range(client(), String.t()) :: response()
  def get_order_price_range(client, inst_id) do
    client
    |> Req.get(url: "/api/v1/trade/order-price-range", params: [instId: inst_id])
    |> Client.handle_response()
  end

  @doc """
  Closes a position.

  ## Parameters

    - `"instId"` - Instrument ID (required)
    - `"marginMode"` - "cross" or "isolated" (required)
    - `"positionSide"` - "net", "long", or "short"
    - `"clientOrderId"` - Client order ID (optional)
  """
  @spec close_position(client(), map()) :: response()
  def close_position(client, params) do
    client
    |> Req.post(url: "/api/v1/trade/close-position", json: params)
    |> Client.handle_response()
  end

  # ===========================================================================
  # Convenience Functions
  # ===========================================================================

  @doc """
  Places a market order with sensible defaults.

  ## Examples

      {:ok, result} = Trading.market_order(client, "BTC-USDT", "buy", "1")
      {:ok, result} = Trading.market_order(client, "BTC-USDT", "sell", "1",
        marginMode: "isolated", positionSide: "long")
  """
  @spec market_order(client(), String.t(), String.t(), String.t(), keyword()) :: response()
  def market_order(client, inst_id, side, size, opts \\ []) do
    params = %{
      "instId" => inst_id,
      "marginMode" => Keyword.get(opts, :marginMode, "cross"),
      "positionSide" => Keyword.get(opts, :positionSide, "net"),
      "side" => side,
      "orderType" => "market",
      "size" => size
    }

    place_order(client, params)
  end

  @doc """
  Places a limit order with sensible defaults.

  ## Examples

      {:ok, result} = Trading.limit_order(client, "BTC-USDT", "buy", "1", "49000.0")
  """
  @spec limit_order(client(), String.t(), String.t(), String.t(), String.t(), keyword()) ::
          response()
  def limit_order(client, inst_id, side, size, price, opts \\ []) do
    params = %{
      "instId" => inst_id,
      "marginMode" => Keyword.get(opts, :marginMode, "cross"),
      "positionSide" => Keyword.get(opts, :positionSide, "net"),
      "side" => side,
      "orderType" => "limit",
      "size" => size,
      "price" => price
    }

    place_order(client, params)
  end

  # ===========================================================================
  # Validation and Enums
  # ===========================================================================

  @doc "Returns valid order sides."
  @spec valid_sides() :: list(String.t())
  def valid_sides, do: @valid_sides

  @doc "Returns valid order types."
  @spec valid_order_types() :: list(String.t())
  def valid_order_types, do: @valid_order_types

  @doc "Returns valid margin modes."
  @spec valid_margin_modes() :: list(String.t())
  def valid_margin_modes, do: @valid_margin_modes

  @doc "Returns valid position sides."
  @spec valid_position_sides() :: list(String.t())
  def valid_position_sides, do: @valid_position_sides

  @doc """
  Validates order parameters.

  Returns `{:ok, params}` if valid, `{:error, reasons}` if invalid.
  """
  @spec validate_order_params(map()) :: {:ok, map()} | {:error, list(String.t())}
  def validate_order_params(params) do
    errors =
      []
      |> validate_required(params, "instId")
      |> validate_required(params, "marginMode")
      |> validate_required(params, "side")
      |> validate_required(params, "orderType")
      |> validate_required(params, "size")
      |> validate_inclusion(params, "side", @valid_sides)
      |> validate_inclusion(params, "orderType", @valid_order_types)
      |> validate_inclusion(params, "marginMode", @valid_margin_modes)
      |> validate_limit_price(params)

    case errors do
      [] -> {:ok, params}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  defp validate_required(errors, params, key) do
    if Map.has_key?(params, key) and params[key] not in [nil, ""] do
      errors
    else
      ["#{key} is required" | errors]
    end
  end

  defp validate_inclusion(errors, params, key, valid_values) do
    value = Map.get(params, key)

    if is_nil(value) or value in valid_values do
      errors
    else
      ["#{key} must be one of: #{Enum.join(valid_values, ", ")}" | errors]
    end
  end

  defp validate_limit_price(errors, params) do
    if Map.get(params, "orderType") in ["limit", "post_only"] and
         not Map.has_key?(params, "price") do
      ["price is required for limit/post_only orders" | errors]
    else
      errors
    end
  end
end
