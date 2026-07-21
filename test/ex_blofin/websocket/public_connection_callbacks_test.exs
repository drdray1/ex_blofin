defmodule ExBlofin.WebSocket.PublicConnectionCallbacksTest do
  @moduledoc """
  Drives `ExBlofin.WebSocket.PublicConnection`'s GenServer callbacks directly.

  The existing connection test covers the process lifecycle; these cover the
  message-handling branches that only run once a socket is live — event
  dispatch, ping scheduling, disconnect handling and subscriber cleanup — none
  of which are reachable without a real server through the public API.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias ExBlofin.WebSocket.PublicConnection
  alias ExBlofin.WebSocket.PublicConnection.State

  # `websocket_pid` is matched against the incoming message's pid, so callbacks
  # are driven with a stand-in socket rather than the test process: WebSockex
  # raises CallingSelfError if a process sends a frame to itself.
  defp state(overrides \\ []) do
    base = %State{
      websocket_pid: fake_socket(),
      demo: false,
      status: :connected,
      reconnect_attempts: 0,
      subscriptions: [],
      subscribers: MapSet.new()
    }

    struct!(base, overrides)
  end

  # Speaks just enough of the `:gen.call` protocol that WebSockex.send_frame/2
  # completes, and forwards whatever was sent back to the test for assertions.
  defp fake_socket do
    test = self()
    spawn_link(fn -> fake_socket_loop(test) end)
  end

  defp fake_socket_loop(test) do
    receive do
      {:"$websockex_send", {from, ref}, frame} ->
        send(test, {:frame_sent, frame})
        send(from, {ref, :ok})
        fake_socket_loop(test)

      _other ->
        fake_socket_loop(test)
    end
  end

  defp cleanup(%{ping_timer: t}) when is_reference(t), do: Process.cancel_timer(t)
  defp cleanup(_), do: :ok

  describe "handle_info/2 :stream_connected" do
    test "marks connected, resets attempts and schedules a ping" do
      st = state(status: :connecting, reconnect_attempts: 3)

      capture_log(fn ->
        assert {:noreply, new_state} =
                 PublicConnection.handle_info({:stream_connected, st.websocket_pid}, st)

        assert new_state.status == :connected
        assert new_state.reconnect_attempts == 0
        assert is_reference(new_state.ping_timer)
        cleanup(new_state)
      end)
    end

    test "re-sends existing subscriptions on reconnect" do
      subs = [%{"channel" => "trades", "instId" => "BTC-USDT"}]
      st = state(status: :connecting, subscriptions: subs)

      capture_log(fn ->
        assert {:noreply, new_state} =
                 PublicConnection.handle_info({:stream_connected, st.websocket_pid}, st)

        assert new_state.subscriptions == subs
        cleanup(new_state)
      end)

      assert_receive {:frame_sent, {:text, json}}
      assert %{"op" => "subscribe", "args" => ^subs} = Jason.decode!(json)
    end
  end

  describe "handle_info/2 :stream_message" do
    test "broadcasts a data event to every subscriber" do
      parent = self()

      sub =
        spawn(fn ->
          receive do
            {:blofin_event, channel, events} -> send(parent, {:got, channel, events})
          end
        end)

      raw =
        ~s({"arg":{"channel":"trades","instId":"BTC-USDT"},) <>
          ~s("data":[{"instId":"BTC-USDT","tradeId":"1","price":"50000",) <>
          ~s("size":"1","side":"buy","ts":"1697021343571"}]})

      st = state(subscribers: MapSet.new([sub]))

      capture_log(fn ->
        assert {:noreply, _state} =
                 PublicConnection.handle_info({:stream_message, st.websocket_pid, raw}, st)
      end)

      assert_receive {:got, :trades, [_event]}
    end

    test "handles pong, subscribe, unsubscribe and error frames without broadcasting" do
      parent = self()
      sub = spawn(fn -> receive do: (msg -> send(parent, {:unexpected, msg})) end)
      st = state(subscribers: MapSet.new([sub]))

      frames = [
        "pong",
        ~s({"event":"subscribe","arg":{"channel":"trades"}}),
        ~s({"event":"unsubscribe","arg":{"channel":"trades"}}),
        ~s({"event":"error","code":"60012","msg":"Invalid request"})
      ]

      log =
        capture_log(fn ->
          for frame <- frames do
            assert {:noreply, _} =
                     PublicConnection.handle_info({:stream_message, st.websocket_pid, frame}, st)
          end
        end)

      assert log =~ "Pong received"
      assert log =~ "Subscribed"
      assert log =~ "Unsubscribed"
      assert log =~ "60012 - Invalid request"
      refute_receive {:unexpected, _}, 50
    end

    test "logs and ignores an unparseable frame" do
      st = state()

      log =
        capture_log(fn ->
          assert {:noreply, _} =
                   PublicConnection.handle_info(
                     {:stream_message, st.websocket_pid, "garbage"},
                     st
                   )
        end)

      assert log =~ "Parse error"
    end
  end

  describe "handle_info/2 :stream_disconnected" do
    test "moves to reconnecting and clears the ping timer" do
      timer = Process.send_after(self(), :send_ping, 60_000)
      st = state(ping_timer: timer)

      log =
        capture_log(fn ->
          assert {:noreply, new_state} =
                   PublicConnection.handle_info(
                     {:stream_disconnected, st.websocket_pid, {:remote, :closed}},
                     st
                   )

          assert new_state.status == :reconnecting
          assert new_state.ping_timer == nil
        end)

      assert log =~ "Disconnected"
    end
  end

  describe "handle_info/2 :send_ping" do
    test "reschedules while connected" do
      assert {:noreply, new_state} = PublicConnection.handle_info(:send_ping, state())
      assert is_reference(new_state.ping_timer)
      cleanup(new_state)
    end

    test "does not reschedule when disconnected" do
      assert {:noreply, new_state} =
               PublicConnection.handle_info(:send_ping, state(status: :disconnected))

      assert new_state.ping_timer == nil
    end

    test "does not reschedule when there is no socket" do
      assert {:noreply, new_state} =
               PublicConnection.handle_info(:send_ping, state(websocket_pid: nil))

      assert new_state.ping_timer == nil
    end
  end

  describe "handle_info/2 :DOWN" do
    test "drops a subscriber that died" do
      dead = spawn(fn -> :ok end)
      alive = self()

      assert {:noreply, new_state} =
               PublicConnection.handle_info(
                 {:DOWN, make_ref(), :process, dead, :normal},
                 state(subscribers: MapSet.new([dead, alive]))
               )

      refute MapSet.member?(new_state.subscribers, dead)
      assert MapSet.member?(new_state.subscribers, alive)
    end
  end

  describe "handle_info/2 catch-all" do
    test "ignores unrelated messages" do
      st = state()
      assert {:noreply, ^st} = PublicConnection.handle_info(:something_unrelated, st)
    end

    test "ignores stream messages from a stale socket pid" do
      # A late frame from a previous connection must not be processed.
      other = spawn(fn -> :ok end)
      st = state()

      assert {:noreply, ^st} =
               PublicConnection.handle_info({:stream_message, other, "pong"}, st)
    end
  end

  describe "handle_call/3" do
    test ":get_status and :get_info report state" do
      st = state(subscriptions: [%{"channel" => "trades"}], subscribers: MapSet.new([self()]))

      assert {:reply, :connected, ^st} = PublicConnection.handle_call(:get_status, self(), st)

      assert {:reply, info, ^st} = PublicConnection.handle_call(:get_info, self(), st)
      assert info.status == :connected
      assert info.subscriptions == [%{"channel" => "trades"}]
      assert info.subscriber_count == 1
    end
  end

  describe "handle_call/3 subscribe and unsubscribe" do
    test "subscribing while connected sends the frame and records the channels" do
      channels = [%{"channel" => "trades", "instId" => "BTC-USDT"}]
      st = state()

      assert {:reply, :ok, new_state} =
               PublicConnection.handle_call({:subscribe, channels}, self(), st)

      assert new_state.subscriptions == channels
      assert_receive {:frame_sent, {:text, json}}
      assert %{"op" => "subscribe", "args" => ^channels} = Jason.decode!(json)
    end

    test "subscribing is idempotent" do
      channels = [%{"channel" => "trades", "instId" => "BTC-USDT"}]
      st = state(subscriptions: channels)

      assert {:reply, :ok, new_state} =
               PublicConnection.handle_call({:subscribe, channels}, self(), st)

      assert new_state.subscriptions == channels
    end

    test "unsubscribing while connected sends the frame and drops the channels" do
      channels = [%{"channel" => "trades", "instId" => "BTC-USDT"}]
      st = state(subscriptions: channels)

      assert {:reply, :ok, new_state} =
               PublicConnection.handle_call({:unsubscribe, channels}, self(), st)

      assert new_state.subscriptions == []
      assert_receive {:frame_sent, {:text, json}}
      assert %{"op" => "unsubscribe", "args" => ^channels} = Jason.decode!(json)
    end

    test "subscribing to nothing while disconnected does not open a connection" do
      st = state(status: :disconnected, websocket_pid: nil, subscriptions: [])

      assert {:reply, :ok, new_state} = PublicConnection.handle_call({:subscribe, []}, self(), st)

      assert new_state.websocket_pid == nil
      assert new_state.status == :disconnected
    end

    test "subscribing while still connecting does not open a second connection" do
      channels = [%{"channel" => "trades"}]
      st = state(status: :connecting)

      assert {:reply, :ok, new_state} =
               PublicConnection.handle_call({:subscribe, channels}, self(), st)

      assert new_state.websocket_pid == st.websocket_pid
      assert new_state.status == :connecting
    end
  end

  describe "handle_cast/2" do
    test ":reconnect tears down and schedules a retry" do
      st = state()

      assert {:noreply, new_state} = PublicConnection.handle_cast(:reconnect, st)

      assert new_state.websocket_pid == nil
      assert new_state.status == :reconnecting
      assert is_reference(new_state.reconnect_timer)
      Process.cancel_timer(new_state.reconnect_timer)
    end

    test "add and remove subscriber" do
      pid = self()

      assert {:noreply, added} =
               PublicConnection.handle_cast({:add_subscriber, pid}, state())

      assert MapSet.member?(added.subscribers, pid)

      assert {:noreply, removed} =
               PublicConnection.handle_cast({:remove_subscriber, pid}, added)

      refute MapSet.member?(removed.subscribers, pid)
    end
  end
end
