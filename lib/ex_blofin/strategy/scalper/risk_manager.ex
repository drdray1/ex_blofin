defmodule ExBlofin.Strategy.Scalper.RiskManager do
  @moduledoc """
  Manages risk limits and circuit breakers for the scalping strategy.

  Tracks realized P&L across daily, weekly, and monthly periods.
  Persists state to disk so circuit breakers survive restarts.
  A restart cannot erase losses or bypass tripped breakers.

  ## Circuit Breaker Levels

    - **Daily** - Resets at midnight UTC
    - **Weekly** - Resets Monday 00:00 UTC
    - **Monthly** - Resets 1st of month 00:00 UTC

  ## State Persistence

  State is written to `{state_dir}/risk_state.json` atomically
  (write to tmp file, then rename) after every trade to prevent
  corruption from crashes mid-write.
  """

  use GenServer

  require Logger

  alias ExBlofin.Strategy.Scalper.Config

  @type period :: :daily | :weekly | :monthly

  defmodule PeriodState do
    @moduledoc false
    defstruct [
      :start_date,
      :starting_balance,
      realized_pnl: 0.0,
      trade_count: 0,
      win_count: 0,
      loss_count: 0,
      consecutive_losses: 0
    ]

    @type t :: %__MODULE__{
            start_date: Date.t(),
            starting_balance: float(),
            realized_pnl: float(),
            trade_count: non_neg_integer(),
            win_count: non_neg_integer(),
            loss_count: non_neg_integer(),
            consecutive_losses: non_neg_integer()
          }
  end

  defmodule State do
    @moduledoc false
    defstruct [
      :config,
      :state_file,
      :daily,
      :weekly,
      :monthly,
      status: :active,
      paused_until: nil,
      pause_reason: nil
    ]

    @type t :: %__MODULE__{
            config: Config.t(),
            state_file: String.t(),
            daily: PeriodState.t(),
            weekly: PeriodState.t(),
            monthly: PeriodState.t(),
            status: :active | :paused | :stopped,
            paused_until: DateTime.t() | nil,
            pause_reason: String.t() | nil
          }
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc "Starts the RiskManager process."
  def start_link(opts) do
    config = Keyword.fetch!(opts, :config)
    balance = Keyword.fetch!(opts, :starting_balance)
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, {config, balance}, gen_opts)
  end

  @doc """
  Checks if a new trade is allowed under current risk limits.

  Returns `{:ok, max_loss_amount}` if trading is permitted,
  or `{:error, reason}` if a circuit breaker is active.
  """
  @spec can_trade?(GenServer.server()) :: {:ok, float()} | {:error, String.t()}
  def can_trade?(server) do
    GenServer.call(server, :can_trade?)
  end

  @doc """
  Records a completed trade result. Updates P&L and checks circuit breakers.

  `pnl` is the realized profit/loss amount (negative for losses).
  """
  @spec record_trade(GenServer.server(), float()) :: :ok
  def record_trade(server, pnl) when is_number(pnl) do
    GenServer.call(server, {:record_trade, pnl})
  end

  @doc "Returns current risk state summary."
  @spec get_status(GenServer.server()) :: map()
  def get_status(server) do
    GenServer.call(server, :get_status)
  end

  @doc "Returns the current account balance."
  @spec get_balance(GenServer.server()) :: float()
  def get_balance(server) do
    GenServer.call(server, :get_balance)
  end

  @doc "Resets all circuit breakers. Use with caution."
  @spec reset(GenServer.server()) :: :ok
  def reset(server) do
    GenServer.call(server, :reset)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init({config, starting_balance}) do
    state_dir = Config.state_dir(config)
    File.mkdir_p!(state_dir)
    state_file = Path.join(state_dir, "risk_state.json")

    state =
      case load_state(state_file, config, starting_balance) do
        {:ok, loaded} ->
          loaded

        :fresh ->
          today = Date.utc_today()

          %State{
            config: config,
            state_file: state_file,
            daily: new_period(today, starting_balance),
            weekly: new_period(week_start(today), starting_balance),
            monthly: new_period(month_start(today), starting_balance)
          }
      end

    state = maybe_roll_periods(state, starting_balance)
    state = check_pause_expiry(state)

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:can_trade?, _from, state) do
    state = maybe_roll_periods(state, current_balance(state))
    state = check_pause_expiry(state)

    case check_all_limits(state) do
      :ok ->
        max_loss = state.daily.starting_balance * state.config.risk_per_trade
        {:reply, {:ok, max_loss}, state}

      {:error, reason} = err ->
        {:reply, err, %{state | status: :stopped, pause_reason: reason}}
    end
  end

  @impl GenServer
  def handle_call({:record_trade, pnl}, _from, state) do
    is_win = pnl > 0

    state =
      state
      |> update_period(:daily, pnl, is_win)
      |> update_period(:weekly, pnl, is_win)
      |> update_period(:monthly, pnl, is_win)

    state = maybe_apply_cooldown(state, pnl)
    persist_state(state)

    Logger.info(
      "[Scalper.RiskManager] Trade recorded: #{format_pnl(pnl)} | " <>
        "Daily: #{format_pnl(state.daily.realized_pnl)} | " <>
        "Consecutive losses: #{state.daily.consecutive_losses}"
    )

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    status = %{
      status: state.status,
      pause_reason: state.pause_reason,
      paused_until: state.paused_until,
      daily: period_summary(state.daily, state.config.max_daily_loss),
      weekly: period_summary(state.weekly, state.config.max_weekly_loss),
      monthly: period_summary(state.monthly, state.config.max_monthly_loss),
      balance: current_balance(state),
      risk_reward_ratio: Config.risk_reward_ratio(state.config),
      break_even_win_rate: Config.break_even_win_rate(state.config)
    }

    {:reply, status, state}
  end

  @impl GenServer
  def handle_call(:get_balance, _from, state) do
    {:reply, current_balance(state), state}
  end

  @impl GenServer
  def handle_call(:reset, _from, state) do
    balance = current_balance(state)
    today = Date.utc_today()

    state = %{
      state
      | daily: new_period(today, balance),
        weekly: new_period(week_start(today), balance),
        monthly: new_period(month_start(today), balance),
        status: :active,
        paused_until: nil,
        pause_reason: nil
    }

    persist_state(state)
    Logger.info("[Scalper.RiskManager] All circuit breakers reset")
    {:reply, :ok, state}
  end

  # ============================================================================
  # Period Management
  # ============================================================================

  defp new_period(start_date, balance) do
    %PeriodState{start_date: start_date, starting_balance: balance}
  end

  defp update_period(state, period, pnl, is_win) do
    ps = Map.get(state, period)

    consecutive_losses =
      if is_win, do: 0, else: ps.consecutive_losses + 1

    updated = %{
      ps
      | realized_pnl: ps.realized_pnl + pnl,
        trade_count: ps.trade_count + 1,
        win_count: if(is_win, do: ps.win_count + 1, else: ps.win_count),
        loss_count: if(is_win, do: ps.loss_count, else: ps.loss_count + 1),
        consecutive_losses: consecutive_losses
    }

    Map.put(state, period, updated)
  end

  defp maybe_roll_periods(state, balance) do
    today = Date.utc_today()

    state
    |> maybe_roll_period(:daily, today, balance)
    |> maybe_roll_period(:weekly, week_start(today), balance)
    |> maybe_roll_period(:monthly, month_start(today), balance)
  end

  defp maybe_roll_period(state, period, current_start, balance) do
    ps = Map.get(state, period)

    if Date.compare(ps.start_date, current_start) == :lt do
      Logger.info("[Scalper.RiskManager] Rolling #{period} period (#{ps.start_date} -> #{current_start})")

      state
      |> Map.put(period, new_period(current_start, balance))
      |> clear_period_pause(period)
    else
      state
    end
  end

  defp clear_period_pause(state, period) do
    reason_prefix = "#{period}_"

    if state.pause_reason && String.starts_with?(state.pause_reason, reason_prefix) do
      %{state | status: :active, paused_until: nil, pause_reason: nil}
    else
      state
    end
  end

  # ============================================================================
  # Limit Checks
  # ============================================================================

  defp check_all_limits(state) do
    checks = [
      check_period_limit(state.daily, state.config.max_daily_loss, "daily"),
      check_period_limit(state.weekly, state.config.max_weekly_loss, "weekly"),
      check_period_limit(state.monthly, state.config.max_monthly_loss, "monthly"),
      check_consecutive_losses(state),
      check_pause(state)
    ]

    case Enum.find(checks, fn result -> result != :ok end) do
      nil -> :ok
      error -> error
    end
  end

  defp check_period_limit(period_state, max_loss_pct, label) do
    max_loss = period_state.starting_balance * max_loss_pct
    current_loss = abs(min(period_state.realized_pnl, 0.0))

    if current_loss >= max_loss do
      {:error, "#{label}_limit_reached: lost $#{Float.round(current_loss, 2)} of $#{Float.round(max_loss, 2)} #{label} limit"}
    else
      :ok
    end
  end

  defp check_consecutive_losses(state) do
    if state.daily.consecutive_losses >= state.config.max_consecutive_losses do
      {:error, "consecutive_losses: #{state.daily.consecutive_losses} consecutive losses"}
    else
      :ok
    end
  end

  defp check_pause(state) do
    if state.status == :paused do
      {:error, "paused: #{state.pause_reason}"}
    else
      :ok
    end
  end

  defp check_pause_expiry(state) do
    case state.paused_until do
      nil ->
        state

      until ->
        if DateTime.compare(DateTime.utc_now(), until) != :lt do
          Logger.info("[Scalper.RiskManager] Pause expired, resuming")
          %{state | status: :active, paused_until: nil, pause_reason: nil}
        else
          state
        end
    end
  end

  # ============================================================================
  # Cooldowns
  # ============================================================================

  defp maybe_apply_cooldown(state, pnl) when pnl >= 0, do: state

  defp maybe_apply_cooldown(state, _pnl) do
    consecutive = state.daily.consecutive_losses

    cond do
      consecutive >= state.config.max_consecutive_losses ->
        pause_ms = state.config.consecutive_loss_pause_ms
        until = DateTime.add(DateTime.utc_now(), pause_ms, :millisecond)

        Logger.warning(
          "[Scalper.RiskManager] #{consecutive} consecutive losses, pausing until #{until}"
        )

        %{
          state
          | status: :paused,
            paused_until: until,
            pause_reason: "consecutive_losses_cooldown"
        }

      true ->
        cooldown_ms = state.config.cooldown_after_loss_ms
        until = DateTime.add(DateTime.utc_now(), cooldown_ms, :millisecond)

        %{
          state
          | status: :paused,
            paused_until: until,
            pause_reason: "loss_cooldown"
        }
    end
  end

  # ============================================================================
  # State Persistence
  # ============================================================================

  defp persist_state(state) do
    data = %{
      "version" => 1,
      "saved_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "status" => to_string(state.status),
      "paused_until" => if(state.paused_until, do: DateTime.to_iso8601(state.paused_until)),
      "pause_reason" => state.pause_reason,
      "daily" => serialize_period(state.daily),
      "weekly" => serialize_period(state.weekly),
      "monthly" => serialize_period(state.monthly)
    }

    tmp_file = state.state_file <> ".tmp"

    case Jason.encode(data, pretty: true) do
      {:ok, json} ->
        File.write!(tmp_file, json)
        File.rename!(tmp_file, state.state_file)

      {:error, reason} ->
        Logger.error("[Scalper.RiskManager] Failed to persist state: #{inspect(reason)}")
    end
  end

  defp load_state(state_file, config, starting_balance) do
    case File.read(state_file) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, data} ->
            state = deserialize_state(data, config, state_file, starting_balance)
            Logger.info("[Scalper.RiskManager] Loaded state from #{state_file}")
            {:ok, state}

          {:error, _} ->
            Logger.warning("[Scalper.RiskManager] Corrupt state file, starting fresh")
            :fresh
        end

      {:error, :enoent} ->
        :fresh

      {:error, reason} ->
        Logger.warning("[Scalper.RiskManager] Cannot read state: #{inspect(reason)}, starting fresh")
        :fresh
    end
  end

  defp serialize_period(ps) do
    %{
      "start_date" => Date.to_iso8601(ps.start_date),
      "starting_balance" => ps.starting_balance,
      "realized_pnl" => ps.realized_pnl,
      "trade_count" => ps.trade_count,
      "win_count" => ps.win_count,
      "loss_count" => ps.loss_count,
      "consecutive_losses" => ps.consecutive_losses
    }
  end

  defp deserialize_period(data, fallback_balance) do
    %PeriodState{
      start_date: Date.from_iso8601!(data["start_date"]),
      starting_balance: data["starting_balance"] || fallback_balance,
      realized_pnl: data["realized_pnl"] || 0.0,
      trade_count: data["trade_count"] || 0,
      win_count: data["win_count"] || 0,
      loss_count: data["loss_count"] || 0,
      consecutive_losses: data["consecutive_losses"] || 0
    }
  end

  defp deserialize_state(data, config, state_file, fallback_balance) do
    paused_until =
      case data["paused_until"] do
        nil -> nil
        str -> DateTime.from_iso8601(str) |> elem(1)
      end

    %State{
      config: config,
      state_file: state_file,
      daily: deserialize_period(data["daily"], fallback_balance),
      weekly: deserialize_period(data["weekly"], fallback_balance),
      monthly: deserialize_period(data["monthly"], fallback_balance),
      status: String.to_existing_atom(data["status"] || "active"),
      paused_until: paused_until,
      pause_reason: data["pause_reason"]
    }
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp current_balance(state) do
    state.daily.starting_balance + state.daily.realized_pnl
  end

  defp week_start(date) do
    day_of_week = Date.day_of_week(date)
    Date.add(date, -(day_of_week - 1))
  end

  defp month_start(date) do
    %Date{date | day: 1}
  end

  defp format_pnl(pnl) when pnl >= 0, do: "+$#{Float.round(pnl, 2)}"
  defp format_pnl(pnl), do: "-$#{Float.round(abs(pnl), 2)}"

  defp period_summary(ps, max_loss_pct) do
    max_loss = ps.starting_balance * max_loss_pct
    current_loss = abs(min(ps.realized_pnl, 0.0))

    win_rate =
      if ps.trade_count > 0,
        do: Float.round(ps.win_count / ps.trade_count * 100, 1),
        else: 0.0

    %{
      start_date: ps.start_date,
      starting_balance: ps.starting_balance,
      realized_pnl: Float.round(ps.realized_pnl, 2),
      trade_count: ps.trade_count,
      win_rate: win_rate,
      consecutive_losses: ps.consecutive_losses,
      loss_limit: Float.round(max_loss, 2),
      loss_used_pct: if(max_loss > 0, do: Float.round(current_loss / max_loss * 100, 1), else: 0.0)
    }
  end
end
