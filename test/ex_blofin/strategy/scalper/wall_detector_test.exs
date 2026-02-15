defmodule ExBlofin.Strategy.Scalper.WallDetectorTest do
  use ExUnit.Case, async: true

  alias ExBlofin.Strategy.Scalper.Config
  alias ExBlofin.Strategy.Scalper.BookManager.BookState
  alias ExBlofin.Strategy.Scalper.WallDetector

  @config Config.new(
            wall_min_multiplier: 10.0,
            wall_persistence_ms: 5_000,
            wall_min_absorption_events: 3,
            wall_max_distance_pct: 0.005,
            min_signal_score: 70.0
          )

  describe "detect_walls/4" do
    test "detects a bid wall" do
      book = %BookState{
        inst_id: "BTC-USDT",
        bids: [
          ["50000.0", "2.0"],
          ["49999.0", "1.5"],
          ["49998.0", "1.0"],
          ["49997.0", "50.0"],
          ["49996.0", "2.5"],
          ["49995.0", "1.8"]
        ],
        asks: [
          ["50001.0", "1.0"],
          ["50002.0", "1.5"]
        ],
        ts: "1234567890"
      }

      now = System.monotonic_time(:millisecond)
      walls = WallDetector.detect_walls(book, "BTC-USDT", @config, now)

      bid_walls = Enum.filter(walls, fn w -> w.side == :bid end)
      assert length(bid_walls) == 1

      wall = hd(bid_walls)
      assert wall.price == 49997.0
      assert wall.size == 50.0
      assert wall.multiplier > 10.0
      assert wall.inst_id == "BTC-USDT"
    end

    test "detects an ask wall" do
      book = %BookState{
        inst_id: "BTC-USDT",
        bids: [
          ["49999.0", "2.0"],
          ["49998.0", "1.5"]
        ],
        asks: [
          ["50001.0", "1.0"],
          ["50002.0", "80.0"],
          ["50003.0", "1.5"],
          ["50004.0", "2.0"],
          ["50005.0", "1.0"],
          ["50006.0", "1.8"]
        ],
        ts: "1234567890"
      }

      now = System.monotonic_time(:millisecond)
      walls = WallDetector.detect_walls(book, "BTC-USDT", @config, now)

      ask_walls = Enum.filter(walls, fn w -> w.side == :ask end)
      assert length(ask_walls) == 1

      wall = hd(ask_walls)
      assert wall.price == 50002.0
      assert wall.size == 80.0
    end

    test "ignores levels below multiplier threshold" do
      book = %BookState{
        inst_id: "BTC-USDT",
        bids: [
          ["50000.0", "2.0"],
          ["49999.0", "3.0"],
          ["49998.0", "4.0"],
          ["49997.0", "5.0"]
        ],
        asks: [
          ["50001.0", "2.0"],
          ["50002.0", "3.0"]
        ],
        ts: "1234567890"
      }

      now = System.monotonic_time(:millisecond)
      walls = WallDetector.detect_walls(book, "BTC-USDT", @config, now)

      assert walls == []
    end

    test "handles empty book" do
      book = %BookState{
        inst_id: "BTC-USDT",
        bids: [],
        asks: [],
        ts: "1234567890"
      }

      now = System.monotonic_time(:millisecond)
      walls = WallDetector.detect_walls(book, "BTC-USDT", @config, now)

      assert walls == []
    end

    test "detects walls on both sides" do
      book = %BookState{
        inst_id: "BTC-USDT",
        bids: [
          ["50000.0", "1.0"],
          ["49999.0", "1.5"],
          ["49998.0", "60.0"],
          ["49997.0", "1.0"],
          ["49996.0", "2.0"],
          ["49995.0", "1.5"]
        ],
        asks: [
          ["50001.0", "1.0"],
          ["50002.0", "1.5"],
          ["50003.0", "70.0"],
          ["50004.0", "1.0"],
          ["50005.0", "2.0"],
          ["50006.0", "1.5"]
        ],
        ts: "1234567890"
      }

      now = System.monotonic_time(:millisecond)
      walls = WallDetector.detect_walls(book, "BTC-USDT", @config, now)

      bid_walls = Enum.filter(walls, fn w -> w.side == :bid end)
      ask_walls = Enum.filter(walls, fn w -> w.side == :ask end)

      assert length(bid_walls) == 1
      assert length(ask_walls) == 1
      assert hd(bid_walls).price == 49998.0
      assert hd(ask_walls).price == 50003.0
    end
  end
end
