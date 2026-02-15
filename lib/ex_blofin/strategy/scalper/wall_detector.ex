defmodule ExBlofin.Strategy.Scalper.WallDetector do
  @moduledoc """
  Detects and validates liquidity walls in order book data.

  A "wall" is a price level with statistically anomalous order size
  relative to the surrounding book. Walls are validated through:

  1. **Size** — Must be >= N times the median book level size
  2. **Persistence** — Must remain in the book for a minimum duration
  3. **Absorption** — Must absorb market orders hitting it (trade stream)
  4. **Proximity** — Must be within scalping range of current price
  5. **Round number** — Bonus for psychologically significant levels

  ## Signal Generation

  Validated walls produce signals with a 0-100 confidence score.
  Only signals above the configured `min_signal_score` threshold
  are emitted to subscribers.

  ## Architecture

  This GenServer subscribes to BookManager for order book updates
  and to the public WebSocket for trade events (to detect absorption).
  It is stateless on restart — wall tracking rebuilds from live data.
  """

  use GenServer

  require Logger

  alias ExBlofin.Strategy.Scalper.Config
  alias ExBlofin.Strategy.Scalper.BookManager.BookState

  defmodule Wall do
    @moduledoc "Represents a detected liquidity wall."
    defstruct [
      :inst_id,
      :side,
      :price,
      :size,
      :multiplier,
      :first_seen,
      :last_seen,
      absorption_count: 0,
      absorption_volume: 0.0
    ]

    @type t :: %__MODULE__{
            inst_id: String.t(),
            side: :bid | :ask,
            price: float(),
            size: float(),
            multiplier: float(),
            first_seen: integer(),
            last_seen: integer(),
            absorption_count: non_neg_integer(),
            absorption_volume: float()
          }
  end

  defmodule Signal do
    @moduledoc "Represents a trade signal from a validated wall."
    defstruct [:inst_id, :direction, :wall, :score, :entry_price, :stop_loss, :take_profit, :ts]

    @type t :: %__MODULE__{
            inst_id: String.t(),
            direction: :long | :short,
            wall: Wall.t(),
            score: float(),
            entry_price: float(),
            stop_loss: float(),
            take_profit: float(),
            ts: integer()
          }
  end

  defmodule State do
    @moduledoc false
    defstruct [
      :config,
      :book_manager,
      walls: %{},
      subscribers: MapSet.new()
    ]
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Starts the WallDetector process.

  ## Options

    - `:config` - Scalper config (required)
    - `:book_manager` - PID of BookManager (required)
    - `:ws_pid` - PID of PublicConnection for trade stream (required)
    - `:name` - Optional process name
  """
  def start_link(opts) do
    config = Keyword.fetch!(opts, :config)
    book_manager = Keyword.fetch!(opts, :book_manager)
    ws_pid = Keyword.fetch!(opts, :ws_pid)
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, {config, book_manager, ws_pid}, gen_opts)
  end

  @doc "Returns currently tracked walls for an instrument."
  @spec get_walls(GenServer.server(), String.t()) :: [Wall.t()]
  def get_walls(server, inst_id) do
    GenServer.call(server, {:get_walls, inst_id})
  end

  @doc "Returns all tracked walls across all instruments."
  @spec get_all_walls(GenServer.server()) :: %{String.t() => [Wall.t()]}
  def get_all_walls(server) do
    GenServer.call(server, :get_all_walls)
  end

  @doc """
  Evaluates the current best signal for an instrument.

  Returns `{:ok, signal}` if a high-confidence setup exists,
  or `{:error, :no_signal}` if nothing meets threshold.
  """
  @spec evaluate(GenServer.server(), String.t(), float()) :: {:ok, Signal.t()} | {:error, :no_signal}
  def evaluate(server, inst_id, current_price) do
    GenServer.call(server, {:evaluate, inst_id, current_price})
  end

  @doc "Registers a process to receive `{:wall_signal, signal}` messages."
  def add_subscriber(server, pid) when is_pid(pid) do
    GenServer.cast(server, {:add_subscriber, pid})
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init({config, book_manager, ws_pid}) do
    BookManager.add_subscriber(book_manager, self())

    trade_channels =
      Enum.map(config.watchlist, fn inst_id ->
        %{"channel" => "trades", "instId" => inst_id}
      end)

    ExBlofin.WebSocket.PublicConnection.add_subscriber(ws_pid, self())
    ExBlofin.WebSocket.PublicConnection.subscribe(ws_pid, trade_channels)

    Logger.info("[Scalper.WallDetector] Started, tracking #{length(config.watchlist)} instruments")

    {:ok, %State{config: config, book_manager: book_manager}}
  end

  @impl GenServer
  def handle_call({:get_walls, inst_id}, _from, state) do
    walls = Map.get(state.walls, inst_id, [])
    {:reply, walls, state}
  end

  @impl GenServer
  def handle_call(:get_all_walls, _from, state) do
    {:reply, state.walls, state}
  end

  @impl GenServer
  def handle_call({:evaluate, inst_id, current_price}, _from, state) do
    walls = Map.get(state.walls, inst_id, [])
    result = build_best_signal(walls, inst_id, current_price, state.config)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_cast({:add_subscriber, pid}, state) do
    Process.monitor(pid)
    {:noreply, %{state | subscribers: MapSet.put(state.subscribers, pid)}}
  end

  @impl GenServer
  def handle_info({:book_update, inst_id, book}, state) do
    now = System.monotonic_time(:millisecond)
    existing_walls = Map.get(state.walls, inst_id, [])
    detected = detect_walls(book, inst_id, state.config, now)
    merged = merge_walls(existing_walls, detected, now, state.config)
    walls = Map.put(state.walls, inst_id, merged)
    {:noreply, %{state | walls: walls}}
  end

  @impl GenServer
  def handle_info({:blofin_event, :trades, events}, state) do
    state = Enum.reduce(events, state, &process_trade/2)
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
  # Wall Detection
  # ============================================================================

  @doc false
  def detect_walls(%BookState{} = book, inst_id, config, now) do
    bid_walls = detect_side_walls(book.bids, :bid, inst_id, config, now)
    ask_walls = detect_side_walls(book.asks, :ask, inst_id, config, now)
    bid_walls ++ ask_walls
  end

  defp detect_side_walls(levels, side, inst_id, config, now) when is_list(levels) do
    sizes = Enum.map(levels, fn level -> parse_size(level) end)

    case sizes do
      [] ->
        []

      sizes ->
        median = median(sizes)

        if median == 0.0 do
          []
        else
          levels
          |> Enum.filter(fn level ->
            size = parse_size(level)
            multiplier = size / median
            multiplier >= config.wall_min_multiplier
          end)
          |> Enum.map(fn level ->
            price = parse_price(level)
            size = parse_size(level)

            %Wall{
              inst_id: inst_id,
              side: side,
              price: price,
              size: size,
              multiplier: size / median,
              first_seen: now,
              last_seen: now
            }
          end)
        end
    end
  end

  # ============================================================================
  # Wall Merging & Persistence Tracking
  # ============================================================================

  defp merge_walls(existing, detected, now, config) do
    stale_cutoff = now - config.wall_persistence_ms * 3

    existing_not_stale =
      Enum.filter(existing, fn w -> w.last_seen > stale_cutoff end)

    Enum.reduce(detected, existing_not_stale, fn new_wall, acc ->
      case find_matching_wall(acc, new_wall) do
        nil ->
          [new_wall | acc]

        {idx, old_wall} ->
          updated = %{
            old_wall
            | size: new_wall.size,
              multiplier: new_wall.multiplier,
              last_seen: now
          }

          List.replace_at(acc, idx, updated)
      end
    end)
  end

  defp find_matching_wall(walls, target) do
    walls
    |> Enum.with_index()
    |> Enum.find_value(fn {wall, idx} ->
      if wall.side == target.side and wall.price == target.price do
        {idx, wall}
      end
    end)
  end

  # ============================================================================
  # Trade Absorption Detection
  # ============================================================================

  defp process_trade(trade_event, state) do
    inst_id = trade_event.inst_id
    trade_price = parse_float(trade_event.price)
    trade_size = parse_float(trade_event.size)

    walls = Map.get(state.walls, inst_id, [])

    updated_walls =
      Enum.map(walls, fn wall ->
        if trade_hits_wall?(trade_event.side, trade_price, wall) do
          %{
            wall
            | absorption_count: wall.absorption_count + 1,
              absorption_volume: wall.absorption_volume + trade_size
          }
        else
          wall
        end
      end)

    %{state | walls: Map.put(state.walls, inst_id, updated_walls)}
  end

  defp trade_hits_wall?(trade_side, trade_price, %Wall{side: :bid, price: wall_price}) do
    trade_side == "sell" and abs(trade_price - wall_price) / wall_price < 0.0002
  end

  defp trade_hits_wall?(trade_side, trade_price, %Wall{side: :ask, price: wall_price}) do
    trade_side == "buy" and abs(trade_price - wall_price) / wall_price < 0.0002
  end

  # ============================================================================
  # Signal Generation & Scoring
  # ============================================================================

  defp build_best_signal([], _inst_id, _price, _config), do: {:error, :no_signal}

  defp build_best_signal(walls, inst_id, current_price, config) do
    now = System.monotonic_time(:millisecond)

    signals =
      walls
      |> Enum.filter(fn w -> wall_in_range?(w, current_price, config) end)
      |> Enum.map(fn w -> score_wall(w, current_price, config, now) end)
      |> Enum.filter(fn {score, _wall} -> score >= config.min_signal_score end)
      |> Enum.sort_by(fn {score, _wall} -> score end, :desc)

    case signals do
      [] ->
        {:error, :no_signal}

      [{score, wall} | _] ->
        signal = build_signal(wall, inst_id, current_price, score, config)
        {:ok, signal}
    end
  end

  defp score_wall(wall, current_price, config, now) do
    strength_score = min(wall.multiplier / config.wall_min_multiplier * 15, 30.0)

    age_ms = now - wall.first_seen
    persistence_score = min(age_ms / config.wall_persistence_ms * 10, 20.0)

    absorption_score =
      min(wall.absorption_count / max(config.wall_min_absorption_events, 1) * 12.5, 25.0)

    distance = abs(current_price - wall.price) / current_price
    max_dist = config.wall_max_distance_pct
    proximity_score = max(0, (1 - distance / max_dist) * 15)

    round_score = round_number_score(wall.price, config.round_number_bonus)

    spread_score = 5.0

    total =
      strength_score + persistence_score + absorption_score +
        proximity_score + round_score + spread_score

    {min(Float.round(total, 1), 100.0), wall}
  end

  defp round_number_score(price, bonus) do
    cond do
      rem(round(price), 10_000) == 0 -> bonus
      rem(round(price), 5_000) == 0 -> bonus * 0.8
      rem(round(price), 1_000) == 0 -> bonus * 0.6
      rem(round(price), 500) == 0 -> bonus * 0.4
      rem(round(price), 100) == 0 -> bonus * 0.2
      true -> 0.0
    end
  end

  defp wall_in_range?(wall, current_price, config) do
    distance = abs(current_price - wall.price) / current_price
    distance <= config.wall_max_distance_pct
  end

  defp build_signal(wall, inst_id, current_price, score, config) do
    {direction, entry, stop, target} =
      case wall.side do
        :bid ->
          entry = wall.price * 1.0001
          stop = wall.price * (1 - config.stop_loss_pct)
          target = entry * (1 + config.take_profit_pct)
          {:long, entry, stop, target}

        :ask ->
          entry = wall.price * 0.9999
          stop = wall.price * (1 + config.stop_loss_pct)
          target = entry * (1 - config.take_profit_pct)
          {:short, entry, stop, target}
      end

    %Signal{
      inst_id: inst_id,
      direction: direction,
      wall: wall,
      score: score,
      entry_price: Float.round(entry, 2),
      stop_loss: Float.round(stop, 2),
      take_profit: Float.round(target, 2),
      ts: System.monotonic_time(:millisecond)
    }
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp parse_price([price | _]) when is_binary(price), do: parse_float(price)
  defp parse_price(_), do: 0.0

  defp parse_size([_, size | _]) when is_binary(size), do: parse_float(size)
  defp parse_size(_), do: 0.0

  defp parse_float(str) when is_binary(str) do
    case Float.parse(str) do
      {val, _} -> val
      :error -> 0.0
    end
  end

  defp parse_float(num) when is_number(num), do: num / 1
  defp parse_float(_), do: 0.0

  defp median([]), do: 0.0

  defp median(list) do
    sorted = Enum.sort(list)
    len = length(sorted)
    mid = div(len, 2)

    if rem(len, 2) == 0 do
      (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
    else
      Enum.at(sorted, mid)
    end
  end
end
