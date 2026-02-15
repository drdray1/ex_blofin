defmodule ExBlofin.WebSocket.CopyTradingConnection do
  @moduledoc """
  GenServer managing a BloFin copy trading WebSocket connection.

  Handles authentication (login handshake) and subscribing to copy trading channels.

  ## State Machine

  `disconnected` → `connecting` → `authenticating` → `connected`

  ## Available Channels

  - `copytrading-positions-by-contract` - Positions grouped by contract
  - `copytrading-positions-by-order` - Positions grouped by order
  - `copytrading-orders` - Copy trading order updates
  - `copytrading-account` - Copy trading account updates

  ## Usage

      {:ok, pid} = ExBlofin.WebSocket.CopyTradingConnection.start_link(
        api_key: "key",
        secret_key: "secret",
        passphrase: "pass"
      )

      ExBlofin.WebSocket.CopyTradingConnection.add_subscriber(pid, self())
      ExBlofin.WebSocket.CopyTradingConnection.subscribe(pid, [
        %{"channel" => "copytrading-orders"},
        %{"channel" => "copytrading-account"}
      ])

      # You'll receive messages like:
      # {:blofin_event, :copytrading_orders, [%ExBlofin.WebSocket.Message.CopyOrderEvent{...}]}
  """

  use GenServer

  require Logger

  alias ExBlofin.Client
  alias ExBlofin.WebSocket.Client, as: StreamClient
  alias ExBlofin.WebSocket.Message

  defp ws_config(key, default) do
    :ex_blofin |> Application.get_env(:websocket, []) |> Keyword.get(key, default)
  end

  defp ping_interval_ms, do: ws_config(:ping_interval_ms, 25_000)
  defp reconnect_base_delay_ms, do: ws_config(:reconnect_base_delay_ms, 1_000)
  defp reconnect_max_delay_ms, do: ws_config(:reconnect_max_delay_ms, 30_000)
  defp max_reconnect_attempts, do: ws_config(:max_reconnect_attempts, 10)

  defmodule State do
    @moduledoc false
    defstruct [
      :api_key,
      :secret_key,
      :passphrase,
      :websocket_pid,
      :status,
      :reconnect_attempts,
      :reconnect_timer,
      :ping_timer,
      subscriptions: [],
      subscribers: MapSet.new()
    ]
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Starts a CopyTradingConnection process.

  ## Options

    - `:api_key` - Required. BloFin API key
    - `:secret_key` - Required. BloFin secret key
    - `:passphrase` - Required. BloFin API passphrase
    - `:name` - Optional process name
  """
  def start_link(opts) do
    api_key = Keyword.fetch!(opts, :api_key)
    secret_key = Keyword.fetch!(opts, :secret_key)
    passphrase = Keyword.fetch!(opts, :passphrase)
    name = Keyword.get(opts, :name)

    gen_opts = if name, do: [name: name], else: []
    init_args = %{api_key: api_key, secret_key: secret_key, passphrase: passphrase}
    GenServer.start_link(__MODULE__, init_args, gen_opts)
  end

  @doc """
  Subscribes to one or more copy trading channels.

  ## Parameters

    - `channels` - List of channel arg maps, e.g. `[%{"channel" => "copytrading-orders"}]`
  """
  def subscribe(server, channels) when is_list(channels) do
    GenServer.call(server, {:subscribe, channels})
  end

  @doc "Unsubscribes from one or more copy trading channels."
  def unsubscribe(server, channels) when is_list(channels) do
    GenServer.call(server, {:unsubscribe, channels})
  end

  @doc "Registers a process to receive streaming events."
  def add_subscriber(server, pid) when is_pid(pid) do
    GenServer.cast(server, {:add_subscriber, pid})
  end

  @doc "Unregisters a process from receiving events."
  def remove_subscriber(server, pid) when is_pid(pid) do
    GenServer.cast(server, {:remove_subscriber, pid})
  end

  @doc "Returns the current connection status."
  def get_status(server), do: GenServer.call(server, :get_status)

  @doc "Returns connection info."
  def get_info(server), do: GenServer.call(server, :get_info)

  @doc "Forces a reconnection."
  def reconnect(server), do: GenServer.cast(server, :reconnect)

  @doc "Stops the connection."
  def stop(server), do: GenServer.stop(server, :normal)

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init(%{api_key: api_key, secret_key: secret_key, passphrase: passphrase}) do
    state = %State{
      api_key: api_key,
      secret_key: secret_key,
      passphrase: passphrase,
      status: :disconnected,
      reconnect_attempts: 0
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:subscribe, channels}, _from, state) do
    state = %{state | subscriptions: Enum.uniq(state.subscriptions ++ channels)}

    if state.status == :connected and state.websocket_pid do
      send_subscribe(state.websocket_pid, channels)
    end

    {:reply, :ok, maybe_connect(state)}
  end

  @impl GenServer
  def handle_call({:unsubscribe, channels}, _from, state) do
    state = %{state | subscriptions: state.subscriptions -- channels}

    if state.status == :connected and state.websocket_pid do
      send_unsubscribe(state.websocket_pid, channels)
    end

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(:get_status, _from, state), do: {:reply, state.status, state}

  @impl GenServer
  def handle_call(:get_info, _from, state) do
    info = %{
      status: state.status,
      subscriptions: state.subscriptions,
      subscriber_count: MapSet.size(state.subscribers)
    }

    {:reply, info, state}
  end

  @impl GenServer
  def handle_cast({:add_subscriber, pid}, state) do
    Process.monitor(pid)
    {:noreply, %{state | subscribers: MapSet.put(state.subscribers, pid)}}
  end

  @impl GenServer
  def handle_cast({:remove_subscriber, pid}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  @impl GenServer
  def handle_cast(:reconnect, state) do
    {:noreply, state |> disconnect() |> schedule_reconnect()}
  end

  @impl GenServer
  def handle_info({:stream_connected, ws_pid}, %{websocket_pid: ws_pid} = state) do
    Logger.info("[ExBlofin.WS.CopyTrading] Connected, sending login")

    state = %{state | status: :authenticating, reconnect_attempts: 0}
    send_login(state)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:stream_message, ws_pid, raw}, %{websocket_pid: ws_pid} = state) do
    case Message.parse(raw) do
      {:ok, :pong, _} ->
        Logger.debug("[ExBlofin.WS.CopyTrading] Pong received")
        {:noreply, state}

      {:ok, :login, %{code: "0"}} ->
        Logger.info("[ExBlofin.WS.CopyTrading] Login successful")
        state = %{state | status: :connected}
        state = schedule_ping(state)

        if state.subscriptions != [] do
          send_subscribe(ws_pid, state.subscriptions)
        end

        {:noreply, state}

      {:ok, :login, %{code: code, msg: msg}} ->
        Logger.error("[ExBlofin.WS.CopyTrading] Login failed: #{code} - #{msg}")
        {:noreply, state |> disconnect() |> schedule_reconnect()}

      {:ok, :subscribe, arg} ->
        Logger.info("[ExBlofin.WS.CopyTrading] Subscribed: #{inspect(arg)}")
        {:noreply, state}

      {:ok, :unsubscribe, arg} ->
        Logger.info("[ExBlofin.WS.CopyTrading] Unsubscribed: #{inspect(arg)}")
        {:noreply, state}

      {:ok, :error, %{code: code, msg: msg}} ->
        Logger.error("[ExBlofin.WS.CopyTrading] Error: #{code} - #{msg}")
        {:noreply, state}

      {:ok, channel, events} ->
        broadcast(state.subscribers, channel, events)
        {:noreply, state}

      {:error, reason} ->
        Logger.debug("[ExBlofin.WS.CopyTrading] Parse error: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:stream_disconnected, ws_pid, reason}, %{websocket_pid: ws_pid} = state) do
    Logger.warning("[ExBlofin.WS.CopyTrading] Disconnected: #{inspect(reason)}")
    state = %{state | websocket_pid: nil, status: :disconnected}
    state = cancel_timer(state, :ping_timer)
    {:noreply, schedule_reconnect(state)}
  end

  @impl GenServer
  def handle_info(:send_ping, state) do
    state = %{state | ping_timer: nil}

    if state.status == :connected and state.websocket_pid do
      StreamClient.send_ping(state.websocket_pid)
      {:noreply, schedule_ping(state)}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(:reconnect, state) do
    Logger.info(
      "[ExBlofin.WS.CopyTrading] Reconnecting (attempt #{state.reconnect_attempts + 1})"
    )

    {:noreply, do_connect(%{state | reconnect_timer: nil})}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  @impl GenServer
  def handle_info(_msg, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    cancel_timer(state, :reconnect_timer)
    cancel_timer(state, :ping_timer)
    if state.websocket_pid, do: StreamClient.close(state.websocket_pid)
    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp maybe_connect(%{status: :connected} = state), do: state
  defp maybe_connect(%{status: :connecting} = state), do: state
  defp maybe_connect(%{status: :authenticating} = state), do: state
  defp maybe_connect(%{subscriptions: []} = state), do: state
  defp maybe_connect(state), do: do_connect(state)

  defp do_connect(state) do
    url = Client.ws_copy_trading_url()

    case StreamClient.start_link(url, self()) do
      {:ok, ws_pid} ->
        %{state | websocket_pid: ws_pid, status: :connecting}

      {:error, reason} ->
        Logger.error("[ExBlofin.WS.CopyTrading] Connect failed: #{inspect(reason)}")
        schedule_reconnect(%{state | status: :disconnected})
    end
  end

  defp send_login(state) do
    msg = Message.build_login(state.api_key, state.secret_key, state.passphrase)
    StreamClient.send_message(state.websocket_pid, msg)
  end

  defp send_subscribe(ws_pid, channels) do
    msg = Message.build_subscribe(channels)
    StreamClient.send_message(ws_pid, msg)
  end

  defp send_unsubscribe(ws_pid, channels) do
    msg = Message.build_unsubscribe(channels)
    StreamClient.send_message(ws_pid, msg)
  end

  defp broadcast(subscribers, channel, events) do
    Enum.each(subscribers, fn pid ->
      send(pid, {:blofin_event, channel, events})
    end)
  end

  defp schedule_ping(state) do
    state = cancel_timer(state, :ping_timer)
    timer = Process.send_after(self(), :send_ping, ping_interval_ms())
    %{state | ping_timer: timer}
  end

  defp schedule_reconnect(%{reconnect_attempts: attempts} = state) do
    if attempts >= max_reconnect_attempts() do
      Logger.error("[ExBlofin.WS.CopyTrading] Max reconnect attempts reached")
      %{state | status: :disconnected}
    else
      state = cancel_timer(state, :reconnect_timer)

      delay =
        min(
          reconnect_base_delay_ms() * round(:math.pow(2, attempts)),
          reconnect_max_delay_ms()
        )

      timer = Process.send_after(self(), :reconnect, delay)

      %{
        state
        | reconnect_timer: timer,
          reconnect_attempts: attempts + 1,
          status: :reconnecting
      }
    end
  end

  defp disconnect(state) do
    state = cancel_timer(state, :reconnect_timer)
    state = cancel_timer(state, :ping_timer)
    if state.websocket_pid, do: StreamClient.close(state.websocket_pid)

    %{state | websocket_pid: nil, status: :disconnected, reconnect_timer: nil, ping_timer: nil}
  end

  defp cancel_timer(state, field) do
    case Map.get(state, field) do
      nil ->
        state

      ref ->
        Process.cancel_timer(ref)
        Map.put(state, field, nil)
    end
  end
end
