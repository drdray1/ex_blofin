defmodule ExBlofin.WebSocket.AuthenticatedConnectionCallbacksTest do
  @moduledoc """
  Drives the GenServer callbacks of the two authenticated connections directly.

  `PrivateConnection` and `CopyTradingConnection` share a structure — connect,
  log in, then dispatch events — so both are exercised by the same cases. The
  login handshake in particular is unreachable through the public API without a
  live server, and it is where a silent failure would leave a caller connected
  but never receiving data.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias ExBlofin.WebSocket.{CopyTradingConnection, PrivateConnection}

  @connections [
    {PrivateConnection, PrivateConnection.State, "ExBlofin.WS.Private"},
    {CopyTradingConnection, CopyTradingConnection.State, "ExBlofin.WS.CopyTrading"}
  ]

  # Speaks enough of the `:gen.call` protocol for WebSockex.send_frame/2 to
  # return, and forwards frames to the test. WebSockex raises if a process
  # sends a frame to itself, so the socket must be a separate process.
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

  defp cleanup(state) do
    for field <- [:ping_timer, :reconnect_timer] do
      case Map.get(state, field) do
        ref when is_reference(ref) -> Process.cancel_timer(ref)
        _ -> :ok
      end
    end
  end

  for {mod, state_mod, log_prefix} <- @connections do
    describe "#{inspect(mod)} login handshake" do
      setup do
        base =
          struct!(unquote(state_mod), %{
            api_key: "key",
            secret_key: "secret",
            passphrase: "pass",
            websocket_pid: fake_socket(),
            status: :connecting,
            reconnect_attempts: 0,
            subscriptions: [],
            subscribers: MapSet.new()
          })

        %{state: base}
      end

      test "sends a login frame on connect", %{state: st} do
        log =
          capture_log(fn ->
            assert {:noreply, new_state} =
                     unquote(mod).handle_info({:stream_connected, st.websocket_pid}, st)

            assert new_state.status == :authenticating
            assert new_state.reconnect_attempts == 0
          end)

        assert log =~ "#{unquote(log_prefix)}] Connected, sending login"

        assert_receive {:frame_sent, {:text, json}}
        decoded = Jason.decode!(json)
        assert decoded["op"] == "login"
        assert [%{"apiKey" => "key", "passphrase" => "pass"} | _] = decoded["args"]
      end

      test "a successful login moves to connected and starts pinging", %{state: st} do
        raw = ~s({"event":"login","code":"0","msg":""})

        capture_log(fn ->
          assert {:noreply, new_state} =
                   unquote(mod).handle_info(
                     {:stream_message, st.websocket_pid, raw},
                     %{st | status: :authenticating}
                   )

          assert new_state.status == :connected
          assert is_reference(new_state.ping_timer)
          cleanup(new_state)
        end)
      end

      test "a successful login replays pending subscriptions", %{state: st} do
        subs = [%{"channel" => "orders"}]
        raw = ~s({"event":"login","code":"0","msg":""})

        capture_log(fn ->
          assert {:noreply, new_state} =
                   unquote(mod).handle_info(
                     {:stream_message, st.websocket_pid, raw},
                     %{st | status: :authenticating, subscriptions: subs}
                   )

          cleanup(new_state)
        end)

        assert_receive {:frame_sent, {:text, json}}
        assert %{"op" => "subscribe", "args" => ^subs} = Jason.decode!(json)
      end

      test "a failed login disconnects and schedules a reconnect", %{state: st} do
        raw = ~s({"event":"login","code":"60009","msg":"Login failed"})

        log =
          capture_log(fn ->
            assert {:noreply, new_state} =
                     unquote(mod).handle_info(
                       {:stream_message, st.websocket_pid, raw},
                       %{st | status: :authenticating}
                     )

            # Must not sit in :authenticating forever — that would look alive
            # to a caller while silently receiving nothing.
            assert new_state.status == :reconnecting
            assert new_state.websocket_pid == nil
            assert is_reference(new_state.reconnect_timer)
            assert new_state.reconnect_attempts == 1
            cleanup(new_state)
          end)

        assert log =~ "Login failed: 60009 - Login failed"
      end
    end

    describe "#{inspect(mod)} event dispatch" do
      setup do
        base =
          struct!(unquote(state_mod), %{
            api_key: "key",
            secret_key: "secret",
            passphrase: "pass",
            websocket_pid: fake_socket(),
            status: :connected,
            reconnect_attempts: 0,
            subscriptions: [],
            subscribers: MapSet.new()
          })

        %{state: base}
      end

      test "broadcasts data events to subscribers", %{state: st} do
        parent = self()

        sub =
          spawn(fn ->
            receive do
              {:blofin_event, channel, events} -> send(parent, {:got, channel, events})
            end
          end)

        raw =
          ~s({"arg":{"channel":"orders"},"data":[{"instId":"BTC-USDT",) <>
            ~s("orderId":"1","state":"filled"}]})

        capture_log(fn ->
          assert {:noreply, _} =
                   unquote(mod).handle_info(
                     {:stream_message, st.websocket_pid, raw},
                     %{st | subscribers: MapSet.new([sub])}
                   )
        end)

        assert_receive {:got, _channel, [_event]}
      end

      test "handles pong, subscribe, unsubscribe, error and garbage frames", %{state: st} do
        frames = [
          "pong",
          ~s({"event":"subscribe","arg":{"channel":"orders"}}),
          ~s({"event":"unsubscribe","arg":{"channel":"orders"}}),
          ~s({"event":"error","code":"60012","msg":"Invalid request"}),
          "not json"
        ]

        log =
          capture_log(fn ->
            for frame <- frames do
              assert {:noreply, _} =
                       unquote(mod).handle_info({:stream_message, st.websocket_pid, frame}, st)
            end
          end)

        assert log =~ "Pong received"
        assert log =~ "Subscribed"
        assert log =~ "Unsubscribed"
        assert log =~ "60012 - Invalid request"
        assert log =~ "Parse error"
      end

      test "ignores frames from a stale socket", %{state: st} do
        other = spawn(fn -> :ok end)
        assert {:noreply, ^st} = unquote(mod).handle_info({:stream_message, other, "pong"}, st)
      end
    end

    describe "#{inspect(mod)} lifecycle callbacks" do
      setup do
        base =
          struct!(unquote(state_mod), %{
            api_key: "key",
            secret_key: "secret",
            passphrase: "pass",
            websocket_pid: fake_socket(),
            status: :connected,
            reconnect_attempts: 0,
            subscriptions: [],
            subscribers: MapSet.new()
          })

        %{state: base}
      end

      test "disconnect moves to reconnecting and clears the ping timer", %{state: st} do
        timer = Process.send_after(self(), :send_ping, 60_000)

        capture_log(fn ->
          assert {:noreply, new_state} =
                   unquote(mod).handle_info(
                     {:stream_disconnected, st.websocket_pid, {:remote, :closed}},
                     %{st | ping_timer: timer}
                   )

          assert new_state.status == :reconnecting
          assert new_state.ping_timer == nil
        end)
      end

      test ":send_ping reschedules only while connected", %{state: st} do
        assert {:noreply, connected} = unquote(mod).handle_info(:send_ping, st)
        assert is_reference(connected.ping_timer)
        cleanup(connected)

        assert {:noreply, idle} =
                 unquote(mod).handle_info(:send_ping, %{st | status: :disconnected})

        assert idle.ping_timer == nil
      end

      test ":DOWN removes the dead subscriber only", %{state: st} do
        dead = spawn(fn -> :ok end)
        alive = self()

        assert {:noreply, new_state} =
                 unquote(mod).handle_info(
                   {:DOWN, make_ref(), :process, dead, :normal},
                   %{st | subscribers: MapSet.new([dead, alive])}
                 )

        refute MapSet.member?(new_state.subscribers, dead)
        assert MapSet.member?(new_state.subscribers, alive)
      end

      test "unrelated messages are ignored", %{state: st} do
        assert {:noreply, ^st} = unquote(mod).handle_info(:nonsense, st)
      end

      test "get_status and get_info report state", %{state: st} do
        st = %{st | subscriptions: [%{"channel" => "orders"}], subscribers: MapSet.new([self()])}

        assert {:reply, :connected, ^st} = unquote(mod).handle_call(:get_status, self(), st)

        assert {:reply, info, ^st} = unquote(mod).handle_call(:get_info, self(), st)
        assert info.status == :connected
        assert info.subscriber_count == 1
      end

      test "add and remove subscriber", %{state: st} do
        pid = self()

        assert {:noreply, added} = unquote(mod).handle_cast({:add_subscriber, pid}, st)
        assert MapSet.member?(added.subscribers, pid)

        assert {:noreply, removed} = unquote(mod).handle_cast({:remove_subscriber, pid}, added)
        refute MapSet.member?(removed.subscribers, pid)
      end

      test "subscribing while connected sends the frame", %{state: st} do
        channels = [%{"channel" => "orders"}]

        assert {:reply, :ok, new_state} =
                 unquote(mod).handle_call({:subscribe, channels}, self(), st)

        assert new_state.subscriptions == channels
        assert_receive {:frame_sent, {:text, json}}
        assert %{"op" => "subscribe", "args" => ^channels} = Jason.decode!(json)
      end

      test "unsubscribing while connected sends the frame", %{state: st} do
        channels = [%{"channel" => "orders"}]

        assert {:reply, :ok, new_state} =
                 unquote(mod).handle_call(
                   {:unsubscribe, channels},
                   self(),
                   %{st | subscriptions: channels}
                 )

        assert new_state.subscriptions == []
        assert_receive {:frame_sent, {:text, json}}
        assert %{"op" => "unsubscribe", "args" => ^channels} = Jason.decode!(json)
      end

      test "subscribing to nothing while disconnected does not connect", %{state: st} do
        idle = %{st | status: :disconnected, websocket_pid: nil, subscriptions: []}

        assert {:reply, :ok, new_state} = unquote(mod).handle_call({:subscribe, []}, self(), idle)

        assert new_state.websocket_pid == nil
        assert new_state.status == :disconnected
      end

      test ":reconnect tears down and schedules a retry", %{state: st} do
        assert {:noreply, new_state} = unquote(mod).handle_cast(:reconnect, st)

        assert new_state.websocket_pid == nil
        assert new_state.status == :reconnecting
        assert is_reference(new_state.reconnect_timer)
        cleanup(new_state)
      end
    end
  end
end
