defmodule ExBlofin.WebSocket.MessageTest do
  use ExUnit.Case, async: true

  alias ExBlofin.Fixtures
  alias ExBlofin.WebSocket.Message

  # ============================================================================
  # Message Building
  # ============================================================================

  describe "build_login/3" do
    test "builds a login message with signature" do
      msg = Message.build_login("my-key", "my-secret", "my-pass")

      assert msg["op"] == "login"
      assert [args] = msg["args"]
      assert args["apiKey"] == "my-key"
      assert args["passphrase"] == "my-pass"
      assert is_binary(args["timestamp"])
      assert is_binary(args["nonce"])
      assert is_binary(args["sign"])
    end
  end

  describe "build_subscribe/1" do
    test "builds a subscribe message for a single channel" do
      msg = Message.build_subscribe([%{"channel" => "trades", "instId" => "BTC-USDT"}])

      assert msg == %{
               "op" => "subscribe",
               "args" => [%{"channel" => "trades", "instId" => "BTC-USDT"}]
             }
    end

    test "builds a subscribe message for multiple channels" do
      channels = [
        %{"channel" => "trades", "instId" => "BTC-USDT"},
        %{"channel" => "tickers", "instId" => "ETH-USDT"}
      ]

      msg = Message.build_subscribe(channels)

      assert msg["op"] == "subscribe"
      assert length(msg["args"]) == 2
    end
  end

  describe "build_unsubscribe/1" do
    test "builds an unsubscribe message" do
      msg = Message.build_unsubscribe([%{"channel" => "trades", "instId" => "BTC-USDT"}])

      assert msg == %{
               "op" => "unsubscribe",
               "args" => [%{"channel" => "trades", "instId" => "BTC-USDT"}]
             }
    end
  end

  describe "build_ping/0" do
    test "returns the ping string" do
      assert Message.build_ping() == "ping"
    end
  end

  describe "encode/1" do
    test "encodes a message to JSON" do
      msg = %{"op" => "subscribe", "args" => []}
      assert {:ok, json} = Message.encode(msg)
      assert {:ok, ^msg} = Jason.decode(json)
    end
  end

  # ============================================================================
  # Control Event Parsing
  # ============================================================================

  describe "parse/1 - control events" do
    test "parses pong" do
      assert {:ok, :pong, nil} = Message.parse("pong")
    end

    test "parses login success" do
      raw = Jason.encode!(Fixtures.sample_ws_login_success())
      assert {:ok, :login, %{code: "0", msg: ""}} = Message.parse(raw)
    end

    test "parses login failure" do
      raw = Jason.encode!(Fixtures.sample_ws_login_failure())
      assert {:ok, :login, %{code: "60009", msg: "Login failed"}} = Message.parse(raw)
    end

    test "parses subscribe confirmation" do
      raw = Jason.encode!(Fixtures.sample_ws_subscribe_success())

      assert {:ok, :subscribe, %{"channel" => "trades", "instId" => "BTC-USDT"}} =
               Message.parse(raw)
    end

    test "parses unsubscribe confirmation" do
      raw =
        Jason.encode!(%{
          "event" => "unsubscribe",
          "arg" => %{"channel" => "trades", "instId" => "BTC-USDT"}
        })

      assert {:ok, :unsubscribe, %{"channel" => "trades"}} = Message.parse(raw)
    end

    test "parses error event" do
      raw = Jason.encode!(Fixtures.sample_ws_error())
      assert {:ok, :error, %{code: "60012", msg: "Invalid request"}} = Message.parse(raw)
    end

    test "returns error for invalid JSON" do
      assert {:error, :invalid_json} = Message.parse("not json {{{")
    end

    test "returns error for unknown message format" do
      raw = Jason.encode!(%{"something" => "unexpected"})
      assert {:error, :unknown_message_format} = Message.parse(raw)
    end
  end

  # ============================================================================
  # Public Channel Parsing
  # ============================================================================

  describe "parse/1 - trades" do
    test "parses trade events" do
      raw = Jason.encode!(Fixtures.sample_ws_trade_event())
      assert {:ok, :trades, [trade]} = Message.parse(raw)
      assert %Message.TradeEvent{} = trade
      assert trade.inst_id == "BTC-USDT"
      assert trade.trade_id == "12345"
      assert trade.price == "50000.0"
      assert trade.size == "0.5"
      assert trade.side == "buy"
      assert trade.ts == "1697021343571"
    end
  end

  describe "parse/1 - tickers" do
    test "parses ticker events" do
      raw = Jason.encode!(Fixtures.sample_ws_ticker_event())
      assert {:ok, :tickers, [ticker]} = Message.parse(raw)
      assert %Message.TickerEvent{} = ticker
      assert ticker.inst_id == "BTC-USDT"
      assert ticker.last == "50000.0"
      assert ticker.ask_price == "50001.0"
      assert ticker.bid_price == "49999.0"
      assert ticker.vol_24h == "10000"
    end
  end

  describe "parse/1 - books" do
    test "parses order book events" do
      raw =
        Jason.encode!(%{
          "arg" => %{"channel" => "books", "instId" => "BTC-USDT"},
          "data" => [
            %{
              "asks" => [["50001.0", "1.5", "0", "3"]],
              "bids" => [["49999.0", "2.0", "0", "4"]],
              "ts" => "1697021343571",
              "checksum" => -1234,
              "action" => "snapshot"
            }
          ]
        })

      assert {:ok, :books, [book]} = Message.parse(raw)
      assert %Message.BookEvent{} = book
      assert book.inst_id == "BTC-USDT"
      assert book.asks == [["50001.0", "1.5", "0", "3"]]
      assert book.bids == [["49999.0", "2.0", "0", "4"]]
      assert book.checksum == -1234
      assert book.action == "snapshot"
    end

    test "parses books5 events" do
      raw =
        Jason.encode!(%{
          "arg" => %{"channel" => "books5", "instId" => "ETH-USDT"},
          "data" => [
            %{
              "asks" => [["3000.0", "10", "0", "2"]],
              "bids" => [["2999.0", "5", "0", "1"]],
              "ts" => "1697021343571"
            }
          ]
        })

      assert {:ok, :books5, [book]} = Message.parse(raw)
      assert %Message.BookEvent{} = book
      assert book.inst_id == "ETH-USDT"
    end
  end

  describe "parse/1 - candles" do
    test "parses candle events (array format)" do
      raw =
        Jason.encode!(%{
          "arg" => %{"channel" => "candle1m", "instId" => "BTC-USDT"},
          "data" => [
            ["1697021343571", "50000.0", "50500.0", "49500.0", "50200.0", "100.5", "5025000", "1"]
          ]
        })

      assert {:ok, :candle1m, [candle]} = Message.parse(raw)
      assert %Message.CandleEvent{} = candle
      assert candle.inst_id == "BTC-USDT"
      assert candle.ts == "1697021343571"
      assert candle.open == "50000.0"
      assert candle.high == "50500.0"
      assert candle.low == "49500.0"
      assert candle.close == "50200.0"
      assert candle.vol == "100.5"
      assert candle.vol_currency == "5025000"
      assert candle.confirm == "1"
    end
  end

  describe "parse/1 - funding-rate" do
    test "parses funding rate events" do
      raw =
        Jason.encode!(%{
          "arg" => %{"channel" => "funding-rate", "instId" => "BTC-USDT"},
          "data" => [
            %{
              "instId" => "BTC-USDT",
              "fundingRate" => "0.0001",
              "nextFundingRate" => "0.00012",
              "fundingTime" => "1697025600000",
              "nextFundingTime" => "1697054400000"
            }
          ]
        })

      assert {:ok, :funding_rate, [event]} = Message.parse(raw)
      assert %Message.FundingRateEvent{} = event
      assert event.inst_id == "BTC-USDT"
      assert event.funding_rate == "0.0001"
      assert event.next_funding_rate == "0.00012"
    end
  end

  # ============================================================================
  # Private Channel Parsing
  # ============================================================================

  describe "parse/1 - orders" do
    test "parses order events" do
      raw = Jason.encode!(Fixtures.sample_ws_order_event())
      assert {:ok, :orders, [order]} = Message.parse(raw)
      assert %Message.OrderEvent{} = order
      assert order.order_id == "28150801"
      assert order.inst_id == "BTC-USDT"
      assert order.side == "buy"
      assert order.order_type == "limit"
      assert order.state == "filled"
      assert order.price == "49000.0"
      assert order.fill_price == "49000.0"
      assert order.fill_size == "10"
    end
  end

  describe "parse/1 - orders-algo" do
    test "parses algo order events" do
      raw =
        Jason.encode!(%{
          "arg" => %{"channel" => "orders-algo"},
          "data" => [
            %{
              "algoId" => "algo-123",
              "instId" => "BTC-USDT",
              "marginMode" => "cross",
              "positionSide" => "net",
              "side" => "buy",
              "orderType" => "trigger",
              "size" => "10",
              "state" => "live",
              "triggerPrice" => "48000.0",
              "triggerType" => "last",
              "createTime" => "1697021343571",
              "updateTime" => "1697021343571"
            }
          ]
        })

      assert {:ok, :orders_algo, [algo]} = Message.parse(raw)
      assert %Message.AlgoOrderEvent{} = algo
      assert algo.algo_id == "algo-123"
      assert algo.inst_id == "BTC-USDT"
      assert algo.state == "live"
      assert algo.trigger_price == "48000.0"
    end
  end

  describe "parse/1 - positions" do
    test "parses position events" do
      raw = Jason.encode!(Fixtures.sample_ws_position_event())
      assert {:ok, :positions, [position]} = Message.parse(raw)
      assert %Message.PositionEvent{} = position
      assert position.position_id == "12345"
      assert position.inst_id == "BTC-USDT"
      assert position.position_side == "long"
      assert position.positions == "100"
      assert position.average_price == "50000.0"
      assert position.unrealized_pnl == "50.0"
    end
  end

  describe "parse/1 - account" do
    test "parses account events" do
      raw = Jason.encode!(Fixtures.sample_ws_account_event())
      assert {:ok, :account, [account]} = Message.parse(raw)
      assert %Message.AccountEvent{} = account
      assert account.total_equity == "10000.0"
      assert is_list(account.details)
      assert account.ts == "1697021343571"
    end
  end

  # ============================================================================
  # Copy Trading Channel Parsing
  # ============================================================================

  describe "parse/1 - copytrading channels" do
    test "parses copy trading positions by contract" do
      raw =
        Jason.encode!(%{
          "arg" => %{"channel" => "copytrading-positions-by-contract"},
          "data" => [
            %{
              "instId" => "BTC-USDT",
              "positionSide" => "long",
              "positions" => "50",
              "averagePrice" => "50000.0",
              "unrealizedPnl" => "25.0",
              "leverage" => "10",
              "marginMode" => "cross",
              "updateTime" => "1697021343571"
            }
          ]
        })

      assert {:ok, :copytrading_positions_by_contract, [pos]} = Message.parse(raw)
      assert %Message.CopyPositionEvent{} = pos
      assert pos.inst_id == "BTC-USDT"
      assert pos.positions == "50"
    end

    test "parses copy trading orders" do
      raw =
        Jason.encode!(%{
          "arg" => %{"channel" => "copytrading-orders"},
          "data" => [
            %{
              "orderId" => "ct-123",
              "instId" => "BTC-USDT",
              "side" => "buy",
              "orderType" => "market",
              "price" => "50000.0",
              "size" => "10",
              "state" => "filled",
              "fillPrice" => "50000.0",
              "fillSize" => "10",
              "createTime" => "1697021343571",
              "updateTime" => "1697021343571"
            }
          ]
        })

      assert {:ok, :copytrading_orders, [order]} = Message.parse(raw)
      assert %Message.CopyOrderEvent{} = order
      assert order.order_id == "ct-123"
      assert order.state == "filled"
    end

    test "parses copy trading account" do
      raw =
        Jason.encode!(%{
          "arg" => %{"channel" => "copytrading-account"},
          "data" => [
            %{
              "totalEquity" => "10000.0",
              "details" => [%{"currency" => "USDT", "equity" => "10000.0"}],
              "ts" => "1697021343571"
            }
          ]
        })

      assert {:ok, :copytrading_account, [account]} = Message.parse(raw)
      assert %Message.CopyAccountEvent{} = account
      assert account.total_equity == "10000.0"
      assert is_list(account.details)
    end
  end
end
