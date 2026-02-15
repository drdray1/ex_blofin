defmodule ExBlofin.Strategy.Scalper do
  @moduledoc """
  Liquidity scalping strategy for BloFin futures.

  Detects order book walls (statistically anomalous liquidity levels),
  validates them through persistence and absorption analysis, then
  scalps the bounce with positive risk-to-reward positioning.

  ## Quick Start

      # Demo mode (default — no real money)
      ExBlofin.Strategy.Scalper.start(
        api_key: "key",
        secret_key: "secret",
        passphrase: "pass",
        starting_balance: 10_000.0
      )

      # With custom config
      ExBlofin.Strategy.Scalper.start(
        api_key: "key",
        secret_key: "secret",
        passphrase: "pass",
        starting_balance: 10_000.0,
        config: [
          watchlist: ["BTC-USDT", "ETH-USDT", "SOL-USDT"],
          leverage: 5,
          risk_per_trade: 0.01,
          max_daily_loss: 0.03
        ]
      )

  ## Architecture

  See `ExBlofin.Strategy.Scalper.Supervisor` for the full supervision tree.

  ## Components

    - `Config` - All tunable parameters with validation
    - `RiskManager` - Circuit breakers, P&L tracking, persisted state
    - `BookManager` - Real-time multi-instrument order book state
    - `WallDetector` - Statistical wall detection and absorption validation
    - `WatchlistScanner` - Ranks instruments, selects best setup
    - `TradeExecutor` - Order execution, position management, reconciliation
    - `Supervisor` - OTP supervision tree with proper restart strategies
  """

  alias ExBlofin.Strategy.Scalper.Config
  alias ExBlofin.Strategy.Scalper.Supervisor, as: ScalperSupervisor

  @doc """
  Starts the liquidity scalping bot.

  ## Options

    - `:api_key` - BloFin API key (required)
    - `:secret_key` - BloFin secret key (required)
    - `:passphrase` - BloFin passphrase (required)
    - `:starting_balance` - Account balance in USDT (required)
    - `:config` - Keyword list of config overrides (optional)
    - `:live` - Set to `true` for live trading (default: false)

  ## Examples

      # Demo mode
      {:ok, pid} = ExBlofin.Strategy.Scalper.start(
        api_key: "key",
        secret_key: "secret",
        passphrase: "pass",
        starting_balance: 10_000.0
      )

      # Live mode (requires explicit opt-in)
      {:ok, pid} = ExBlofin.Strategy.Scalper.start(
        api_key: "key",
        secret_key: "secret",
        passphrase: "pass",
        starting_balance: 10_000.0,
        live: true,
        config: [demo: false, live: true]
      )
  """
  @spec start(keyword()) :: {:ok, pid()} | {:error, term()}
  def start(opts) do
    api_key = Keyword.fetch!(opts, :api_key)
    secret_key = Keyword.fetch!(opts, :secret_key)
    passphrase = Keyword.fetch!(opts, :passphrase)
    balance = Keyword.fetch!(opts, :starting_balance)

    live = Keyword.get(opts, :live, false)
    config_overrides = Keyword.get(opts, :config, [])

    config_opts =
      if live do
        Keyword.merge([demo: false, live: true], config_overrides)
      else
        Keyword.merge([demo: true, live: false], config_overrides)
      end

    config = Config.new(config_opts)
    demo = not live

    client = ExBlofin.Client.new(api_key, secret_key, passphrase, demo: demo)

    ScalperSupervisor.start_link(
      config: config,
      client: client,
      starting_balance: balance
    )
  end

  @doc """
  Stops the running scalper bot.
  """
  @spec stop(pid() | atom()) :: :ok
  def stop(pid \\ ExBlofin.Strategy.Scalper.Supervisor) do
    Supervisor.stop(pid, :normal)
  end

  @doc """
  Returns the current status of all components.
  """
  @spec status() :: map()
  def status do
    %{
      risk: safe_call(Scalper.RiskManager, &ExBlofin.Strategy.Scalper.RiskManager.get_status/1),
      executor: safe_call(Scalper.TradeExecutor, &ExBlofin.Strategy.Scalper.TradeExecutor.get_status/1),
      rankings: safe_call(Scalper.WatchlistScanner, &ExBlofin.Strategy.Scalper.WatchlistScanner.get_rankings/1),
      walls: safe_call(Scalper.WallDetector, &ExBlofin.Strategy.Scalper.WallDetector.get_all_walls/1)
    }
  end

  @doc """
  Emergency close — immediately closes any open position.
  """
  @spec emergency_close() :: :ok | {:error, term()}
  def emergency_close do
    ExBlofin.Strategy.Scalper.TradeExecutor.emergency_close(Scalper.TradeExecutor)
  end

  defp safe_call(name, fun) do
    case Process.whereis(name) do
      nil -> {:error, :not_running}
      pid -> fun.(pid)
    end
  end
end
