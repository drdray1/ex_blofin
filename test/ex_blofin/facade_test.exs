defmodule ExBlofin.FacadeTest do
  @moduledoc """
  Guards the `ExBlofin` delegate surface against signature drift.

  `defdelegate` only checks arity, not argument meaning, so a delegate whose
  parameter order disagrees with its target compiles cleanly and fails at
  runtime. Three delegates were broken that way; these tests pin them.
  """
  use ExUnit.Case, async: true

  alias ExBlofin.Fixtures

  @stub :facade_stub

  # `function_exported?/3` reports false for a module that merely hasn't been
  # loaded yet, which would make the assertions below pass vacuously.
  setup_all do
    Code.ensure_loaded!(ExBlofin)
    :ok
  end

  describe "get_order_price_range/2" do
    test "accepts an instrument id, not an options list" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/trade/order/price-range"
        assert URI.decode_query(conn.query_string)["instId"] == "BTC-USDT"
        Req.Test.json(conn, Fixtures.success_response(%{"maxPrice" => "1", "minPrice" => "0"}))
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, _} = ExBlofin.get_order_price_range(client, "BTC-USDT")
    end

    test "is not exposed at arity 1" do
      # The old delegate defaulted `opts`, generating an arity-1 clause that had
      # no counterpart in ExBlofin.Trading and raised on every call.
      refute function_exported?(ExBlofin, :get_order_price_range, 1)
      assert function_exported?(ExBlofin, :get_order_price_range, 2)
    end
  end

  describe "market_order/4" do
    test "treats the 4th argument as size and defaults margin/position side" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/trade/order"
        body = decode_body(conn)

        assert body["size"] == "10"
        assert body["orderType"] == "market"
        assert body["marginMode"] == "cross"
        assert body["positionSide"] == "net"

        Req.Test.json(conn, Fixtures.sample_place_order_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, _} = ExBlofin.market_order(client, "BTC-USDT", "buy", "10")
    end

    test "accepts overrides via opts" do
      Req.Test.expect(@stub, fn conn ->
        body = decode_body(conn)
        assert body["marginMode"] == "isolated"
        assert body["positionSide"] == "long"
        Req.Test.json(conn, Fixtures.sample_place_order_response())
      end)

      client = Fixtures.test_client(@stub)

      assert {:ok, _} =
               ExBlofin.market_order(client, "BTC-USDT", "buy", "10",
                 marginMode: "isolated",
                 positionSide: "long"
               )
    end
  end

  describe "limit_order/5" do
    test "treats the 4th and 5th arguments as size and price" do
      Req.Test.expect(@stub, fn conn ->
        body = decode_body(conn)

        assert body["size"] == "10"
        assert body["price"] == "50000.0"
        assert body["orderType"] == "limit"

        Req.Test.json(conn, Fixtures.sample_place_order_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, _} = ExBlofin.limit_order(client, "BTC-USDT", "buy", "10", "50000.0")
    end
  end

  describe "delegate coverage" do
    # Coverage had silently drifted: CopyTrading, Affiliate and Tax each had
    # functions with no delegate at all. Listed explicitly rather than derived,
    # so adding an endpoint without a delegate fails here.
    @delegates [
      {:get_copy_trading_positions_by_order, 1},
      {:get_copy_trading_positions_by_contract, 1},
      {:get_copy_trading_position_mode, 1},
      {:set_copy_trading_position_mode, 2},
      {:get_copy_trading_leverage, 1},
      {:set_copy_trading_leverage, 2},
      {:cancel_copy_trading_order, 2},
      {:place_copy_trading_tpsl_by_contract, 2},
      {:get_invitees, 1},
      {:get_sub_invitees, 1},
      {:get_sub_affiliates, 1},
      {:get_commission, 1},
      {:get_tax_funds_transfer_history, 1},
      {:get_position_tiers, 1},
      {:get_positions_history, 1},
      {:get_currencies, 1}
    ]

    for {fun, arity} <- @delegates do
      test "ExBlofin.#{fun}/#{arity} is exposed" do
        assert function_exported?(ExBlofin, unquote(fun), unquote(arity))
      end
    end
  end

  defp decode_body(conn) do
    {:ok, body, _conn} = Plug.Conn.read_body(conn)
    Jason.decode!(body)
  end
end
