defmodule ExBlofin.WebSocket.Client do
  @moduledoc """
  WebSockex client for BloFin WebSocket connections.

  Wraps WebSockex to handle the actual WebSocket connection, forwarding
  all received messages to a parent process.

  ## Usage

      {:ok, pid} = ExBlofin.WebSocket.Client.start_link(url, self())
      ExBlofin.WebSocket.Client.send_message(pid, %{"op" => "subscribe", ...})

  Messages received from the WebSocket will be sent to the parent process as:
  - `{:stream_connected, pid}` - When connection is established
  - `{:stream_message, pid, message}` - For each received text message
  - `{:stream_disconnected, pid, reason}` - When disconnected

  ## BloFin Ping/Pong

  BloFin uses application-level text-frame ping/pong. Send `"ping"` and
  receive `"pong"` as regular text frames (not WebSocket protocol pings).
  """

  use WebSockex

  require Logger

  defmodule State do
    @moduledoc false
    defstruct [:parent_pid, :connected]
  end

  @doc """
  Starts a WebSocket connection to the given URL.

  ## Parameters

    - `url` - The WebSocket URL to connect to
    - `parent_pid` - The process to send messages to
    - `opts` - Optional WebSockex options
  """
  def start_link(url, parent_pid, opts \\ []) do
    state = %State{parent_pid: parent_pid, connected: false}

    websockex_opts =
      opts
      |> Keyword.delete(:name)
      |> Keyword.put_new(:handle_initial_conn_failure, true)

    WebSockex.start_link(url, __MODULE__, state, websockex_opts)
  end

  @doc """
  Sends a message map to the WebSocket as a JSON text frame.
  """
  def send_message(pid, message) when is_map(message) do
    case Jason.encode(message) do
      {:ok, json} -> WebSockex.send_frame(pid, {:text, json})
      {:error, reason} -> {:error, {:encode_error, reason}}
    end
  end

  @doc """
  Sends a raw text frame to the WebSocket.

  Used for BloFin's application-level ping (`"ping"`).
  """
  def send_text(pid, text) when is_binary(text) do
    WebSockex.send_frame(pid, {:text, text})
  end

  @doc """
  Sends a ping text frame. BloFin uses `"ping"` as a text frame, not a WS protocol ping.
  """
  def send_ping(pid) do
    send_text(pid, "ping")
  end

  @doc """
  Closes the WebSocket connection gracefully.
  """
  def close(pid) do
    WebSockex.cast(pid, :close)
  end

  # ============================================================================
  # WebSockex Callbacks
  # ============================================================================

  @impl WebSockex
  def handle_connect(_conn, state) do
    Logger.debug("[ExBlofin.WebSocket.Client] Connected to WebSocket")
    send(state.parent_pid, {:stream_connected, self()})
    {:ok, %{state | connected: true}}
  end

  @impl WebSockex
  def handle_frame({:text, msg}, state) do
    Logger.debug("[ExBlofin.WebSocket.Client] Received: #{String.slice(msg, 0, 200)}")
    send(state.parent_pid, {:stream_message, self(), msg})
    {:ok, state}
  end

  @impl WebSockex
  def handle_frame({:binary, msg}, state) do
    Logger.debug("[ExBlofin.WebSocket.Client] Received binary frame: #{byte_size(msg)} bytes")
    send(state.parent_pid, {:stream_binary, self(), msg})
    {:ok, state}
  end

  @impl WebSockex
  def handle_frame({:ping, msg}, state) do
    Logger.debug("[ExBlofin.WebSocket.Client] Received WS protocol ping")
    {:reply, {:pong, msg}, state}
  end

  @impl WebSockex
  def handle_frame({:pong, _msg}, state) do
    Logger.debug("[ExBlofin.WebSocket.Client] Received WS protocol pong")
    {:ok, state}
  end

  @impl WebSockex
  def handle_disconnect(disconnect_map, state) do
    reason = disconnect_map[:reason] || :unknown
    attempt = disconnect_map[:attempt_number] || 1

    case reason do
      :normal ->
        Logger.info("[ExBlofin.WebSocket.Client] Closed normally")
        send(state.parent_pid, {:stream_disconnected, self(), :normal})
        {:ok, %{state | connected: false}}

      _ ->
        Logger.warning(
          "[ExBlofin.WebSocket.Client] Disconnected: #{inspect(reason)}, " <>
            "reconnecting (attempt #{attempt})"
        )

        send(state.parent_pid, {:stream_disconnected, self(), reason})
        {:reconnect, %{state | connected: false}}
    end
  end

  @impl WebSockex
  def handle_cast(:close, state) do
    Logger.debug("[ExBlofin.WebSocket.Client] Closing connection")
    {:close, state}
  end

  @impl WebSockex
  def handle_cast({:send, frame}, state) do
    {:reply, frame, state}
  end

  @impl WebSockex
  def handle_info(msg, state) do
    Logger.debug("[ExBlofin.WebSocket.Client] Received info: #{inspect(msg)}")
    {:ok, state}
  end

  @impl WebSockex
  def terminate(reason, state) do
    Logger.debug("[ExBlofin.WebSocket.Client] Terminating: #{inspect(reason)}")

    if state.connected do
      send(state.parent_pid, {:stream_disconnected, self(), reason})
    end

    :ok
  end
end
