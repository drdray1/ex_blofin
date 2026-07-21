defmodule ExBlofin.AssetTest do
  use ExUnit.Case, async: true

  alias ExBlofin.{Asset, Fixtures}

  @stub :asset_stub

  describe "get_balances/2" do
    test "returns asset balances" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/asset/balances"
        Req.Test.json(conn, Fixtures.sample_asset_balances_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, balances} = Asset.get_balances(client)
      assert length(balances) == 2
      assert hd(balances)["currency"] == "USDT"
    end
  end

  describe "transfer/2" do
    test "transfers funds" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/asset/transfer"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.sample_transfer_response())
      end)

      client = Fixtures.test_client(@stub)
      params = %{"currency" => "USDT", "amount" => "100", "from" => "funding", "to" => "trading"}
      assert {:ok, [%{"transferId" => _}]} = Asset.transfer(client, params)
    end
  end

  describe "get_bills/2" do
    test "returns bill history" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/asset/bills"
        Req.Test.json(conn, Fixtures.sample_bills_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, [%{"billId" => _}]} = Asset.get_bills(client)
    end
  end

  describe "get_withdrawal_history/2" do
    test "returns withdrawal history" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/asset/withdrawal-history"
        Req.Test.json(conn, Fixtures.success_response([]))
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, []} = Asset.get_withdrawal_history(client)
    end
  end

  describe "get_deposit_history/2" do
    test "returns deposit history" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/asset/deposit-history"
        Req.Test.json(conn, Fixtures.success_response([]))
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, []} = Asset.get_deposit_history(client)
    end
  end

  describe "get_currencies/2" do
    test "returns currency info" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/asset/currencies"
        Req.Test.json(conn, Fixtures.sample_currencies_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, currencies} = Asset.get_currencies(client)
      assert [%{"currency" => "USDT", "chain" => "TRC20"} | _] = currencies
    end

    test "filters by currency" do
      Req.Test.expect(@stub, fn conn ->
        query = URI.decode_query(conn.query_string)
        assert query["currency"] == "USDT"
        Req.Test.json(conn, Fixtures.sample_currencies_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, _} = Asset.get_currencies(client, currency: "USDT")
    end
  end

  describe "apply_demo_money/1" do
    test "requests demo funds" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/asset/demo-apply-money"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.success_response([]))
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, _} = Asset.apply_demo_money(client)
    end
  end
end
