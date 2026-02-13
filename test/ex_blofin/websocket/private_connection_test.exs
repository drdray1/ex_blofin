defmodule ExBlofin.WebSocket.PrivateConnectionTest do
  use ExUnit.Case, async: true

  alias ExBlofin.WebSocket.PrivateConnection

  @creds [api_key: "test-key", secret_key: "test-secret", passphrase: "test-pass"]

  describe "start_link/1" do
    test "starts with required credentials" do
      {:ok, pid} = PrivateConnection.start_link(@creds)
      assert Process.alive?(pid)
      assert PrivateConnection.get_status(pid) == :disconnected
      PrivateConnection.stop(pid)
    end

    test "starts with demo option" do
      {:ok, pid} = PrivateConnection.start_link(@creds ++ [demo: true])
      assert Process.alive?(pid)
      PrivateConnection.stop(pid)
    end

    test "raises on missing api_key" do
      assert_raise KeyError, fn ->
        PrivateConnection.start_link(secret_key: "s", passphrase: "p")
      end
    end
  end

  describe "get_info/1" do
    test "returns initial info" do
      {:ok, pid} = PrivateConnection.start_link(@creds)

      info = PrivateConnection.get_info(pid)
      assert info.status == :disconnected
      assert info.subscriptions == []
      assert info.subscriber_count == 0

      PrivateConnection.stop(pid)
    end
  end

  describe "subscriber management" do
    test "add and remove subscribers" do
      {:ok, pid} = PrivateConnection.start_link(@creds)

      PrivateConnection.add_subscriber(pid, self())
      Process.sleep(10)
      assert PrivateConnection.get_info(pid).subscriber_count == 1

      PrivateConnection.remove_subscriber(pid, self())
      Process.sleep(10)
      assert PrivateConnection.get_info(pid).subscriber_count == 0

      PrivateConnection.stop(pid)
    end
  end

  describe "login handling via direct messages" do
    test "transitions to connected on successful login" do
      {:ok, pid} = PrivateConnection.start_link(@creds)
      Process.sleep(10)

      test_pid = self()

      :sys.replace_state(pid, fn state ->
        %{state | websocket_pid: test_pid, status: :authenticating}
      end)

      login_success = Jason.encode!(%{"event" => "login", "code" => "0", "msg" => ""})
      send(pid, {:stream_message, test_pid, login_success})
      Process.sleep(50)

      assert PrivateConnection.get_status(pid) == :connected
      PrivateConnection.stop(pid)
    end

    test "handles login failure" do
      {:ok, pid} = PrivateConnection.start_link(@creds)
      Process.sleep(10)

      test_pid = self()

      :sys.replace_state(pid, fn state ->
        %{state | websocket_pid: test_pid, status: :authenticating}
      end)

      login_fail =
        Jason.encode!(%{"event" => "login", "code" => "60009", "msg" => "Login failed"})

      send(pid, {:stream_message, test_pid, login_fail})
      Process.sleep(50)

      # After login failure, should disconnect and schedule reconnect
      status = PrivateConnection.get_status(pid)
      assert status in [:disconnected, :reconnecting]
      PrivateConnection.stop(pid)
    end
  end

  describe "event broadcasting" do
    test "broadcasts order events to subscribers" do
      {:ok, pid} = PrivateConnection.start_link(@creds)
      PrivateConnection.add_subscriber(pid, self())
      Process.sleep(10)

      test_pid = self()

      :sys.replace_state(pid, fn state ->
        %{state | websocket_pid: test_pid, status: :connected}
      end)

      order_raw =
        Jason.encode!(%{
          "arg" => %{"channel" => "orders"},
          "data" => [
            %{
              "orderId" => "28150801",
              "instId" => "BTC-USDT",
              "side" => "buy",
              "orderType" => "limit",
              "price" => "49000.0",
              "size" => "10",
              "state" => "filled",
              "fillPrice" => "49000.0",
              "fillSize" => "10",
              "ts" => "1697021343571"
            }
          ]
        })

      send(pid, {:stream_message, test_pid, order_raw})
      assert_receive {:blofin_event, :orders, [order]}, 1000
      assert order.order_id == "28150801"
      assert order.state == "filled"

      PrivateConnection.stop(pid)
    end

    test "broadcasts position events to subscribers" do
      {:ok, pid} = PrivateConnection.start_link(@creds)
      PrivateConnection.add_subscriber(pid, self())
      Process.sleep(10)

      test_pid = self()

      :sys.replace_state(pid, fn state ->
        %{state | websocket_pid: test_pid, status: :connected}
      end)

      pos_raw =
        Jason.encode!(%{
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
        })

      send(pid, {:stream_message, test_pid, pos_raw})
      assert_receive {:blofin_event, :positions, [position]}, 1000
      assert position.inst_id == "BTC-USDT"
      assert position.positions == "100"

      PrivateConnection.stop(pid)
    end
  end

  describe "subscription tracking" do
    test "tracks subscriptions" do
      {:ok, pid} = PrivateConnection.start_link(@creds)

      channels = [%{"channel" => "orders"}, %{"channel" => "positions"}]
      PrivateConnection.subscribe(pid, channels)

      info = PrivateConnection.get_info(pid)
      assert length(info.subscriptions) == 2

      PrivateConnection.stop(pid)
    end
  end
end
