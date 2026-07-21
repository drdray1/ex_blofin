defmodule ExBlofin.ClientInternalsTest do
  @moduledoc """
  Covers the `ExBlofin.Client` surface that the per-endpoint tests don't reach:
  the health check, error normalisation, and URL helpers.
  """
  use ExUnit.Case, async: true

  alias ExBlofin.{Client, Fixtures}

  @stub :client_internals_stub

  defp json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  defp stub(fun) do
    Req.Test.stub(@stub, fun)
    Fixtures.test_client(@stub)
  end

  describe "healthcheck/1" do
    test "returns :ok when the config endpoint answers with code 0" do
      client =
        stub(fn conn ->
          assert conn.request_path == "/api/v1/account/config"
          json(conn, 200, %{"code" => "0", "data" => []})
        end)

      assert Client.healthcheck(client) == :ok
    end

    test "maps 401 to :unauthorized" do
      client = stub(fn conn -> json(conn, 401, %{"code" => "401", "msg" => "Unauthorized"}) end)
      assert Client.healthcheck(client) == {:error, :unauthorized}
    end

    test "maps 403 to :forbidden" do
      client = stub(fn conn -> json(conn, 403, %{"code" => "403", "msg" => "Forbidden"}) end)
      assert Client.healthcheck(client) == {:error, :forbidden}
    end

    test "reports any other status as unexpected" do
      client = stub(fn conn -> json(conn, 503, %{"msg" => "Unavailable"}) end)
      assert Client.healthcheck(client) == {:error, {:unexpected_status, 503}}
    end

    test "a 200 carrying a non-zero code is not healthy" do
      client = stub(fn conn -> json(conn, 200, %{"code" => "152001", "msg" => "nope"}) end)
      assert {:error, {:unexpected_status, 200}} = Client.healthcheck(client)
    end

    test "surfaces transport failures" do
      client = stub(fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      # healthcheck/1 passes the reason through unwrapped, unlike
      # handle_response/1 which tags it as {:connection_error, reason}.
      assert {:error, %Req.TransportError{reason: :econnrefused}} = Client.healthcheck(client)
    end
  end

  describe "handle_response/1 error normalisation" do
    test "maps documented statuses to atoms" do
      assert Client.handle_response({:ok, %Req.Response{status: 401, body: %{}}}) ==
               {:error, :unauthorized}

      assert Client.handle_response({:ok, %Req.Response{status: 403, body: %{}}}) ==
               {:error, :forbidden}

      assert Client.handle_response({:ok, %Req.Response{status: 404, body: %{}}}) ==
               {:error, :not_found}

      assert Client.handle_response({:ok, %Req.Response{status: 429, body: %{}}}) ==
               {:error, :rate_limited}
    end

    test "extracts an error message from each known envelope shape" do
      for {body, expected} <- [
            {%{"msg" => "from msg"}, "from msg"},
            {%{"message" => "from message"}, "from message"},
            {%{"error" => "from error"}, "from error"},
            {%{"unrecognised" => true}, "Unknown error"},
            {"not a map", "Unknown error"},
            # An empty msg must fall through rather than yielding "".
            {%{"msg" => ""}, "Unknown error"}
          ] do
        assert {:error, {:api_error, 500, ^expected}} =
                 Client.handle_response({:ok, %Req.Response{status: 500, body: body}})
      end
    end

    test "unwraps a success envelope and passes through unenveloped bodies" do
      assert Client.handle_response(
               {:ok, %Req.Response{status: 200, body: %{"code" => "0", "data" => [1, 2]}}}
             ) == {:ok, [1, 2]}

      assert Client.handle_response({:ok, %Req.Response{status: 200, body: %{"code" => "0"}}}) ==
               {:ok, %{"code" => "0"}}

      assert Client.handle_response({:ok, %Req.Response{status: 200, body: "plain"}}) ==
               {:ok, "plain"}
    end

    test "reports a non-zero code from a 2xx as an api_error" do
      assert Client.handle_response(
               {:ok, %Req.Response{status: 200, body: %{"code" => "152001", "msg" => "bad"}}}
             ) == {:error, {:api_error, "152001", "bad"}}
    end

    test "wraps transport errors" do
      assert Client.handle_response({:error, :timeout}) == {:error, {:connection_error, :timeout}}
    end
  end

  describe "URL helpers" do
    test "base_url/1 switches on the demo flag" do
      assert Client.base_url() == "https://openapi.blofin.com"
      assert Client.base_url(false) == "https://openapi.blofin.com"
      assert Client.base_url(true) == "https://demo-trading-openapi.blofin.com"
    end

    test "websocket URLs switch on the demo flag" do
      assert Client.ws_public_url() == "wss://openapi.blofin.com/ws/public"
      assert Client.ws_public_url(true) =~ "demo-trading-openapi"
      assert Client.ws_private_url() == "wss://openapi.blofin.com/ws/private"
      assert Client.ws_private_url(true) =~ "demo-trading-openapi"
      assert Client.ws_copy_trading_url() == "wss://openapi.blofin.com/ws/copytrading/private"
    end
  end

  describe "init_path_cache/0" do
    test "is idempotent" do
      assert Client.init_path_cache() == :ok
      assert Client.init_path_cache() == :ok
    end
  end
end
