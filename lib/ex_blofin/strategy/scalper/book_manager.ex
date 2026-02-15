defmodule ExBlofin.Strategy.Scalper.BookManager do
  @moduledoc """
  Manages real-time order book state for multiple instruments.

  Subscribes to the public WebSocket `books` channel and maintains
  the latest order book snapshot for each instrument in the watchlist.
  Broadcasts book updates to registered subscribers.

  Designed to rebuild from scratch on restart — the first WebSocket
  snapshot fully populates the book, ready in ~100ms after reconnection.
  """

  use GenServer

  require Logger

  alias ExBlofin.WebSocket.PublicConnection

  defmodule BookState do
    @moduledoc false
    defstruct [:inst_id, :asks, :bids, :ts, :last_update]

    @type t :: %__MODULE__{
            inst_id: String.t(),
            asks: [[String.t()]],
            bids: [[String.t()]],
            ts: String.t() | nil,
            last_update: integer() | nil
          }
  end

  defmodule State do
    @moduledoc false
    defstruct [
      :ws_pid,
      books: %{},
      subscribers: MapSet.new()
    ]

    @type t :: %__MODULE__{
            ws_pid: pid() | nil,
            books: %{String.t() => BookState.t()},
            subscribers: MapSet.t()
          }
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Starts the BookManager process.

  ## Options

    - `:ws_pid` - PID of a running PublicConnection (required)
    - `:instruments` - List of instrument IDs to track (required)
    - `:name` - Optional process name
  """
  def start_link(opts) do
    ws_pid = Keyword.fetch!(opts, :ws_pid)
    instruments = Keyword.fetch!(opts, :instruments)
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, {ws_pid, instruments}, gen_opts)
  end

  @doc """
  Returns the current order book for an instrument.

  Returns `{:ok, book}` or `{:error, :not_available}` if no snapshot has arrived yet.
  """
  @spec get_book(GenServer.server(), String.t()) :: {:ok, BookState.t()} | {:error, :not_available}
  def get_book(server, inst_id) do
    GenServer.call(server, {:get_book, inst_id})
  end

  @doc """
  Returns order books for all tracked instruments.
  """
  @spec get_all_books(GenServer.server()) :: %{String.t() => BookState.t()}
  def get_all_books(server) do
    GenServer.call(server, :get_all_books)
  end

  @doc "Registers a process to receive `{:book_update, inst_id, book}` messages."
  def add_subscriber(server, pid) when is_pid(pid) do
    GenServer.cast(server, {:add_subscriber, pid})
  end

  @doc "Unregisters a subscriber."
  def remove_subscriber(server, pid) when is_pid(pid) do
    GenServer.cast(server, {:remove_subscriber, pid})
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init({ws_pid, instruments}) do
    PublicConnection.add_subscriber(ws_pid, self())

    channels =
      Enum.map(instruments, fn inst_id ->
        %{"channel" => "books", "instId" => inst_id}
      end)

    PublicConnection.subscribe(ws_pid, channels)

    books =
      Map.new(instruments, fn inst_id ->
        {inst_id, %BookState{inst_id: inst_id, asks: [], bids: []}}
      end)

    Logger.info("[Scalper.BookManager] Tracking #{length(instruments)} instruments: #{Enum.join(instruments, ", ")}")

    {:ok, %State{ws_pid: ws_pid, books: books}}
  end

  @impl GenServer
  def handle_call({:get_book, inst_id}, _from, state) do
    case Map.get(state.books, inst_id) do
      nil -> {:reply, {:error, :not_available}, state}
      %BookState{ts: nil} -> {:reply, {:error, :not_available}, state}
      book -> {:reply, {:ok, book}, state}
    end
  end

  @impl GenServer
  def handle_call(:get_all_books, _from, state) do
    {:reply, state.books, state}
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
  def handle_info({:blofin_event, channel, events}, state) when channel in [:books, :books5] do
    state =
      Enum.reduce(events, state, fn event, acc ->
        apply_book_event(acc, event)
      end)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:blofin_event, _channel, _events}, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  @impl GenServer
  def handle_info(_msg, state), do: {:noreply, state}

  # ============================================================================
  # Book Updates
  # ============================================================================

  defp apply_book_event(state, event) do
    inst_id = event.inst_id

    case Map.get(state.books, inst_id) do
      nil ->
        state

      _existing ->
        now = System.monotonic_time(:millisecond)

        updated = %BookState{
          inst_id: inst_id,
          asks: event.asks || [],
          bids: event.bids || [],
          ts: event.ts,
          last_update: now
        }

        books = Map.put(state.books, inst_id, updated)
        broadcast_update(state.subscribers, inst_id, updated)
        %{state | books: books}
    end
  end

  defp broadcast_update(subscribers, inst_id, book) do
    Enum.each(subscribers, fn pid ->
      send(pid, {:book_update, inst_id, book})
    end)
  end
end
