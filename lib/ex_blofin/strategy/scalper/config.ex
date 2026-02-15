defmodule ExBlofin.Strategy.Scalper.Config do
  @moduledoc """
  Configuration for the liquidity scalping strategy.

  Defines all tunable parameters for risk management, wall detection,
  trade execution, and watchlist scanning.

  ## Usage

      config = ExBlofin.Strategy.Scalper.Config.new()
      config = ExBlofin.Strategy.Scalper.Config.new(risk_per_trade: 0.02, leverage: 10)

  ## Parameter Groups

    - **Risk** - Per-trade risk, leverage, margin mode
    - **Circuit Breakers** - Daily/weekly/monthly loss limits
    - **Trade** - Stop loss, take profit, hold time, cooldowns
    - **Wall Detection** - Thresholds for identifying and validating walls
    - **Watchlist** - Instruments to scan and scoring thresholds
  """

  @type t :: %__MODULE__{
          # Risk
          risk_per_trade: float(),
          leverage: pos_integer(),
          margin_mode: String.t(),
          position_side: String.t(),

          # Circuit breakers
          max_daily_loss: float(),
          max_weekly_loss: float(),
          max_monthly_loss: float(),

          # Trade execution
          stop_loss_pct: float(),
          take_profit_pct: float(),
          max_hold_time_ms: pos_integer(),
          cooldown_after_loss_ms: pos_integer(),
          max_consecutive_losses: pos_integer(),
          consecutive_loss_pause_ms: pos_integer(),
          max_open_positions: pos_integer(),

          # Wall detection
          wall_min_multiplier: float(),
          wall_persistence_ms: pos_integer(),
          wall_min_absorption_events: pos_integer(),
          wall_max_distance_pct: float(),
          round_number_bonus: float(),

          # Watchlist & scoring
          watchlist: [String.t()],
          min_signal_score: float(),
          min_spread_pct: float(),
          max_spread_pct: float(),
          min_volume_24h: float(),
          scan_interval_ms: pos_integer(),

          # Persistence
          state_dir: String.t(),

          # Mode
          demo: boolean(),
          live: boolean()
        }

  defstruct [
    # Risk — 1% of account per trade
    risk_per_trade: 0.01,
    leverage: 5,
    margin_mode: "isolated",
    position_side: "net",

    # Circuit breakers — daily 3%, weekly 5%, monthly 8%
    max_daily_loss: 0.03,
    max_weekly_loss: 0.05,
    max_monthly_loss: 0.08,

    # Trade execution — 1.5:1 R:R
    stop_loss_pct: 0.004,
    take_profit_pct: 0.006,
    max_hold_time_ms: 120_000,
    cooldown_after_loss_ms: 30_000,
    max_consecutive_losses: 3,
    consecutive_loss_pause_ms: 300_000,
    max_open_positions: 1,

    # Wall detection
    wall_min_multiplier: 10.0,
    wall_persistence_ms: 5_000,
    wall_min_absorption_events: 3,
    wall_max_distance_pct: 0.005,
    round_number_bonus: 5.0,

    # Watchlist & scoring
    watchlist: ["BTC-USDT", "ETH-USDT", "SOL-USDT"],
    min_signal_score: 70.0,
    min_spread_pct: 0.0,
    max_spread_pct: 0.001,
    min_volume_24h: 1_000_000.0,
    scan_interval_ms: 1_000,

    # Persistence
    state_dir: "~/.scalper",

    # Mode — demo by default, live requires explicit opt-in
    demo: true,
    live: false
  ]

  @doc """
  Creates a new config with optional overrides.

  ## Examples

      config = Config.new()
      config = Config.new(risk_per_trade: 0.02, leverage: 10, watchlist: ["BTC-USDT"])
  """
  @spec new(keyword()) :: t()
  def new(overrides \\ []) do
    struct!(__MODULE__, overrides)
    |> validate!()
  end

  @doc """
  Validates config values and raises on invalid configuration.
  """
  @spec validate!(t()) :: t()
  def validate!(%__MODULE__{} = config) do
    validations = [
      {config.risk_per_trade > 0 and config.risk_per_trade <= 0.1,
       "risk_per_trade must be between 0 and 0.1 (10%)"},
      {config.leverage >= 1 and config.leverage <= 125,
       "leverage must be between 1 and 125"},
      {config.margin_mode in ["isolated", "cross"],
       "margin_mode must be 'isolated' or 'cross'"},
      {config.max_daily_loss > 0 and config.max_daily_loss <= 1.0,
       "max_daily_loss must be between 0 and 1.0"},
      {config.max_weekly_loss >= config.max_daily_loss,
       "max_weekly_loss must be >= max_daily_loss"},
      {config.max_monthly_loss >= config.max_weekly_loss,
       "max_monthly_loss must be >= max_weekly_loss"},
      {config.stop_loss_pct > 0, "stop_loss_pct must be positive"},
      {config.take_profit_pct > 0, "take_profit_pct must be positive"},
      {config.take_profit_pct >= config.stop_loss_pct,
       "take_profit_pct should be >= stop_loss_pct for positive R:R"},
      {config.wall_min_multiplier >= 2.0,
       "wall_min_multiplier must be >= 2.0"},
      {config.watchlist != [], "watchlist cannot be empty"},
      {config.min_signal_score > 0 and config.min_signal_score <= 100,
       "min_signal_score must be between 0 and 100"},
      {not config.live or not config.demo,
       "cannot be both live and demo mode"}
    ]

    errors =
      validations
      |> Enum.reject(fn {valid?, _msg} -> valid? end)
      |> Enum.map(fn {_valid?, msg} -> msg end)

    case errors do
      [] -> config
      errors -> raise ArgumentError, "Invalid scalper config: #{Enum.join(errors, "; ")}"
    end
  end

  @doc """
  Returns the expanded state directory path.
  """
  @spec state_dir(t()) :: String.t()
  def state_dir(%__MODULE__{state_dir: dir}) do
    Path.expand(dir)
  end

  @doc """
  Returns the risk-to-reward ratio.
  """
  @spec risk_reward_ratio(t()) :: float()
  def risk_reward_ratio(%__MODULE__{take_profit_pct: tp, stop_loss_pct: sl}) do
    tp / sl
  end

  @doc """
  Returns the break-even win rate needed for profitability.
  """
  @spec break_even_win_rate(t()) :: float()
  def break_even_win_rate(%__MODULE__{take_profit_pct: tp, stop_loss_pct: sl}) do
    sl / (tp + sl)
  end
end
