defmodule ExBlofin.CopyTradingTest do
  use ExUnit.Case, async: true

  alias ExBlofin.{CopyTrading, Fixtures}

  @stub :copy_trading_stub

  describe "get_instruments/2" do
    test "returns instruments" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/copytrading/instruments"
        Req.Test.json(conn, Fixtures.sample_instruments_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, _} = CopyTrading.get_instruments(client)
    end
  end

  describe "get_account_config/1" do
    test "returns account config" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/copytrading/account-config"
        Req.Test.json(conn, Fixtures.sample_account_config_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, _} = CopyTrading.get_account_config(client)
    end
  end

  describe "get_balance/2" do
    test "returns balance" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/copytrading/balance"
        Req.Test.json(conn, Fixtures.sample_copy_trading_balance_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, [%{"totalEquity" => _}]} = CopyTrading.get_balance(client)
    end
  end

  describe "get_positions_by_contract/2" do
    test "returns positions" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/copytrading/positions-by-contract"
        Req.Test.json(conn, Fixtures.sample_copy_trading_positions_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, _} = CopyTrading.get_positions_by_contract(client)
    end
  end

  describe "place_order/2" do
    test "places a copy trading order" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/copytrading/order"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.sample_place_order_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, _} = CopyTrading.place_order(client, %{"instId" => "BTC-USDT"})
    end
  end

  describe "close_position/2" do
    test "closes a position" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/copytrading/close-position"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.sample_close_position_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, _} = CopyTrading.close_position(client, %{"instId" => "BTC-USDT"})
    end
  end
end
