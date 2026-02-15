defmodule ExBlofin.Strategy.Scalper.WatchlistScanner do
  @moduledoc """
  Scans a watchlist of instruments and ranks them by setup quality.

  Periodically evaluates each instrument in the watchlist by combining:
  - Wall detection signals (from WallDetector)
  - Volume and liquidity metrics (from ticker data)
  - Spread tightness
  - Current price proximity to detected walls

  Only the highest-scoring instrument that meets the minimum threshold
  is selected for trading. If nothing qualifies, the scanner waits.

  ## Architecture

  Runs on a configurable scan interval (default 1s). Subscribes to
  the public WebSocket for ticker data. Queries WallDetector for
  signal evaluation on each tick.
  """

  use GenServer

  require Logger

  alias ExBlofin.Strategy.Scalper.Config
  alias ExBlofin.Strategy.Scalper.WallDetector

  defmodule InstrumentScore do
    @moduledoc "Scored instrument from the watchlist scan."
    defstruct [
      :inst_id,
      :score,
      :signal,
      :last_price,
      :spread_pct,
      :volume_24h,
      :reason
    ]

    @type t :: %__MODULE__{
            inst_id: String.t(),
            score: float(),
            signal: WallDetector.Signal.t() | nil,
            last_price: float(),
            spread_pct: float(),
            volume_24h: float(),
            reason: String.t() | nil
          }
  end

  defmodule State do
    @moduledoc false
    defstruct [
      :config,
      :wall_detector,
      :scan_timer,
      tickers: %{},
      scores: [],
      subscribers: MapSet.new()
    ]
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Starts the WatchlistScanner process.

  ## Options

    - `:config` - Scalper config (required)
    - `:wall_detector` - PID of WallDetector (required)
    - `:ws_pid` - PID of PublicConnection for ticker stream (required)
    - `:name` - Optional process name
  """
  def start_link(opts) do
    config = Keyword.fetch!(opts, :config)
    wall_detector = Keyword.fetch!(opts, :wall_detector)
    ws_pid = Keyword.fetch!(opts, :ws_pid)
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, {config, wall_detector, ws_pid}, gen_opts)
  end

  @doc """
  Returns the current best trading opportunity.

  Returns `{:ok, instrument_score}` if a setup meets threshold,
  or `{:error, :no_opportunity}` if nothing qualifies.
  """
  @spec best_opportunity(GenServer.server()) ::
          {:ok, InstrumentScore.t()} | {:error, :no_opportunity}
  def best_opportunity(server) do
    GenServer.call(server, :best_opportunity)
  end

  @doc "Returns the full ranked list of instruments."
  @spec get_rankings(GenServer.server()) :: [InstrumentScore.t()]
  def get_rankings(server) do
    GenServer.call(server, :get_rankings)
  end

  @doc "Registers a process to receive `{:best_opportunity, instrument_score}` messages."
  def add_subscriber(server, pid) when is_pid(pid) do
    GenServer.cast(server, {:add_subscriber, pid})
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init({config, wall_detector, ws_pid}) do
    ExBlofin.WebSocket.PublicConnection.add_subscriber(ws_pid, self())

    ticker_channels =
      Enum.map(config.watchlist, fn inst_id ->
        %{"channel" => "tickers", "instId" => inst_id}
      end)

    ExBlofin.WebSocket.PublicConnection.subscribe(ws_pid, ticker_channels)

    timer = schedule_scan(config.scan_interval_ms)

    Logger.info("[Scalper.Scanner] Started, scanning #{length(config.watchlist)} instruments every #{config.scan_interval_ms}ms")

    {:ok,
     %State{
       config: config,
       wall_detector: wall_detector,
       scan_timer: timer
     }}
  end

  @impl GenServer
  def handle_call(:best_opportunity, _from, state) do
    case Enum.find(state.scores, fn s -> s.score >= state.config.min_signal_score end) do
      nil -> {:reply, {:error, :no_opportunity}, state}
      best -> {:reply, {:ok, best}, state}
    end
  end

  @impl GenServer
  def handle_call(:get_rankings, _from, state) do
    {:reply, state.scores, state}
  end

  @impl GenServer
  def handle_cast({:add_subscriber, pid}, state) do
    Process.monitor(pid)
    {:noreply, %{state | subscribers: MapSet.put(state.subscribers, pid)}}
  end

  @impl GenServer
  def handle_info({:blofin_event, :tickers, events}, state) do
    tickers =
      Enum.reduce(events, state.tickers, fn event, acc ->
        Map.put(acc, event.inst_id, event)
      end)

    {:noreply, %{state | tickers: tickers}}
  end

  @impl GenServer
  def handle_info({:blofin_event, _channel, _events}, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:scan, state) do
    scores = scan_watchlist(state)

    case Enum.find(scores, fn s -> s.score >= state.config.min_signal_score end) do
      nil ->
        :ok

      best ->
        Enum.each(state.subscribers, fn pid ->
          send(pid, {:best_opportunity, best})
        end)
    end

    timer = schedule_scan(state.config.scan_interval_ms)
    {:noreply, %{state | scores: scores, scan_timer: timer}}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  @impl GenServer
  def handle_info(_msg, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    if state.scan_timer, do: Process.cancel_timer(state.scan_timer)
    :ok
  end

  # ============================================================================
  # Scanning Logic
  # ============================================================================

  defp scan_watchlist(state) do
    state.config.watchlist
    |> Enum.map(fn inst_id -> score_instrument(inst_id, state) end)
    |> Enum.sort_by(fn s -> s.score end, :desc)
  end

  defp score_instrument(inst_id, state) do
    ticker = Map.get(state.tickers, inst_id)

    if is_nil(ticker) do
      %InstrumentScore{
        inst_id: inst_id,
        score: 0.0,
        signal: nil,
        last_price: 0.0,
        spread_pct: 0.0,
        volume_24h: 0.0,
        reason: "no_ticker_data"
      }
    else
      last_price = parse_float(ticker.last)
      bid = parse_float(ticker.bid_price)
      ask = parse_float(ticker.ask_price)
      volume = parse_float(ticker.vol_currency_24h)

      spread_pct =
        if bid > 0, do: (ask - bid) / bid, else: 1.0

      signal_result = WallDetector.evaluate(state.wall_detector, inst_id, last_price)

      {signal, signal_score} =
        case signal_result do
          {:ok, sig} -> {sig, sig.score}
          {:error, :no_signal} -> {nil, 0.0}
        end

      {final_score, reason} = compute_final_score(signal_score, spread_pct, volume, state.config)

      %InstrumentScore{
        inst_id: inst_id,
        score: final_score,
        signal: signal,
        last_price: last_price,
        spread_pct: Float.round(spread_pct, 6),
        volume_24h: volume,
        reason: reason
      }
    end
  end

  defp compute_final_score(signal_score, spread_pct, volume, config) do
    cond do
      spread_pct > config.max_spread_pct ->
        {0.0, "spread_too_wide"}

      volume < config.min_volume_24h ->
        {0.0, "volume_too_low"}

      signal_score == 0.0 ->
        {0.0, "no_wall_signal"}

      true ->
        spread_bonus =
          if spread_pct < config.max_spread_pct * 0.5, do: 5.0, else: 0.0

        volume_bonus =
          cond do
            volume > config.min_volume_24h * 10 -> 5.0
            volume > config.min_volume_24h * 5 -> 3.0
            true -> 0.0
          end

        final = min(signal_score + spread_bonus + volume_bonus, 100.0)
        {Float.round(final, 1), "qualified"}
    end
  end

  defp schedule_scan(interval_ms) do
    Process.send_after(self(), :scan, interval_ms)
  end

  defp parse_float(nil), do: 0.0

  defp parse_float(str) when is_binary(str) do
    case Float.parse(str) do
      {val, _} -> val
      :error -> 0.0
    end
  end

  defp parse_float(num) when is_number(num), do: num / 1
end
