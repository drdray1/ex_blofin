defmodule ExBlofin.TaxTest do
  use ExUnit.Case, async: true

  alias ExBlofin.{Fixtures, Tax}

  @stub :tax_stub

  describe "get_deposit_history/2" do
    test "returns deposit history" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/tax/deposit-history"
        Req.Test.json(conn, Fixtures.sample_tax_deposit_history_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, [%{"depositId" => _}]} = Tax.get_deposit_history(client)
    end
  end

  describe "get_withdraw_history/2" do
    test "returns withdrawal history" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/tax/withdraw-history"
        Req.Test.json(conn, Fixtures.success_response([]))
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, []} = Tax.get_withdraw_history(client)
    end
  end

  describe "get_funds_transfer_history/2" do
    test "returns transfer history" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/tax/funds-transfer-history"
        Req.Test.json(conn, Fixtures.success_response([]))
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, []} = Tax.get_funds_transfer_history(client)
    end
  end

  describe "get_futures_trade_history/2" do
    test "returns futures trade history" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/tax/futures-trade-history"
        Req.Test.json(conn, Fixtures.sample_tax_futures_trade_history_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, [%{"tradeId" => _}]} = Tax.get_futures_trade_history(client)
    end
  end

  describe "get_spot_trade_history/2" do
    test "returns spot trade history" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/tax/spot-trade-history"
        Req.Test.json(conn, Fixtures.success_response([]))
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, []} = Tax.get_spot_trade_history(client)
    end
  end
end
