defmodule ExBlofin.Strategy.Scalper.TradeExecutor do
  @moduledoc """
  Executes trades and manages open positions for the scalping strategy.

  Responsible for:
  - Receiving signals from the WatchlistScanner
  - Checking risk limits via RiskManager before each trade
  - Placing orders with proper position sizing
  - Managing stop-loss and take-profit via TP/SL orders
  - Enforcing max hold time (force-closing stale positions)
  - Reconciling positions with the exchange on startup

  ## Position Reconciliation on Restart

  On startup, the TradeExecutor:
  1. Loads the last known position from `{state_dir}/trade_state.json`
  2. Queries the exchange for actual open positions
  3. Reconciles: matching positions resume management, orphaned
     positions are closed immediately, closed positions update P&L

  ## Safety

  - Only one position at a time (configurable)
  - All positions use isolated margin
  - TP/SL orders placed immediately after entry
  - Max hold time enforced via timer
  """

  use GenServer

  require Logger

  alias ExBlofin.Strategy.Scalper.Config
  alias ExBlofin.Strategy.Scalper.RiskManager
  alias ExBlofin.Strategy.Scalper.WallDetector

  defmodule Position do
    @moduledoc "Represents an open position being managed."
    defstruct [
      :inst_id,
      :direction,
      :side,
      :size,
      :entry_price,
      :order_id,
      :stop_order_id,
      :tp_order_id,
      :signal_score,
      :opened_at,
      :max_hold_timer
    ]

    @type t :: %__MODULE__{
            inst_id: String.t(),
            direction: :long | :short,
            side: String.t(),
            size: String.t(),
            entry_price: float(),
            order_id: String.t() | nil,
            stop_order_id: String.t() | nil,
            tp_order_id: String.t() | nil,
            signal_score: float(),
            opened_at: DateTime.t(),
            max_hold_timer: reference() | nil
          }
  end

  defmodule State do
    @moduledoc false
    defstruct [
      :config,
      :client,
      :risk_manager,
      :scanner,
      :state_file,
      position: nil,
      trade_count: 0,
      status: :idle
    ]
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Starts the TradeExecutor process.

  ## Options

    - `:config` - Scalper config (required)
    - `:client` - Authenticated ExBlofin API client (required)
    - `:risk_manager` - PID of RiskManager (required)
    - `:scanner` - PID of WatchlistScanner (required)
    - `:name` - Optional process name
  """
  def start_link(opts) do
    config = Keyword.fetch!(opts, :config)
    client = Keyword.fetch!(opts, :client)
    risk_manager = Keyword.fetch!(opts, :risk_manager)
    scanner = Keyword.fetch!(opts, :scanner)
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []

    GenServer.start_link(
      __MODULE__,
      {config, client, risk_manager, scanner},
      gen_opts
    )
  end

  @doc "Returns the current position, if any."
  @spec get_position(GenServer.server()) :: Position.t() | nil
  def get_position(server) do
    GenServer.call(server, :get_position)
  end

  @doc "Returns the current executor status."
  @spec get_status(GenServer.server()) :: map()
  def get_status(server) do
    GenServer.call(server, :get_status)
  end

  @doc "Force-closes any open position via market order."
  @spec emergency_close(GenServer.server()) :: :ok | {:error, term()}
  def emergency_close(server) do
    GenServer.call(server, :emergency_close, 15_000)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init({config, client, risk_manager, scanner}) do
    state_dir = Config.state_dir(config)
    File.mkdir_p!(state_dir)
    state_file = Path.join(state_dir, "trade_state.json")

    ExBlofin.Strategy.Scalper.WatchlistScanner.add_subscriber(scanner, self())

    state = %State{
      config: config,
      client: client,
      risk_manager: risk_manager,
      scanner: scanner,
      state_file: state_file
    }

    send(self(), :reconcile_positions)

    Logger.info("[Scalper.TradeExecutor] Started in #{if config.live, do: "LIVE", else: "DEMO"} mode")

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_position, _from, state) do
    {:reply, state.position, state}
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    status = %{
      status: state.status,
      position: format_position(state.position),
      trade_count: state.trade_count,
      mode: if(state.config.live, do: :live, else: :demo)
    }

    {:reply, status, state}
  end

  @impl GenServer
  def handle_call(:emergency_close, _from, state) do
    case state.position do
      nil ->
        {:reply, :ok, state}

      position ->
        case close_position(state, position, "emergency_close") do
          {:ok, new_state} -> {:reply, :ok, new_state}
          {:error, reason} -> {:reply, {:error, reason}, state}
        end
    end
  end

  @impl GenServer
  def handle_info({:best_opportunity, opportunity}, state) do
    state = maybe_enter_trade(state, opportunity)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:max_hold_timeout, inst_id}, state) do
    case state.position do
      %Position{inst_id: ^inst_id} = pos ->
        Logger.warning("[Scalper.TradeExecutor] Max hold time exceeded for #{inst_id}, force closing")

        case close_position(state, pos, "max_hold_time") do
          {:ok, new_state} -> {:noreply, new_state}
          {:error, _reason} -> {:noreply, state}
        end

      _ ->
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(:reconcile_positions, state) do
    state = reconcile_positions(state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(_msg, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    if state.position do
      persist_trade_state(state)
    end

    :ok
  end

  # ============================================================================
  # Trade Entry
  # ============================================================================

  defp maybe_enter_trade(%{position: pos} = state, _opportunity) when not is_nil(pos) do
    state
  end

  defp maybe_enter_trade(state, opportunity) do
    case RiskManager.can_trade?(state.risk_manager) do
      {:ok, max_loss} ->
        execute_entry(state, opportunity, max_loss)

      {:error, reason} ->
        Logger.debug("[Scalper.TradeExecutor] Trade blocked: #{reason}")
        state
    end
  end

  defp execute_entry(state, opportunity, max_loss) do
    signal = opportunity.signal

    if is_nil(signal) do
      state
    else
      size = calculate_position_size(max_loss, signal, state.config)
      side = if(signal.direction == :long, do: "buy", else: "sell")

      Logger.info(
        "[Scalper.TradeExecutor] Entering #{signal.direction} #{signal.inst_id} | " <>
          "Score: #{signal.score} | Size: #{size} | Entry: #{signal.entry_price}"
      )

      result = place_entry_order(state, signal, side, size)

      case result do
        {:ok, order_id} ->
          position = %Position{
            inst_id: signal.inst_id,
            direction: signal.direction,
            side: side,
            size: size,
            entry_price: signal.entry_price,
            order_id: order_id,
            signal_score: signal.score,
            opened_at: DateTime.utc_now(),
            max_hold_timer:
              Process.send_after(
                self(),
                {:max_hold_timeout, signal.inst_id},
                state.config.max_hold_time_ms
              )
          }

          state = %{state | position: position, status: :in_trade, trade_count: state.trade_count + 1}

          state = place_tpsl(state, position, signal)
          persist_trade_state(state)
          state

        {:error, reason} ->
          Logger.error("[Scalper.TradeExecutor] Entry failed: #{inspect(reason)}")
          state
      end
    end
  end

  defp place_entry_order(state, signal, side, size) do
    params = %{
      "instId" => signal.inst_id,
      "marginMode" => state.config.margin_mode,
      "positionSide" => state.config.position_side,
      "side" => side,
      "orderType" => "market",
      "size" => size
    }

    case ExBlofin.Trading.place_order(state.client, params) do
      {:ok, [%{"orderId" => order_id, "code" => "0"} | _]} ->
        {:ok, order_id}

      {:ok, [%{"code" => code, "msg" => msg} | _]} ->
        {:error, "order rejected: #{code} - #{msg}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp place_tpsl(state, position, signal) do
    close_side = if(position.direction == :long, do: "sell", else: "buy")

    params = %{
      "instId" => position.inst_id,
      "marginMode" => state.config.margin_mode,
      "positionSide" => state.config.position_side,
      "side" => close_side,
      "size" => position.size,
      "tpTriggerPrice" => to_string(signal.take_profit),
      "tpOrderPrice" => "-1",
      "slTriggerPrice" => to_string(signal.stop_loss),
      "slOrderPrice" => "-1"
    }

    case ExBlofin.Trading.place_tpsl_order(state.client, params) do
      {:ok, [%{"tpslId" => tpsl_id} | _]} ->
        Logger.info("[Scalper.TradeExecutor] TP/SL placed: #{tpsl_id}")

        position = %{
          position
          | stop_order_id: tpsl_id,
            tp_order_id: tpsl_id
        }

        %{state | position: position}

      {:error, reason} ->
        Logger.error("[Scalper.TradeExecutor] TP/SL placement failed: #{inspect(reason)}")
        state
    end
  end

  # ============================================================================
  # Position Closing
  # ============================================================================

  defp close_position(state, position, reason) do
    Logger.info("[Scalper.TradeExecutor] Closing #{position.inst_id}: #{reason}")

    if position.max_hold_timer do
      Process.cancel_timer(position.max_hold_timer)
    end

    cancel_tpsl(state, position)

    params = %{
      "instId" => position.inst_id,
      "marginMode" => state.config.margin_mode,
      "positionSide" => state.config.position_side
    }

    case ExBlofin.Trading.close_position(state.client, params) do
      {:ok, _} ->
        Logger.info("[Scalper.TradeExecutor] Position closed: #{position.inst_id}")
        state = %{state | position: nil, status: :idle}
        clear_trade_state(state)
        {:ok, state}

      {:error, reason} ->
        Logger.error("[Scalper.TradeExecutor] Close failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp cancel_tpsl(state, position) do
    if position.stop_order_id do
      ExBlofin.Trading.cancel_tpsl_order(state.client, %{
        "instId" => position.inst_id,
        "tpslId" => position.stop_order_id
      })
    end
  end

  # ============================================================================
  # Position Sizing
  # ============================================================================

  defp calculate_position_size(max_loss, signal, config) do
    stop_distance_pct = config.stop_loss_pct
    leverage = config.leverage

    notional_size = max_loss / stop_distance_pct
    margin_required = notional_size / leverage

    contracts = notional_size / signal.entry_price

    contracts
    |> Float.round(0)
    |> max(1.0)
    |> trunc()
    |> to_string()
  end

  # ============================================================================
  # Position Reconciliation
  # ============================================================================

  defp reconcile_positions(state) do
    saved = load_trade_state(state.state_file)
    exchange_positions = fetch_exchange_positions(state)

    case {saved, exchange_positions} do
      {nil, []} ->
        Logger.info("[Scalper.TradeExecutor] No positions to reconcile")
        state

      {nil, positions} ->
        Logger.warning(
          "[Scalper.TradeExecutor] Orphaned position(s) found on exchange, closing #{length(positions)}"
        )

        close_orphaned_positions(state, positions)

      {saved_pos, []} ->
        Logger.info(
          "[Scalper.TradeExecutor] Saved position #{saved_pos["inst_id"]} was closed while offline"
        )

        clear_trade_state(state)
        state

      {saved_pos, exchange_pos} ->
        matching =
          Enum.find(exchange_pos, fn p ->
            p["instId"] == saved_pos["inst_id"]
          end)

        if matching do
          Logger.info("[Scalper.TradeExecutor] Resuming position: #{saved_pos["inst_id"]}")
          resume_position(state, saved_pos, matching)
        else
          Logger.warning("[Scalper.TradeExecutor] Position mismatch, closing exchange positions")
          close_orphaned_positions(state, exchange_pos)
        end
    end
  end

  defp fetch_exchange_positions(state) do
    case ExBlofin.Account.get_positions(state.client) do
      {:ok, positions} ->
        Enum.filter(positions, fn p ->
          p["positions"] != "0" and p["positions"] != ""
        end)

      {:error, reason} ->
        Logger.error("[Scalper.TradeExecutor] Cannot fetch positions: #{inspect(reason)}")
        []
    end
  end

  defp close_orphaned_positions(state, positions) do
    Enum.each(positions, fn pos ->
      params = %{
        "instId" => pos["instId"],
        "marginMode" => pos["marginMode"] || state.config.margin_mode,
        "positionSide" => pos["positionSide"] || state.config.position_side
      }

      case ExBlofin.Trading.close_position(state.client, params) do
        {:ok, _} ->
          Logger.info("[Scalper.TradeExecutor] Closed orphaned position: #{pos["instId"]}")

        {:error, reason} ->
          Logger.error("[Scalper.TradeExecutor] Failed to close orphan #{pos["instId"]}: #{inspect(reason)}")
      end
    end)

    clear_trade_state(state)
    state
  end

  defp resume_position(state, saved, _exchange) do
    direction = String.to_existing_atom(saved["direction"])

    position = %Position{
      inst_id: saved["inst_id"],
      direction: direction,
      side: saved["side"],
      size: saved["size"],
      entry_price: saved["entry_price"],
      order_id: saved["order_id"],
      stop_order_id: saved["stop_order_id"],
      tp_order_id: saved["tp_order_id"],
      signal_score: saved["signal_score"] || 0.0,
      opened_at: parse_datetime(saved["opened_at"]),
      max_hold_timer:
        Process.send_after(
          self(),
          {:max_hold_timeout, saved["inst_id"]},
          state.config.max_hold_time_ms
        )
    }

    %{state | position: position, status: :in_trade}
  end

  # ============================================================================
  # State Persistence
  # ============================================================================

  defp persist_trade_state(state) do
    case state.position do
      nil ->
        :ok

      pos ->
        data = %{
          "version" => 1,
          "saved_at" => DateTime.to_iso8601(DateTime.utc_now()),
          "inst_id" => pos.inst_id,
          "direction" => to_string(pos.direction),
          "side" => pos.side,
          "size" => pos.size,
          "entry_price" => pos.entry_price,
          "order_id" => pos.order_id,
          "stop_order_id" => pos.stop_order_id,
          "tp_order_id" => pos.tp_order_id,
          "signal_score" => pos.signal_score,
          "opened_at" => DateTime.to_iso8601(pos.opened_at)
        }

        tmp_file = state.state_file <> ".tmp"

        case Jason.encode(data, pretty: true) do
          {:ok, json} ->
            File.write!(tmp_file, json)
            File.rename!(tmp_file, state.state_file)

          {:error, reason} ->
            Logger.error("[Scalper.TradeExecutor] Failed to persist state: #{inspect(reason)}")
        end
    end
  end

  defp load_trade_state(state_file) do
    case File.read(state_file) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, data} -> data
          {:error, _} -> nil
        end

      {:error, _} ->
        nil
    end
  end

  defp clear_trade_state(state) do
    File.rm(state.state_file)
    state
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp format_position(nil), do: nil

  defp format_position(pos) do
    %{
      inst_id: pos.inst_id,
      direction: pos.direction,
      size: pos.size,
      entry_price: pos.entry_price,
      signal_score: pos.signal_score,
      opened_at: DateTime.to_iso8601(pos.opened_at),
      age_seconds: DateTime.diff(DateTime.utc_now(), pos.opened_at)
    }
  end

  defp parse_datetime(nil), do: DateTime.utc_now()

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      _ -> DateTime.utc_now()
    end
  end
end
