defmodule ExBlofin.Fixtures do
  @moduledoc """
  Test fixtures for ExBlofin API testing.
  """

  # ===========================================================================
  # Credentials
  # ===========================================================================

  def sample_api_key, do: "test-api-key-123"
  def sample_secret_key, do: "test-secret-key-456"
  def sample_passphrase, do: "test-passphrase"

  # ===========================================================================
  # Test Client Factory
  # ===========================================================================

  def test_client(stub_name) do
    sample_api_key()
    |> ExBlofin.Client.new(
      sample_secret_key(),
      sample_passphrase(),
      plug: {Req.Test, stub_name}
    )
    |> Req.Request.merge_options(retry: false)
  end

  # ===========================================================================
  # BloFin Response Helpers
  # ===========================================================================

  @doc """
  Wraps data in standard BloFin success response envelope.
  """
  def success_response(data) do
    %{"code" => "0", "msg" => "", "data" => data}
  end

  @doc """
  Creates a BloFin error response envelope.
  """
  def error_response(code, msg) do
    %{"code" => code, "msg" => msg, "data" => []}
  end

  # ===========================================================================
  # Market Data Responses
  # ===========================================================================

  def sample_instruments_response do
    success_response([
      %{
        "instId" => "BTC-USDT",
        "baseCurrency" => "BTC",
        "quoteCurrency" => "USDT",
        "contractValue" => "0.001",
        "listTime" => "1597026383085",
        "maxLeverage" => "125",
        "minSize" => "1",
        "lotSize" => "1",
        "tickSize" => "0.1",
        "instType" => "SWAP",
        "contractType" => "linear",
        "maxLimitSize" => "100000",
        "maxMarketSize" => "10000",
        "state" => "live",
        "settleCurrency" => "USDT"
      },
      %{
        "instId" => "ETH-USDT",
        "baseCurrency" => "ETH",
        "quoteCurrency" => "USDT",
        "contractValue" => "0.01",
        "listTime" => "1597026383085",
        "maxLeverage" => "100",
        "minSize" => "1",
        "lotSize" => "1",
        "tickSize" => "0.01",
        "instType" => "SWAP",
        "contractType" => "linear",
        "maxLimitSize" => "100000",
        "maxMarketSize" => "10000",
        "state" => "live",
        "settleCurrency" => "USDT"
      }
    ])
  end

  def sample_tickers_response do
    success_response([
      %{
        "instId" => "BTC-USDT",
        "last" => "50000.0",
        "lastSize" => "0.5",
        "askPrice" => "50001.0",
        "askSize" => "1.0",
        "bidPrice" => "49999.0",
        "bidSize" => "2.0",
        "open24h" => "49000.0",
        "high24h" => "51000.0",
        "low24h" => "48000.0",
        "volCurrency24h" => "500000000",
        "vol24h" => "10000",
        "ts" => "1697021343571"
      }
    ])
  end

  def sample_books_response do
    success_response([
      %{
        "asks" => [
          ["50001.0", "1.5", "0", "3"],
          ["50002.0", "2.0", "0", "5"]
        ],
        "bids" => [
          ["49999.0", "2.0", "0", "4"],
          ["49998.0", "1.0", "0", "2"]
        ],
        "ts" => "1697021343571"
      }
    ])
  end

  def sample_trades_response do
    success_response([
      %{
        "instId" => "BTC-USDT",
        "tradeId" => "12345",
        "price" => "50000.0",
        "size" => "0.5",
        "side" => "buy",
        "ts" => "1697021343571"
      }
    ])
  end

  def sample_mark_price_response do
    success_response([
      %{
        "instId" => "BTC-USDT",
        "instType" => "SWAP",
        "markPrice" => "50000.5",
        "ts" => "1697021343571"
      }
    ])
  end

  def sample_funding_rate_response do
    success_response([
      %{
        "instId" => "BTC-USDT",
        "fundingRate" => "0.0001",
        "nextFundingRate" => "0.00012",
        "fundingTime" => "1697025600000",
        "nextFundingTime" => "1697054400000"
      }
    ])
  end

  def sample_funding_rate_history_response do
    success_response([
      %{
        "instId" => "BTC-USDT",
        "fundingRate" => "0.0001",
        "realizedRate" => "0.00009",
        "fundingTime" => "1697025600000"
      }
    ])
  end

  def sample_candles_response do
    success_response([
      ["1697021343571", "50000.0", "50500.0", "49500.0", "50200.0", "100.5", "5025000"],
      ["1697017743571", "49800.0", "50100.0", "49700.0", "50000.0", "85.2", "4250000"]
    ])
  end

  # ===========================================================================
  # Account Responses
  # ===========================================================================

  def sample_account_balance_response do
    success_response([
      %{
        "ts" => "1697021343571",
        "totalEquity" => "10011254.077985990315787910",
        "isolatedEquity" => "861.763132108800000000",
        "details" => [
          %{
            "currency" => "USDT",
            "equity" => "10014042.988958415234430699",
            "balance" => "10013119.885958415234430699",
            "ts" => "1697021343571",
            "isolatedEquity" => "862.003200000000000000",
            "available" => "9996399.470869115970336272",
            "availableEquity" => "9996399.470869115970336272",
            "frozen" => "15805.149672632597427761",
            "orderFrozen" => "14920.994472632597427761",
            "equityUsd" => "10011254.077985990315787910",
            "isolatedUnrealizedPnl" => "-22.151999999999999999",
            "bonus" => "0"
          }
        ]
      }
    ])
  end

  def sample_positions_response do
    success_response([
      %{
        "positionId" => "12345",
        "instId" => "BTC-USDT",
        "instType" => "SWAP",
        "marginMode" => "cross",
        "positionSide" => "long",
        "leverage" => "10",
        "positions" => "100",
        "availablePositions" => "100",
        "averagePrice" => "50000.0",
        "markPrice" => "50500.0",
        "marginRatio" => "0.15",
        "liquidationPrice" => "45000.0",
        "unrealizedPnl" => "50.0",
        "unrealizedPnlRatio" => "0.1",
        "initialMargin" => "500.0",
        "maintenanceMargin" => "25.0",
        "createTime" => "1697021343571",
        "updateTime" => "1697021343571",
        "adl" => "1"
      }
    ])
  end

  def sample_account_config_response do
    success_response([
      %{
        "accountLevel" => "1",
        "positionMode" => "net_mode",
        "uid" => "123456"
      }
    ])
  end

  def sample_margin_mode_response do
    success_response([
      %{
        "instId" => "BTC-USDT",
        "marginMode" => "cross"
      }
    ])
  end

  def sample_leverage_info_response do
    success_response([
      %{
        "instId" => "BTC-USDT",
        "lever" => "10",
        "marginMode" => "cross",
        "positionSide" => "net"
      }
    ])
  end

  # ===========================================================================
  # Asset Responses
  # ===========================================================================

  def sample_asset_balances_response do
    success_response([
      %{
        "currency" => "USDT",
        "balance" => "10000.0",
        "available" => "9500.0",
        "frozen" => "500.0"
      },
      %{
        "currency" => "BTC",
        "balance" => "1.5",
        "available" => "1.5",
        "frozen" => "0"
      }
    ])
  end

  def sample_transfer_response do
    success_response([
      %{
        "transferId" => "trans-123",
        "currency" => "USDT",
        "amount" => "100.0"
      }
    ])
  end

  def sample_bills_response do
    success_response([
      %{
        "billId" => "bill-123",
        "currency" => "USDT",
        "balance" => "10000.0",
        "balanceChange" => "100.0",
        "type" => "transfer",
        "ts" => "1697021343571"
      }
    ])
  end

  # ===========================================================================
  # Trading Responses
  # ===========================================================================

  def sample_place_order_response do
    success_response([
      %{
        "orderId" => "28150801",
        "clientOrderId" => "test1597321",
        "msg" => "",
        "code" => "0"
      }
    ])
  end

  def sample_batch_orders_response do
    success_response([
      %{
        "orderId" => "28150801",
        "clientOrderId" => "test001",
        "msg" => "",
        "code" => "0"
      },
      %{
        "orderId" => "28150802",
        "clientOrderId" => "test002",
        "msg" => "",
        "code" => "0"
      }
    ])
  end

  def sample_cancel_order_response do
    success_response([
      %{
        "orderId" => "28150801",
        "clientOrderId" => "test1597321",
        "msg" => "",
        "code" => "0"
      }
    ])
  end

  def sample_pending_orders_response do
    success_response([
      %{
        "orderId" => "28150801",
        "instId" => "BTC-USDT",
        "marginMode" => "cross",
        "positionSide" => "net",
        "side" => "buy",
        "orderType" => "limit",
        "price" => "49000.0",
        "size" => "10",
        "state" => "live",
        "leverage" => "10",
        "createTime" => "1697021343571",
        "updateTime" => "1697021343571"
      }
    ])
  end

  def sample_order_detail_response do
    success_response([
      %{
        "orderId" => "28150801",
        "instId" => "BTC-USDT",
        "marginMode" => "cross",
        "positionSide" => "net",
        "side" => "buy",
        "orderType" => "limit",
        "price" => "49000.0",
        "size" => "10",
        "state" => "filled",
        "fillPrice" => "49000.0",
        "fillSize" => "10",
        "fee" => "-2.94",
        "pnl" => "0",
        "leverage" => "10",
        "createTime" => "1697021343571",
        "updateTime" => "1697021343571"
      }
    ])
  end

  def sample_order_history_response do
    success_response([
      %{
        "orderId" => "28150801",
        "instId" => "BTC-USDT",
        "side" => "buy",
        "orderType" => "limit",
        "state" => "filled",
        "createTime" => "1697021343571"
      },
      %{
        "orderId" => "28150800",
        "instId" => "ETH-USDT",
        "side" => "sell",
        "orderType" => "market",
        "state" => "filled",
        "createTime" => "1697021243571"
      }
    ])
  end

  def sample_tpsl_order_response do
    success_response([
      %{
        "tpslId" => "tpsl-123",
        "clientOrderId" => "test-tpsl",
        "msg" => "",
        "code" => "0"
      }
    ])
  end

  def sample_algo_order_response do
    success_response([
      %{
        "algoId" => "algo-123",
        "clientOrderId" => "test-algo",
        "msg" => "",
        "code" => "0"
      }
    ])
  end

  def sample_trade_history_response do
    success_response([
      %{
        "instId" => "BTC-USDT",
        "tradeId" => "trade-1",
        "orderId" => "28150801",
        "price" => "50000.0",
        "size" => "10",
        "side" => "buy",
        "fee" => "-2.94",
        "ts" => "1697021343571"
      }
    ])
  end

  def sample_order_price_range_response do
    success_response([
      %{
        "instId" => "BTC-USDT",
        "highLimitPrice" => "55000.0",
        "lowLimitPrice" => "45000.0"
      }
    ])
  end

  def sample_close_position_response do
    success_response([
      %{
        "instId" => "BTC-USDT",
        "positionSide" => "net"
      }
    ])
  end

  # ===========================================================================
  # Copy Trading Responses
  # ===========================================================================

  def sample_copy_trading_balance_response do
    success_response([
      %{
        "totalEquity" => "10000.0",
        "details" => [
          %{
            "currency" => "USDT",
            "equity" => "10000.0",
            "available" => "9000.0"
          }
        ]
      }
    ])
  end

  def sample_copy_trading_positions_response do
    success_response([
      %{
        "instId" => "BTC-USDT",
        "positionSide" => "long",
        "leverage" => "10",
        "positions" => "50",
        "averagePrice" => "50000.0",
        "unrealizedPnl" => "25.0"
      }
    ])
  end

  # ===========================================================================
  # Affiliate Responses
  # ===========================================================================

  def sample_affiliate_info_response do
    success_response([
      %{
        "uid" => "123456",
        "level" => "1",
        "totalCommission" => "1000.0"
      }
    ])
  end

  def sample_referral_code_response do
    success_response([
      %{
        "referralCode" => "ABC123",
        "referralLink" => "https://blofin.com/register?referralCode=ABC123"
      }
    ])
  end

  # ===========================================================================
  # User Responses
  # ===========================================================================

  def sample_api_key_info_response do
    success_response([
      %{
        "apiKey" => "test-api-key",
        "label" => "Trading Bot",
        "permissions" => "read,trade",
        "ip" => "192.168.1.1",
        "createTime" => "1697021343571"
      }
    ])
  end

  # ===========================================================================
  # Tax Responses
  # ===========================================================================

  def sample_tax_deposit_history_response do
    success_response([
      %{
        "depositId" => "dep-123",
        "currency" => "USDT",
        "amount" => "1000.0",
        "ts" => "1697021343571"
      }
    ])
  end

  def sample_tax_futures_trade_history_response do
    success_response([
      %{
        "tradeId" => "trade-123",
        "instId" => "BTC-USDT",
        "side" => "buy",
        "price" => "50000.0",
        "size" => "10",
        "fee" => "-2.94",
        "pnl" => "50.0",
        "ts" => "1697021343571"
      }
    ])
  end

  # ===========================================================================
  # WebSocket Event Fixtures
  # ===========================================================================

  def sample_ws_trade_event do
    %{
      "arg" => %{"channel" => "trades", "instId" => "BTC-USDT"},
      "data" => [
        %{
          "instId" => "BTC-USDT",
          "tradeId" => "12345",
          "price" => "50000.0",
          "size" => "0.5",
          "side" => "buy",
          "ts" => "1697021343571"
        }
      ]
    }
  end

  def sample_ws_ticker_event do
    %{
      "arg" => %{"channel" => "tickers", "instId" => "BTC-USDT"},
      "data" => [
        %{
          "instId" => "BTC-USDT",
          "last" => "50000.0",
          "askPrice" => "50001.0",
          "bidPrice" => "49999.0",
          "vol24h" => "10000",
          "ts" => "1697021343571"
        }
      ]
    }
  end

  def sample_ws_order_event do
    %{
      "arg" => %{"channel" => "orders"},
      "data" => [
        %{
          "orderId" => "28150801",
          "instId" => "BTC-USDT",
          "side" => "buy",
          "orderType" => "limit",
          "state" => "filled",
          "price" => "49000.0",
          "size" => "10",
          "fillPrice" => "49000.0",
          "fillSize" => "10",
          "ts" => "1697021343571"
        }
      ]
    }
  end

  def sample_ws_position_event do
    %{
      "arg" => %{"channel" => "positions"},
      "data" => [
        %{
          "positionId" => "12345",
          "instId" => "BTC-USDT",
          "positionSide" => "long",
          "positions" => "100",
          "averagePrice" => "50000.0",
          "unrealizedPnl" => "50.0",
          "ts" => "1697021343571"
        }
      ]
    }
  end

  def sample_ws_account_event do
    %{
      "arg" => %{"channel" => "account"},
      "data" => [
        %{
          "totalEquity" => "10000.0",
          "details" => [
            %{
              "currency" => "USDT",
              "equity" => "10000.0",
              "available" => "9000.0"
            }
          ],
          "ts" => "1697021343571"
        }
      ]
    }
  end

  def sample_ws_login_success do
    %{
      "event" => "login",
      "code" => "0",
      "msg" => ""
    }
  end

  def sample_ws_login_failure do
    %{
      "event" => "login",
      "code" => "60009",
      "msg" => "Login failed"
    }
  end

  def sample_ws_subscribe_success do
    %{
      "event" => "subscribe",
      "arg" => %{"channel" => "trades", "instId" => "BTC-USDT"}
    }
  end

  def sample_ws_error do
    %{
      "event" => "error",
      "code" => "60012",
      "msg" => "Invalid request"
    }
  end
end
