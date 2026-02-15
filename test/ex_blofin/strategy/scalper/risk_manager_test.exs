defmodule ExBlofin.Strategy.Scalper.RiskManagerTest do
  use ExUnit.Case, async: true

  alias ExBlofin.Strategy.Scalper.Config
  alias ExBlofin.Strategy.Scalper.RiskManager

  setup do
    state_dir = Path.join(System.tmp_dir!(), "scalper_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(state_dir)

    config =
      Config.new(
        state_dir: state_dir,
        risk_per_trade: 0.01,
        max_daily_loss: 0.03,
        max_weekly_loss: 0.05,
        max_monthly_loss: 0.08,
        max_consecutive_losses: 3,
        cooldown_after_loss_ms: 100,
        consecutive_loss_pause_ms: 200
      )

    {:ok, pid} =
      RiskManager.start_link(
        config: config,
        starting_balance: 10_000.0
      )

    on_exit(fn ->
      File.rm_rf!(state_dir)
    end)

    %{pid: pid, config: config, state_dir: state_dir}
  end

  describe "can_trade?/1" do
    test "allows trading when no limits reached", %{pid: pid} do
      assert {:ok, max_loss} = RiskManager.can_trade?(pid)
      assert max_loss == 100.0
    end
  end

  describe "record_trade/2" do
    test "records a winning trade", %{pid: pid} do
      assert :ok = RiskManager.record_trade(pid, 50.0)

      status = RiskManager.get_status(pid)
      assert status.daily.realized_pnl == 50.0
      assert status.daily.trade_count == 1
      assert status.daily.win_rate == 100.0
    end

    test "records a losing trade", %{pid: pid} do
      assert :ok = RiskManager.record_trade(pid, -80.0)

      status = RiskManager.get_status(pid)
      assert status.daily.realized_pnl == -80.0
      assert status.daily.trade_count == 1
      assert status.daily.win_rate == 0.0
    end

    test "tracks consecutive losses", %{pid: pid} do
      RiskManager.record_trade(pid, -50.0)
      # Wait for cooldown to expire
      Process.sleep(150)

      RiskManager.record_trade(pid, -50.0)
      Process.sleep(150)

      status = RiskManager.get_status(pid)
      assert status.daily.consecutive_losses == 2
    end

    test "resets consecutive losses on win", %{pid: pid} do
      RiskManager.record_trade(pid, -50.0)
      Process.sleep(150)

      RiskManager.record_trade(pid, 50.0)

      status = RiskManager.get_status(pid)
      assert status.daily.consecutive_losses == 0
    end

    test "trips daily circuit breaker", %{pid: pid} do
      # Daily limit is 3% of 10,000 = $300
      RiskManager.record_trade(pid, -150.0)
      Process.sleep(150)
      RiskManager.record_trade(pid, -160.0)
      Process.sleep(150)

      assert {:error, reason} = RiskManager.can_trade?(pid)
      assert reason =~ "daily_limit_reached"
    end
  end

  describe "get_balance/1" do
    test "returns current balance after trades", %{pid: pid} do
      assert RiskManager.get_balance(pid) == 10_000.0

      RiskManager.record_trade(pid, -100.0)
      assert RiskManager.get_balance(pid) == 9_900.0

      RiskManager.record_trade(pid, 50.0)
      assert RiskManager.get_balance(pid) == 9_950.0
    end
  end

  describe "get_status/1" do
    test "returns comprehensive status", %{pid: pid} do
      status = RiskManager.get_status(pid)

      assert status.status == :active
      assert status.balance == 10_000.0
      assert status.risk_reward_ratio == 1.5
      assert status.break_even_win_rate == 0.4
      assert is_map(status.daily)
      assert is_map(status.weekly)
      assert is_map(status.monthly)
    end
  end

  describe "state persistence" do
    test "persists state to disk after trade", %{pid: pid, state_dir: state_dir} do
      RiskManager.record_trade(pid, -75.0)

      state_file = Path.join(state_dir, "risk_state.json")
      assert File.exists?(state_file)

      {:ok, contents} = File.read(state_file)
      {:ok, data} = Jason.decode(contents)

      assert data["version"] == 1
      assert data["daily"]["realized_pnl"] == -75.0
      assert data["daily"]["trade_count"] == 1
    end

    test "loads persisted state on restart", %{config: config, state_dir: state_dir} do
      {:ok, pid1} = RiskManager.start_link(config: config, starting_balance: 10_000.0)
      RiskManager.record_trade(pid1, -100.0)
      GenServer.stop(pid1)

      {:ok, pid2} = RiskManager.start_link(config: config, starting_balance: 10_000.0)
      status = RiskManager.get_status(pid2)

      assert status.daily.realized_pnl == -100.0
      assert status.daily.trade_count == 1

      GenServer.stop(pid2)
    end
  end

  describe "reset/1" do
    test "clears all circuit breakers", %{pid: pid} do
      RiskManager.record_trade(pid, -150.0)
      Process.sleep(150)
      RiskManager.record_trade(pid, -160.0)
      Process.sleep(250)

      assert {:error, _} = RiskManager.can_trade?(pid)

      RiskManager.reset(pid)

      assert {:ok, _} = RiskManager.can_trade?(pid)
    end
  end
end
