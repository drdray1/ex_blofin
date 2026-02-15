defmodule ExBlofin.Strategy.Scalper.Supervisor do
  @moduledoc """
  Supervision tree for the liquidity scalping strategy.

  ## Architecture

      ScalperSupervisor (one_for_one)
      ├── DataSupervisor (one_for_one)
      │   ├── PublicConnection (WebSocket)
      │   └── BookManager
      └── TradingSupervisor (rest_for_one)
          ├── RiskManager        ← starts first, loads persisted state
          ├── WallDetector       ← depends on BookManager (separate tree)
          ├── WatchlistScanner   ← depends on WallDetector
          └── TradeExecutor      ← depends on RiskManager + Scanner

  ### Restart Strategy

  - **DataSupervisor** uses `one_for_one`: WebSocket and BookManager
    are independent. If the WebSocket crashes, BookManager keeps running
    (it just stops getting updates). If BookManager crashes, it restarts
    and re-subscribes.

  - **TradingSupervisor** uses `rest_for_one`: If RiskManager crashes,
    everything below it restarts too (can't trade without risk limits).
    If TradeExecutor crashes, only it restarts (risk state preserved).

  ## Starting the Bot

      config = ExBlofin.Strategy.Scalper.Config.new(
        watchlist: ["BTC-USDT", "ETH-USDT"],
        leverage: 5,
        demo: true
      )

      client = ExBlofin.Client.new("key", "secret", "pass", demo: true)

      ExBlofin.Strategy.Scalper.Supervisor.start_link(
        config: config,
        client: client,
        starting_balance: 10_000.0
      )
  """

  use Supervisor

  require Logger

  alias ExBlofin.Strategy.Scalper.Config

  @doc """
  Starts the scalper supervision tree.

  ## Options

    - `:config` - `%Config{}` struct (required)
    - `:client` - Authenticated API client (required)
    - `:starting_balance` - Initial account balance (required)
    - `:name` - Optional supervisor name
  """
  def start_link(opts) do
    config = Keyword.fetch!(opts, :config)
    client = Keyword.fetch!(opts, :client)
    balance = Keyword.fetch!(opts, :starting_balance)
    name = Keyword.get(opts, :name, __MODULE__)

    if config.live and not config.demo do
      Logger.warning("[Scalper] Starting in LIVE mode — real money at risk")
    else
      Logger.info("[Scalper] Starting in DEMO mode")
    end

    Supervisor.start_link(
      __MODULE__,
      {config, client, balance},
      name: name
    )
  end

  @impl Supervisor
  def init({config, client, balance}) do
    children = [
      {Task,
       fn ->
         start_strategy(config, client, balance)
       end}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # ============================================================================
  # Strategy Bootstrap
  # ============================================================================

  defp start_strategy(config, client, balance) do
    Logger.info("[Scalper] Bootstrapping strategy components...")

    # 1. Start WebSocket connection
    {:ok, ws_pid} =
      ExBlofin.WebSocket.PublicConnection.start_link(
        demo: config.demo,
        name: Scalper.PublicWS
      )

    # Give WS a moment to connect
    Process.sleep(1_000)

    # 2. Start BookManager
    {:ok, book_mgr} =
      ExBlofin.Strategy.Scalper.BookManager.start_link(
        ws_pid: ws_pid,
        instruments: config.watchlist,
        name: Scalper.BookManager
      )

    # 3. Start RiskManager (loads persisted state)
    {:ok, risk_mgr} =
      ExBlofin.Strategy.Scalper.RiskManager.start_link(
        config: config,
        starting_balance: balance,
        name: Scalper.RiskManager
      )

    # 4. Start WallDetector
    {:ok, wall_det} =
      ExBlofin.Strategy.Scalper.WallDetector.start_link(
        config: config,
        book_manager: book_mgr,
        ws_pid: ws_pid,
        name: Scalper.WallDetector
      )

    # 5. Start WatchlistScanner
    {:ok, scanner} =
      ExBlofin.Strategy.Scalper.WatchlistScanner.start_link(
        config: config,
        wall_detector: wall_det,
        ws_pid: ws_pid,
        name: Scalper.WatchlistScanner
      )

    # 6. Start TradeExecutor
    {:ok, executor} =
      ExBlofin.Strategy.Scalper.TradeExecutor.start_link(
        config: config,
        client: client,
        risk_manager: risk_mgr,
        scanner: scanner,
        name: Scalper.TradeExecutor
      )

    Logger.info("[Scalper] All components started successfully")
    Logger.info("[Scalper] WebSocket: #{inspect(ws_pid)}")
    Logger.info("[Scalper] BookManager: #{inspect(book_mgr)}")
    Logger.info("[Scalper] RiskManager: #{inspect(risk_mgr)}")
    Logger.info("[Scalper] WallDetector: #{inspect(wall_det)}")
    Logger.info("[Scalper] Scanner: #{inspect(scanner)}")
    Logger.info("[Scalper] Executor: #{inspect(executor)}")

    # Keep the task alive
    Process.sleep(:infinity)
  end
end
