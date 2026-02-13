defmodule ExBlofin.WebSocket.CopyTradingConnectionTest do
  use ExUnit.Case, async: true

  alias ExBlofin.WebSocket.CopyTradingConnection

  @creds [api_key: "test-key", secret_key: "test-secret", passphrase: "test-pass"]

  describe "start_link/1" do
    test "starts with required credentials" do
      {:ok, pid} = CopyTradingConnection.start_link(@creds)
      assert Process.alive?(pid)
      assert CopyTradingConnection.get_status(pid) == :disconnected
      CopyTradingConnection.stop(pid)
    end
  end

  describe "get_info/1" do
    test "returns initial info" do
      {:ok, pid} = CopyTradingConnection.start_link(@creds)

      info = CopyTradingConnection.get_info(pid)
      assert info.status == :disconnected
      assert info.subscriptions == []
      assert info.subscriber_count == 0

      CopyTradingConnection.stop(pid)
    end
  end

  describe "subscriber management" do
    test "add and remove subscribers" do
      {:ok, pid} = CopyTradingConnection.start_link(@creds)

      CopyTradingConnection.add_subscriber(pid, self())
      Process.sleep(10)
      assert CopyTradingConnection.get_info(pid).subscriber_count == 1

      CopyTradingConnection.remove_subscriber(pid, self())
      Process.sleep(10)
      assert CopyTradingConnection.get_info(pid).subscriber_count == 0

      CopyTradingConnection.stop(pid)
    end
  end

  describe "login handling" do
    test "transitions to connected on successful login" do
      {:ok, pid} = CopyTradingConnection.start_link(@creds)
      Process.sleep(10)

      test_pid = self()

      :sys.replace_state(pid, fn state ->
        %{state | websocket_pid: test_pid, status: :authenticating}
      end)

      login_success = Jason.encode!(%{"event" => "login", "code" => "0", "msg" => ""})
      send(pid, {:stream_message, test_pid, login_success})
      Process.sleep(50)

      assert CopyTradingConnection.get_status(pid) == :connected
      CopyTradingConnection.stop(pid)
    end
  end

  describe "event broadcasting" do
    test "broadcasts copy trading order events" do
      {:ok, pid} = CopyTradingConnection.start_link(@creds)
      CopyTradingConnection.add_subscriber(pid, self())
      Process.sleep(10)

      test_pid = self()

      :sys.replace_state(pid, fn state ->
        %{state | websocket_pid: test_pid, status: :connected}
      end)

      order_raw =
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

      send(pid, {:stream_message, test_pid, order_raw})
      assert_receive {:blofin_event, :copytrading_orders, [order]}, 1000
      assert order.order_id == "ct-123"
      assert order.state == "filled"

      CopyTradingConnection.stop(pid)
    end

    test "broadcasts copy trading account events" do
      {:ok, pid} = CopyTradingConnection.start_link(@creds)
      CopyTradingConnection.add_subscriber(pid, self())
      Process.sleep(10)

      test_pid = self()

      :sys.replace_state(pid, fn state ->
        %{state | websocket_pid: test_pid, status: :connected}
      end)

      account_raw =
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

      send(pid, {:stream_message, test_pid, account_raw})
      assert_receive {:blofin_event, :copytrading_account, [account]}, 1000
      assert account.total_equity == "10000.0"

      CopyTradingConnection.stop(pid)
    end
  end

  describe "subscription tracking" do
    test "tracks subscriptions" do
      {:ok, pid} = CopyTradingConnection.start_link(@creds)

      channels = [%{"channel" => "copytrading-orders"}, %{"channel" => "copytrading-account"}]
      CopyTradingConnection.subscribe(pid, channels)

      info = CopyTradingConnection.get_info(pid)
      assert length(info.subscriptions) == 2

      CopyTradingConnection.stop(pid)
    end
  end
end
