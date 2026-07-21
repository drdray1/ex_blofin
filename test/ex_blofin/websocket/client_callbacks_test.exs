defmodule ExBlofin.WebSocket.ClientCallbacksTest do
  @moduledoc """
  Unit tests for `ExBlofin.WebSocket.Client`'s WebSockex callbacks.

  The callbacks are plain functions over a `State` struct, so they can be
  driven directly without standing up a WebSocket server. Anything that would
  otherwise only run against a live connection — frame dispatch, reconnect
  pacing, terminate semantics — is covered here.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias ExBlofin.WebSocket.Client
  alias ExBlofin.WebSocket.Client.State

  defp state(connected \\ false), do: %State{parent_pid: self(), connected: connected}

  describe "handle_connect/2" do
    test "notifies the parent and marks the state connected" do
      capture_log(fn ->
        assert {:ok, new_state} = Client.handle_connect(:conn, state())
        assert new_state.connected
      end)

      assert_received {:stream_connected, _pid}
    end
  end

  describe "handle_frame/2" do
    test "forwards text frames to the parent" do
      capture_log(fn ->
        assert {:ok, _state} = Client.handle_frame({:text, ~s({"event":"pong"})}, state(true))
      end)

      assert_received {:stream_message, _pid, ~s({"event":"pong"})}
    end

    test "forwards binary frames to the parent" do
      capture_log(fn ->
        assert {:ok, _state} = Client.handle_frame({:binary, <<1, 2, 3>>}, state(true))
      end)

      assert_received {:stream_binary, _pid, <<1, 2, 3>>}
    end

    test "answers a protocol ping with a matching pong" do
      capture_log(fn ->
        assert {:reply, {:pong, "abc"}, _state} =
                 Client.handle_frame({:ping, "abc"}, state(true))
      end)
    end

    test "accepts a protocol pong without replying" do
      capture_log(fn ->
        assert {:ok, _state} = Client.handle_frame({:pong, "abc"}, state(true))
      end)

      refute_received {:stream_message, _, _}
    end
  end

  describe "handle_disconnect/2" do
    test "a normal close notifies the parent and does not reconnect" do
      capture_log(fn ->
        assert {:ok, new_state} =
                 Client.handle_disconnect(%{reason: :normal, attempt_number: 1}, state(true))

        refute new_state.connected
      end)

      assert_received {:stream_disconnected, _pid, :normal}
    end

    @tag :slow
    test "an abnormal close notifies the parent and requests a reconnect" do
      # Sleeps for the computed backoff (1s at attempt 1) before returning
      # :reconnect, which is what paces retries.
      log =
        capture_log(fn ->
          assert {:reconnect, new_state} =
                   Client.handle_disconnect(
                     %{reason: {:remote, :closed}, attempt_number: 1},
                     state(true)
                   )

          refute new_state.connected
        end)

      assert log =~ "reconnecting in 1000ms"
      assert_received {:stream_disconnected, _pid, {:remote, :closed}}
    end

    test "defaults a missing reason and attempt number" do
      log =
        capture_log(fn ->
          assert {:reconnect, _state} = Client.handle_disconnect(%{}, state(true))
        end)

      assert log =~ ":unknown"
      assert log =~ "attempt 1"
    end
  end

  describe "reconnect_delay/2" do
    test "backs off exponentially from 1s" do
      assert Client.reconnect_delay(:normal, 1) == 1_000
      assert Client.reconnect_delay(:normal, 2) == 2_000
      assert Client.reconnect_delay(:normal, 3) == 4_000
      assert Client.reconnect_delay(:normal, 4) == 8_000
    end

    test "caps at 30s" do
      assert Client.reconnect_delay(:normal, 6) == 30_000
      assert Client.reconnect_delay(:normal, 50) == 30_000
    end

    test "applies a 10s floor when rate limited" do
      rate_limited = %WebSockex.RequestError{code: 429, message: "Too Many Requests"}

      # Early attempts would otherwise retry in 1-4s and keep the limit tripped.
      assert Client.reconnect_delay(rate_limited, 1) == 10_000
      assert Client.reconnect_delay(rate_limited, 3) == 10_000

      # Once the exponential delay exceeds the floor it takes over again.
      assert Client.reconnect_delay(rate_limited, 5) == 16_000
    end

    test "a non-429 request error gets no floor" do
      other = %WebSockex.RequestError{code: 500, message: "Server Error"}
      assert Client.reconnect_delay(other, 1) == 1_000
    end
  end

  describe "handle_cast/2" do
    test ":close closes the connection" do
      capture_log(fn ->
        assert {:close, _state} = Client.handle_cast(:close, state(true))
      end)
    end

    test "{:send, frame} replies with the frame" do
      assert {:reply, {:text, "ping"}, _state} =
               Client.handle_cast({:send, {:text, "ping"}}, state(true))
    end
  end

  describe "handle_info/2" do
    test "ignores unrecognised messages" do
      capture_log(fn ->
        assert {:ok, _state} = Client.handle_info(:something_else, state(true))
      end)
    end
  end

  describe "terminate/2" do
    test "notifies the parent when it was connected" do
      capture_log(fn ->
        assert :ok = Client.terminate(:shutdown, state(true))
      end)

      assert_received {:stream_disconnected, _pid, :shutdown}
    end

    test "stays silent when it was never connected" do
      capture_log(fn ->
        assert :ok = Client.terminate(:shutdown, state(false))
      end)

      refute_received {:stream_disconnected, _, _}
    end
  end

  describe "send_message/2" do
    test "reports an encoding failure rather than raising" do
      # A pid is not JSON-encodable; the error is returned before any frame is
      # sent, so no live socket is needed.
      assert {:error, {:encode_error, _}} =
               Client.send_message(self(), %{"bad" => self()})
    end
  end
end
