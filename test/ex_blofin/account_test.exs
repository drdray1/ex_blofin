defmodule ExBlofin.AccountTest do
  use ExUnit.Case, async: true

  alias ExBlofin.{Account, Fixtures}

  @stub :account_stub

  describe "get_balance/2" do
    test "returns account balance" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/account/balance"
        Req.Test.json(conn, Fixtures.sample_account_balance_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, [balance]} = Account.get_balance(client)
      assert balance["totalEquity"]
      assert is_list(balance["details"])
    end
  end

  describe "get_positions/2" do
    test "returns positions" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/account/positions"
        Req.Test.json(conn, Fixtures.sample_positions_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, [position]} = Account.get_positions(client)
      assert position["instId"] == "BTC-USDT"
      assert position["positionSide"] == "long"
    end

    test "filters by instId" do
      Req.Test.expect(@stub, fn conn ->
        query = URI.decode_query(conn.query_string)
        assert query["instId"] == "BTC-USDT"
        Req.Test.json(conn, Fixtures.sample_positions_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, _} = Account.get_positions(client, instId: "BTC-USDT")
    end
  end

  describe "get_margin_mode/2" do
    test "returns margin mode" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/account/margin-mode"
        Req.Test.json(conn, Fixtures.sample_margin_mode_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, [%{"marginMode" => "cross"}]} = Account.get_margin_mode(client)
    end
  end

  describe "set_margin_mode/2" do
    test "sets margin mode" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/account/set-margin-mode"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.sample_margin_mode_response())
      end)

      client = Fixtures.test_client(@stub)
      params = %{"instId" => "BTC-USDT", "marginMode" => "isolated"}
      assert {:ok, _} = Account.set_margin_mode(client, params)
    end
  end

  describe "set_position_mode/2" do
    test "sets position mode" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/account/set-position-mode"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.success_response([%{"positionMode" => "long_short_mode"}]))
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, _} = Account.set_position_mode(client, %{"positionMode" => "long_short_mode"})
    end
  end

  describe "get_batch_leverage_info/2" do
    test "returns leverage info" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/account/batch-leverage-info"
        Req.Test.json(conn, Fixtures.sample_leverage_info_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, [%{"lever" => "10"}]} = Account.get_batch_leverage_info(client)
    end
  end

  describe "set_leverage/2" do
    test "sets leverage" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/account/set-leverage"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.sample_leverage_info_response())
      end)

      client = Fixtures.test_client(@stub)
      params = %{"instId" => "BTC-USDT", "lever" => "20", "marginMode" => "cross"}
      assert {:ok, _} = Account.set_leverage(client, params)
    end
  end

  describe "get_config/1" do
    test "returns account config" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/account/config"
        Req.Test.json(conn, Fixtures.sample_account_config_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, [%{"positionMode" => "net_mode"}]} = Account.get_config(client)
    end
  end
end
