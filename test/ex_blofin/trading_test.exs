defmodule ExBlofin.TradingTest do
  use ExUnit.Case, async: true

  alias ExBlofin.{Fixtures, Trading}

  @stub :trading_stub

  # ===========================================================================
  # Order Management
  # ===========================================================================

  describe "place_order/2" do
    test "places an order" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/trade/order"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.sample_place_order_response())
      end)

      client = Fixtures.test_client(@stub)

      params = %{
        "instId" => "BTC-USDT",
        "marginMode" => "cross",
        "positionSide" => "net",
        "side" => "buy",
        "orderType" => "market",
        "size" => "1"
      }

      assert {:ok, [%{"orderId" => "28150801"}]} = Trading.place_order(client, params)
    end
  end

  describe "place_batch_orders/2" do
    test "places multiple orders" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/trade/batch-orders"
        Req.Test.json(conn, Fixtures.sample_batch_orders_response())
      end)

      client = Fixtures.test_client(@stub)
      orders = [%{"instId" => "BTC-USDT"}, %{"instId" => "ETH-USDT"}]
      assert {:ok, results} = Trading.place_batch_orders(client, orders)
      assert length(results) == 2
    end
  end

  describe "cancel_order/2" do
    test "cancels an order" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/trade/cancel-order"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.sample_cancel_order_response())
      end)

      client = Fixtures.test_client(@stub)
      params = %{"instId" => "BTC-USDT", "orderId" => "28150801"}
      assert {:ok, [%{"orderId" => "28150801"}]} = Trading.cancel_order(client, params)
    end
  end

  describe "get_pending_orders/2" do
    test "returns pending orders" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/trade/orders-pending"
        Req.Test.json(conn, Fixtures.sample_pending_orders_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, [%{"state" => "live"}]} = Trading.get_pending_orders(client)
    end
  end

  describe "get_order_detail/2" do
    test "returns order details" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/trade/order-detail"
        query = URI.decode_query(conn.query_string)
        assert query["orderId"] == "28150801"
        Req.Test.json(conn, Fixtures.sample_order_detail_response())
      end)

      client = Fixtures.test_client(@stub)

      assert {:ok, [%{"orderId" => "28150801"}]} =
               Trading.get_order_detail(client, orderId: "28150801")
    end
  end

  describe "get_order_history/2" do
    test "returns order history" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/trade/order-history"
        Req.Test.json(conn, Fixtures.sample_order_history_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, orders} = Trading.get_order_history(client)
      assert length(orders) == 2
    end
  end

  # ===========================================================================
  # TP/SL Orders
  # ===========================================================================

  describe "place_tpsl_order/2" do
    test "places a TP/SL order" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/trade/order-tpsl"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.sample_tpsl_order_response())
      end)

      client = Fixtures.test_client(@stub)

      params = %{
        "instId" => "BTC-USDT",
        "marginMode" => "cross",
        "positionSide" => "net",
        "side" => "sell",
        "size" => "-1",
        "tpTriggerPrice" => "55000",
        "slTriggerPrice" => "45000"
      }

      assert {:ok, [%{"tpslId" => "tpsl-123"}]} = Trading.place_tpsl_order(client, params)
    end
  end

  describe "cancel_tpsl_order/2" do
    test "cancels a TP/SL order" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/trade/cancel-tpsl"
        Req.Test.json(conn, Fixtures.sample_tpsl_order_response())
      end)

      client = Fixtures.test_client(@stub)

      assert {:ok, _} =
               Trading.cancel_tpsl_order(client, %{"instId" => "BTC-USDT", "tpslId" => "tpsl-123"})
    end

    test "sends params wrapped in an array" do
      Req.Test.expect(@stub, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert is_list(decoded)
        assert [%{"instId" => "BTC-USDT", "tpslId" => "tpsl-123"}] = decoded
        Req.Test.json(conn, Fixtures.sample_tpsl_order_response())
      end)

      client = Fixtures.test_client(@stub)

      assert {:ok, _} =
               Trading.cancel_tpsl_order(client, %{"instId" => "BTC-USDT", "tpslId" => "tpsl-123"})
    end
  end

  describe "get_tpsl_orders/2" do
    test "returns TP/SL orders" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/trade/orders-tpsl"
        Req.Test.json(conn, Fixtures.sample_tpsl_order_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, _} = Trading.get_tpsl_orders(client)
    end
  end

  # ===========================================================================
  # Algo Orders
  # ===========================================================================

  describe "place_algo_order/2" do
    test "places an algo order" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/trade/order-algo"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.sample_algo_order_response())
      end)

      client = Fixtures.test_client(@stub)

      params = %{
        "instId" => "BTC-USDT",
        "marginMode" => "cross",
        "positionSide" => "net",
        "side" => "buy",
        "size" => "1",
        "orderType" => "trigger",
        "triggerPrice" => "48000"
      }

      assert {:ok, [%{"algoId" => "algo-123"}]} = Trading.place_algo_order(client, params)
    end
  end

  describe "cancel_algo_order/2" do
    test "cancels an algo order" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/trade/cancel-algo"
        Req.Test.json(conn, Fixtures.sample_algo_order_response())
      end)

      client = Fixtures.test_client(@stub)

      assert {:ok, _} =
               Trading.cancel_algo_order(client, %{"instId" => "BTC-USDT", "algoId" => "algo-123"})
    end
  end

  # ===========================================================================
  # Other Trading Endpoints
  # ===========================================================================

  describe "get_trade_history/2" do
    test "returns trade history" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/trade/trade-history"
        Req.Test.json(conn, Fixtures.sample_trade_history_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, [%{"tradeId" => _}]} = Trading.get_trade_history(client)
    end
  end

  describe "get_order_price_range/2" do
    test "returns price range" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/trade/order-price-range"
        query = URI.decode_query(conn.query_string)
        assert query["instId"] == "BTC-USDT"
        Req.Test.json(conn, Fixtures.sample_order_price_range_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, [%{"highLimitPrice" => _}]} = Trading.get_order_price_range(client, "BTC-USDT")
    end
  end

  describe "close_position/2" do
    test "closes a position" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/trade/close-position"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.sample_close_position_response())
      end)

      client = Fixtures.test_client(@stub)
      params = %{"instId" => "BTC-USDT", "marginMode" => "cross"}
      assert {:ok, _} = Trading.close_position(client, params)
    end
  end

  # ===========================================================================
  # Convenience Functions
  # ===========================================================================

  describe "market_order/5" do
    test "places a market buy order" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/trade/order"
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["instId"] == "BTC-USDT"
        assert decoded["side"] == "buy"
        assert decoded["orderType"] == "market"
        assert decoded["marginMode"] == "cross"
        assert decoded["positionSide"] == "net"
        Req.Test.json(conn, Fixtures.sample_place_order_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, _} = Trading.market_order(client, "BTC-USDT", "buy", "1")
    end
  end

  describe "limit_order/6" do
    test "places a limit buy order" do
      Req.Test.expect(@stub, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["orderType"] == "limit"
        assert decoded["price"] == "49000.0"
        Req.Test.json(conn, Fixtures.sample_place_order_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, _} = Trading.limit_order(client, "BTC-USDT", "buy", "1", "49000.0")
    end
  end

  # ===========================================================================
  # Validation
  # ===========================================================================

  describe "validate_order_params/1" do
    test "validates a valid order" do
      params = %{
        "instId" => "BTC-USDT",
        "marginMode" => "cross",
        "side" => "buy",
        "orderType" => "market",
        "size" => "1"
      }

      assert {:ok, ^params} = Trading.validate_order_params(params)
    end

    test "rejects missing required fields" do
      assert {:error, errors} = Trading.validate_order_params(%{})
      assert "instId is required" in errors
      assert "side is required" in errors
      assert "size is required" in errors
    end

    test "rejects invalid side" do
      params = %{
        "instId" => "BTC-USDT",
        "marginMode" => "cross",
        "side" => "invalid",
        "orderType" => "market",
        "size" => "1"
      }

      assert {:error, errors} = Trading.validate_order_params(params)
      assert Enum.any?(errors, &String.contains?(&1, "side must be"))
    end

    test "requires price for limit orders" do
      params = %{
        "instId" => "BTC-USDT",
        "marginMode" => "cross",
        "side" => "buy",
        "orderType" => "limit",
        "size" => "1"
      }

      assert {:error, errors} = Trading.validate_order_params(params)
      assert "price is required for limit/post_only orders" in errors
    end

    test "accepts limit order with price" do
      params = %{
        "instId" => "BTC-USDT",
        "marginMode" => "cross",
        "side" => "buy",
        "orderType" => "limit",
        "size" => "1",
        "price" => "49000.0"
      }

      assert {:ok, ^params} = Trading.validate_order_params(params)
    end
  end

  describe "enums" do
    test "valid_sides/0 returns sides" do
      assert "buy" in Trading.valid_sides()
      assert "sell" in Trading.valid_sides()
    end

    test "valid_order_types/0 returns order types" do
      assert "market" in Trading.valid_order_types()
      assert "limit" in Trading.valid_order_types()
    end

    test "valid_margin_modes/0 returns margin modes" do
      assert "cross" in Trading.valid_margin_modes()
      assert "isolated" in Trading.valid_margin_modes()
    end

    test "valid_position_sides/0 returns position sides" do
      assert "net" in Trading.valid_position_sides()
      assert "long" in Trading.valid_position_sides()
    end
  end
end
