defmodule ExBlofin.WebSocket.PublicConnectionTest do
  use ExUnit.Case, async: true

  alias ExBlofin.WebSocket.PublicConnection

  describe "start_link/1" do
    test "starts with default options" do
      {:ok, pid} = PublicConnection.start_link()
      assert Process.alive?(pid)
      assert PublicConnection.get_status(pid) == :disconnected
      PublicConnection.stop(pid)
    end

    test "starts with demo option" do
      {:ok, pid} = PublicConnection.start_link(demo: true)
      assert Process.alive?(pid)
      PublicConnection.stop(pid)
    end
  end

  describe "get_info/1" do
    test "returns initial info" do
      {:ok, pid} = PublicConnection.start_link()

      info = PublicConnection.get_info(pid)
      assert info.status == :disconnected
      assert info.subscriptions == []
      assert info.subscriber_count == 0

      PublicConnection.stop(pid)
    end
  end

  describe "subscriber management" do
    test "add_subscriber tracks subscribers" do
      {:ok, pid} = PublicConnection.start_link()

      PublicConnection.add_subscriber(pid, self())
      Process.sleep(10)

      info = PublicConnection.get_info(pid)
      assert info.subscriber_count == 1

      PublicConnection.stop(pid)
    end

    test "remove_subscriber removes tracked subscribers" do
      {:ok, pid} = PublicConnection.start_link()

      PublicConnection.add_subscriber(pid, self())
      Process.sleep(10)
      assert PublicConnection.get_info(pid).subscriber_count == 1

      PublicConnection.remove_subscriber(pid, self())
      Process.sleep(10)
      assert PublicConnection.get_info(pid).subscriber_count == 0

      PublicConnection.stop(pid)
    end

    test "subscriber removed on process exit" do
      {:ok, pid} = PublicConnection.start_link()

      subscriber = spawn(fn -> Process.sleep(:infinity) end)
      PublicConnection.add_subscriber(pid, subscriber)
      Process.sleep(10)
      assert PublicConnection.get_info(pid).subscriber_count == 1

      Process.exit(subscriber, :kill)
      Process.sleep(50)
      assert PublicConnection.get_info(pid).subscriber_count == 0

      PublicConnection.stop(pid)
    end
  end

  describe "event broadcasting via direct messages" do
    test "broadcasts parsed trade events to subscribers" do
      {:ok, pid} = PublicConnection.start_link()
      PublicConnection.add_subscriber(pid, self())
      Process.sleep(10)

      trade_raw =
        Jason.encode!(%{
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
        })

      # Capture test pid and use it as the fake websocket_pid
      test_pid = self()

      :sys.replace_state(pid, fn state ->
        %{state | websocket_pid: test_pid, status: :connected}
      end)

      send(pid, {:stream_message, test_pid, trade_raw})

      assert_receive {:blofin_event, :trades, [trade]}, 1000
      assert trade.inst_id == "BTC-USDT"
      assert trade.price == "50000.0"

      PublicConnection.stop(pid)
    end

    test "handles pong messages without broadcasting" do
      {:ok, pid} = PublicConnection.start_link()
      PublicConnection.add_subscriber(pid, self())
      Process.sleep(10)

      test_pid = self()

      :sys.replace_state(pid, fn state ->
        %{state | websocket_pid: test_pid, status: :connected}
      end)

      send(pid, {:stream_message, test_pid, "pong"})
      refute_receive {:blofin_event, _, _}, 100

      PublicConnection.stop(pid)
    end
  end

  describe "subscription tracking" do
    test "tracks subscriptions via subscribe call" do
      {:ok, pid} = PublicConnection.start_link()

      # Subscribe won't actually connect (no real WS), but will track subscriptions
      # The connect attempt will fail silently since there's no real WS server
      channels = [%{"channel" => "trades", "instId" => "BTC-USDT"}]
      PublicConnection.subscribe(pid, channels)

      info = PublicConnection.get_info(pid)
      assert info.subscriptions == channels

      PublicConnection.stop(pid)
    end

    test "unsubscribe removes tracked channels" do
      {:ok, pid} = PublicConnection.start_link()

      channels = [%{"channel" => "trades", "instId" => "BTC-USDT"}]
      PublicConnection.subscribe(pid, channels)
      PublicConnection.unsubscribe(pid, channels)

      info = PublicConnection.get_info(pid)
      assert info.subscriptions == []

      PublicConnection.stop(pid)
    end
  end
end
