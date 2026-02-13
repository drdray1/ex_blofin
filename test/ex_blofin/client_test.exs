defmodule ExBlofin.ClientTest do
  use ExUnit.Case, async: true

  alias ExBlofin.{Client, Fixtures}

  describe "new/4" do
    test "creates a Req.Request struct" do
      client = Client.new("key", "secret", "pass")
      assert %Req.Request{} = client
    end

    test "sets production base URL by default" do
      client = Client.new("key", "secret", "pass")
      assert client.options.base_url == "https://openapi.blofin.com"
    end

    test "sets demo base URL when demo: true" do
      client = Client.new("key", "secret", "pass", demo: true)
      assert client.options.base_url == "https://demo-trading-openapi.blofin.com"
    end

    test "accepts nil credentials for public-only usage" do
      client = Client.new(nil, nil, nil)
      assert %Req.Request{} = client
    end

    test "accepts plug option for testing" do
      client = Client.new("key", "secret", "pass", plug: {Req.Test, :test_stub})
      assert %Req.Request{} = client
    end
  end

  describe "base_url/1" do
    test "returns production URL by default" do
      assert Client.base_url() == "https://openapi.blofin.com"
      assert Client.base_url(false) == "https://openapi.blofin.com"
    end

    test "returns demo URL when demo is true" do
      assert Client.base_url(true) == "https://demo-trading-openapi.blofin.com"
    end
  end

  describe "ws_public_url/1" do
    test "returns production public WS URL by default" do
      assert Client.ws_public_url() == "wss://openapi.blofin.com/ws/public"
    end

    test "returns demo public WS URL" do
      assert Client.ws_public_url(true) == "wss://demo-trading-openapi.blofin.com/ws/public"
    end
  end

  describe "ws_private_url/1" do
    test "returns production private WS URL by default" do
      assert Client.ws_private_url() == "wss://openapi.blofin.com/ws/private"
    end

    test "returns demo private WS URL" do
      assert Client.ws_private_url(true) == "wss://demo-trading-openapi.blofin.com/ws/private"
    end
  end

  describe "ws_copy_trading_url/0" do
    test "returns copy trading WS URL" do
      assert Client.ws_copy_trading_url() ==
               "wss://openapi.blofin.com/ws/copytrading/private"
    end
  end

  describe "handle_response/1" do
    test "unwraps successful BloFin response" do
      response =
        {:ok,
         %Req.Response{status: 200, body: Fixtures.success_response([%{"instId" => "BTC-USDT"}])}}

      assert {:ok, [%{"instId" => "BTC-USDT"}]} = Client.handle_response(response)
    end

    test "returns error for BloFin error code" do
      response =
        {:ok, %Req.Response{status: 200, body: Fixtures.error_response("1000", "Cancel failed")}}

      assert {:error, {:api_error, "1000", "Cancel failed"}} = Client.handle_response(response)
    end

    test "handles success with no data key" do
      response = {:ok, %Req.Response{status: 200, body: %{"code" => "0", "msg" => ""}}}
      assert {:ok, %{"code" => "0", "msg" => ""}} = Client.handle_response(response)
    end

    test "handles non-BloFin response body" do
      response = {:ok, %Req.Response{status: 200, body: %{"some" => "data"}}}
      assert {:ok, %{"some" => "data"}} = Client.handle_response(response)
    end

    test "returns :unauthorized for 401" do
      response = {:ok, %Req.Response{status: 401, body: ""}}
      assert {:error, :unauthorized} = Client.handle_response(response)
    end

    test "returns :forbidden for 403" do
      response = {:ok, %Req.Response{status: 403, body: ""}}
      assert {:error, :forbidden} = Client.handle_response(response)
    end

    test "returns :not_found for 404" do
      response = {:ok, %Req.Response{status: 404, body: ""}}
      assert {:error, :not_found} = Client.handle_response(response)
    end

    test "returns :rate_limited for 429" do
      response = {:ok, %Req.Response{status: 429, body: ""}}
      assert {:error, :rate_limited} = Client.handle_response(response)
    end

    test "returns api_error for other 4xx/5xx" do
      response = {:ok, %Req.Response{status: 500, body: %{"msg" => "Internal error"}}}
      assert {:error, {:api_error, 500, "Internal error"}} = Client.handle_response(response)
    end

    test "returns connection_error for network errors" do
      response = {:error, %Req.TransportError{reason: :timeout}}

      assert {:error, {:connection_error, %Req.TransportError{reason: :timeout}}} =
               Client.handle_response(response)
    end

    test "extracts error message from msg field" do
      response = {:ok, %Req.Response{status: 500, body: %{"msg" => "Server error"}}}
      assert {:error, {:api_error, 500, "Server error"}} = Client.handle_response(response)
    end

    test "returns Unknown error when no message extractable" do
      response = {:ok, %Req.Response{status: 500, body: %{}}}
      assert {:error, {:api_error, 500, "Unknown error"}} = Client.handle_response(response)
    end
  end

  describe "test_client/1 fixture" do
    test "creates a working test client" do
      client = Fixtures.test_client(:my_stub)
      assert %Req.Request{} = client
    end
  end
end
