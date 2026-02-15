defmodule ExBlofin.Strategy.Scalper.ConfigTest do
  use ExUnit.Case, async: true

  alias ExBlofin.Strategy.Scalper.Config

  describe "new/1" do
    test "creates config with defaults" do
      config = Config.new()

      assert config.risk_per_trade == 0.01
      assert config.leverage == 5
      assert config.margin_mode == "isolated"
      assert config.max_daily_loss == 0.03
      assert config.max_weekly_loss == 0.05
      assert config.max_monthly_loss == 0.08
      assert config.stop_loss_pct == 0.004
      assert config.take_profit_pct == 0.006
      assert config.demo == true
      assert config.live == false
    end

    test "accepts overrides" do
      config = Config.new(risk_per_trade: 0.02, leverage: 10, watchlist: ["BTC-USDT"])

      assert config.risk_per_trade == 0.02
      assert config.leverage == 10
      assert config.watchlist == ["BTC-USDT"]
    end

    test "raises on invalid risk_per_trade" do
      assert_raise ArgumentError, ~r/risk_per_trade/, fn ->
        Config.new(risk_per_trade: 0.5)
      end
    end

    test "raises on invalid leverage" do
      assert_raise ArgumentError, ~r/leverage/, fn ->
        Config.new(leverage: 200)
      end
    end

    test "raises when weekly loss < daily loss" do
      assert_raise ArgumentError, ~r/max_weekly_loss/, fn ->
        Config.new(max_daily_loss: 0.10, max_weekly_loss: 0.05)
      end
    end

    test "raises when TP < SL (negative R:R)" do
      assert_raise ArgumentError, ~r/take_profit_pct/, fn ->
        Config.new(stop_loss_pct: 0.005, take_profit_pct: 0.004)
      end
    end

    test "raises on empty watchlist" do
      assert_raise ArgumentError, ~r/watchlist/, fn ->
        Config.new(watchlist: [])
      end
    end

    test "raises when both live and demo" do
      assert_raise ArgumentError, ~r/live and demo/, fn ->
        Config.new(live: true, demo: true)
      end
    end
  end

  describe "risk_reward_ratio/1" do
    test "calculates correct R:R" do
      config = Config.new(take_profit_pct: 0.006, stop_loss_pct: 0.004)
      assert Config.risk_reward_ratio(config) == 1.5
    end
  end

  describe "break_even_win_rate/1" do
    test "calculates correct break-even rate" do
      config = Config.new(take_profit_pct: 0.006, stop_loss_pct: 0.004)
      assert Config.break_even_win_rate(config) == 0.4
    end

    test "50% for symmetric R:R" do
      config = Config.new(take_profit_pct: 0.005, stop_loss_pct: 0.005)
      assert Config.break_even_win_rate(config) == 0.5
    end
  end

  describe "state_dir/1" do
    test "expands home directory" do
      config = Config.new(state_dir: "~/.scalper")
      dir = Config.state_dir(config)
      assert String.starts_with?(dir, "/")
      refute String.contains?(dir, "~")
    end
  end
end
