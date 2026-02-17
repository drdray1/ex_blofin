defmodule ExBlofin.WebSocket.PrivateConnection do
  @moduledoc """
  GenServer managing a BloFin private WebSocket connection.

  Handles authentication (login handshake) and subscribing to private
  account/trading channels.

  ## State Machine

  `disconnected` → `connecting` → `authenticating` → `connected`

  ## Available Channels

  - `orders` - Order updates
  - `orders-algo` - Algo order updates
  - `positions` - Position updates
  - `account` - Account balance updates

  ## Usage

      {:ok, pid} = ExBlofin.WebSocket.PrivateConnection.start_link(
        api_key: "key",
        secret_key: "secret",
        passphrase: "pass"
      )

      ExBlofin.WebSocket.PrivateConnection.add_subscriber(pid, self())
      ExBlofin.WebSocket.PrivateConnection.subscribe(pid, [
        %{"channel" => "orders"},
        %{"channel" => "positions"}
      ])

      # You'll receive messages like:
      # {:blofin_event, :orders, [%ExBlofin.WebSocket.Message.OrderEvent{...}]}
  """

  use GenServer

  require Logger

  alias ExBlofin.Client
  alias ExBlofin.WebSocket.Client, as: StreamClient
  alias ExBlofin.WebSocket.Message

  @ping_interval_ms 25_000
  @reconnect_base_delay_ms 1_000
  @reconnect_max_delay_ms 30_000
  # Reconnect indefinitely — cap exponent at 10 so delay stays at @reconnect_max_delay_ms

  defmodule State do
    @moduledoc false
    defstruct [
      :api_key,
      :secret_key,
      :passphrase,
      :websocket_pid,
      :demo,
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
  Starts a PrivateConnection process.

  ## Options

    - `:api_key` - Required. BloFin API key
    - `:secret_key` - Required. BloFin secret key
    - `:passphrase` - Required. BloFin API passphrase
    - `:demo` - Use demo environment (default: false)
    - `:name` - Optional process name
  """
  def start_link(opts) do
    api_key = Keyword.fetch!(opts, :api_key)
    secret_key = Keyword.fetch!(opts, :secret_key)
    passphrase = Keyword.fetch!(opts, :passphrase)
    demo = Keyword.get(opts, :demo, false)
    name = Keyword.get(opts, :name)

    gen_opts = if name, do: [name: name], else: []
    init_args = %{api_key: api_key, secret_key: secret_key, passphrase: passphrase, demo: demo}
    GenServer.start_link(__MODULE__, init_args, gen_opts)
  end

  @doc """
  Subscribes to one or more private channels.

  ## Parameters

    - `channels` - List of channel arg maps, e.g. `[%{"channel" => "orders"}]`
  """
  def subscribe(server, channels) when is_list(channels) do
    GenServer.call(server, {:subscribe, channels})
  end

  @doc "Unsubscribes from one or more private channels."
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
  def init(%{api_key: api_key, secret_key: secret_key, passphrase: passphrase, demo: demo}) do
    state = %State{
      api_key: api_key,
      secret_key: secret_key,
      passphrase: passphrase,
      demo: demo,
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
    Logger.info("[ExBlofin.WS.Private] Connected, sending login")

    state = %{state | status: :authenticating, reconnect_attempts: 0}
    send_login(state)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:stream_message, ws_pid, raw}, %{websocket_pid: ws_pid} = state) do
    case Message.parse(raw) do
      {:ok, :pong, _} ->
        Logger.debug("[ExBlofin.WS.Private] Pong received")
        {:noreply, state}

      {:ok, :login, %{code: "0"}} ->
        Logger.info("[ExBlofin.WS.Private] Login successful")
        state = %{state | status: :connected}
        state = schedule_ping(state)

        if state.subscriptions != [] do
          send_subscribe(ws_pid, state.subscriptions)
        end

        {:noreply, state}

      {:ok, :login, %{code: code, msg: msg}} ->
        Logger.error("[ExBlofin.WS.Private] Login failed: #{code} - #{msg}")
        {:noreply, state |> disconnect() |> schedule_reconnect()}

      {:ok, :subscribe, arg} ->
        Logger.info("[ExBlofin.WS.Private] Subscribed: #{inspect(arg)}")
        {:noreply, state}

      {:ok, :unsubscribe, arg} ->
        Logger.info("[ExBlofin.WS.Private] Unsubscribed: #{inspect(arg)}")
        {:noreply, state}

      {:ok, :error, %{code: code, msg: msg}} ->
        Logger.error("[ExBlofin.WS.Private] Error: #{code} - #{msg}")
        {:noreply, state}

      {:ok, channel, events} ->
        broadcast(state.subscribers, channel, events)
        {:noreply, state}

      {:error, reason} ->
        Logger.debug("[ExBlofin.WS.Private] Parse error: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:stream_disconnected, ws_pid, reason}, %{websocket_pid: ws_pid} = state) do
    Logger.warning("[ExBlofin.WS.Private] Disconnected: #{inspect(reason)}")
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
    Logger.info("[ExBlofin.WS.Private] Reconnecting (attempt #{state.reconnect_attempts + 1})")
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
    url = Client.ws_private_url(state.demo)

    case StreamClient.start_link(url, self()) do
      {:ok, ws_pid} ->
        %{state | websocket_pid: ws_pid, status: :connecting}

      {:error, reason} ->
        Logger.error("[ExBlofin.WS.Private] Connect failed: #{inspect(reason)}")
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
    timer = Process.send_after(self(), :send_ping, @ping_interval_ms)
    %{state | ping_timer: timer}
  end

  defp schedule_reconnect(state) do
    state = cancel_timer(state, :reconnect_timer)

    delay =
      min(
        @reconnect_base_delay_ms * round(:math.pow(2, min(state.reconnect_attempts, 10))),
        @reconnect_max_delay_ms
      )

    timer = Process.send_after(self(), :reconnect, delay)

    %{
      state
      | reconnect_timer: timer,
        reconnect_attempts: state.reconnect_attempts + 1,
        status: :reconnecting
    }
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
