defmodule ExBlofin.Strategy.Scalper.WatchlistScannerTest do
  use ExUnit.Case, async: true

  alias ExBlofin.Strategy.Scalper.WatchlistScanner.InstrumentScore

  describe "InstrumentScore struct" do
    test "creates with defaults" do
      score = %InstrumentScore{
        inst_id: "BTC-USDT",
        score: 85.0,
        signal: nil,
        last_price: 50_000.0,
        spread_pct: 0.0001,
        volume_24h: 500_000_000.0,
        reason: "qualified"
      }

      assert score.inst_id == "BTC-USDT"
      assert score.score == 85.0
      assert score.reason == "qualified"
    end
  end
end
