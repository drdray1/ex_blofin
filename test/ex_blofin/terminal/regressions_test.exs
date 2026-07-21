defmodule ExBlofin.Terminal.RegressionsTest do
  @moduledoc """
  Pins the confirmed TUI bugs. Each test fails against the previous behaviour.

  These are driven through the GenServer callbacks directly — no terminal and
  no socket — which is the seam that made this subsystem testable at all.
  """
  use ExUnit.Case, async: true

  alias ExBlofin.Terminal.{FundingMonitor, MultiOrderBook, OrderBook}
  alias ExBlofin.WebSocket.Message.{BookEvent, FundingRateEvent}

  describe "funding monitor receives live updates" do
    test "handles the atom the message layer actually emits" do
      # message.ex emits :funding_rate for the "funding-rate" channel. The
      # monitor matched :"funding-rate", so every update was silently dropped
      # and the pane showed the startup REST snapshot forever.
      state = %FundingMonitor{inst_ids: ["BTC-USDT"], rates: %{}}
      event = %FundingRateEvent{inst_id: "BTC-USDT", funding_rate: "0.0001"}

      assert {:noreply, updated} =
               FundingMonitor.handle_info({:blofin_event, :funding_rate, [event]}, state)

      assert updated.rates["BTC-USDT"] == event
      assert updated.dirty
    end

    test "later updates replace earlier ones for the same instrument" do
      first = %FundingRateEvent{inst_id: "BTC-USDT", funding_rate: "0.0001"}
      second = %FundingRateEvent{inst_id: "BTC-USDT", funding_rate: "0.0009"}
      state = %FundingMonitor{inst_ids: ["BTC-USDT"], rates: %{"BTC-USDT" => first}}

      assert {:noreply, updated} =
               FundingMonitor.handle_info({:blofin_event, :funding_rate, [second]}, state)

      assert updated.rates["BTC-USDT"].funding_rate == "0.0009"
    end
  end

  describe "order book message handling" do
    defp book(opts) do
      %BookEvent{
        inst_id: Keyword.get(opts, :inst_id, "BTC-USDT"),
        asks: Keyword.get(opts, :asks, []),
        bids: Keyword.get(opts, :bids, []),
        ts: Keyword.get(opts, :ts, "1697021343571"),
        action: Keyword.get(opts, :action)
      }
    end

    defp send_books(state, books) do
      {:noreply, updated} = OrderBook.handle_info({:blofin_event, :books, books}, state)
      updated
    end

    test "a batched message is applied, not dropped" do
      # The old `[book]` pattern matched only single-element lists; a batch fell
      # through to the catch-all and vanished while the display stayed "Live".
      state = %OrderBook{inst_id: "BTC-USDT"}

      updated =
        send_books(state, [
          book(asks: [["50001", "1"]], bids: [["50000", "1"]]),
          book(asks: [["50002", "2"]], bids: [["49999", "2"]])
        ])

      assert updated.asks == [["50002", "2"]]
      assert updated.bids == [["49999", "2"]]
    end

    test "a nil action replaces rather than merges" do
      # `action` is nil whenever the payload arrives as a JSON array. Treating
      # that as an incremental update meant the snapshot sent after a reconnect
      # was merged into the stale book, so vanished levels lived forever.
      stale = %OrderBook{
        inst_id: "BTC-USDT",
        asks: [["50001", "1"], ["50005", "9"]],
        bids: [["50000", "1"]]
      }

      updated = send_books(stale, [book(asks: [["50002", "1"]], bids: [["49998", "1"]])])

      assert updated.asks == [["50002", "1"]]
      refute Enum.any?(updated.asks, fn [p | _] -> p == "50005" end)
    end

    test "an explicit update action still merges incrementally" do
      state = %OrderBook{inst_id: "BTC-USDT", asks: [["50001", "1"]], bids: [["50000", "1"]]}

      updated =
        send_books(state, [book(action: "update", asks: [["50002", "3"]], bids: [])])

      assert Enum.sort(updated.asks) == [["50001", "1"], ["50002", "3"]]
    end

    test "a zero size removes the level" do
      state = %OrderBook{inst_id: "BTC-USDT", asks: [["50001", "1"]], bids: []}

      updated = send_books(state, [book(action: "update", asks: [["50001", "0"]], bids: [])])

      assert updated.asks == []
    end

    test "price levels are matched numerically, not by string equality" do
      # "50000.0" and "50000.00" are one level. Comparing the raw strings left
      # both in the book, which sorted adjacently and double-counted depth.
      state = %OrderBook{inst_id: "BTC-USDT", asks: [["50000.0", "1"]], bids: []}

      updated =
        send_books(state, [book(action: "update", asks: [["50000.00", "5"]], bids: [])])

      assert length(updated.asks) == 1
      assert [["50000.00", "5"]] = updated.asks
    end

    test "asks sort ascending and bids descending" do
      state = %OrderBook{inst_id: "BTC-USDT"}

      updated =
        send_books(state, [
          book(
            asks: [["50003", "1"], ["50001", "1"], ["50002", "1"]],
            bids: [["49998", "1"], ["50000", "1"], ["49999", "1"]]
          )
        ])

      assert Enum.map(updated.asks, &hd/1) == ["50001", "50002", "50003"]
      assert Enum.map(updated.bids, &hd/1) == ["50000", "49999", "49998"]
    end
  end

  describe "multi order book message handling" do
    test "a batch spanning several instruments updates each one" do
      state = %MultiOrderBook{
        inst_ids: ["BTC-USDT", "ETH-USDT"],
        books: %{
          "BTC-USDT" => %{asks: [], bids: [], last_update: nil},
          "ETH-USDT" => %{asks: [], bids: [], last_update: nil}
        }
      }

      books = [
        %BookEvent{inst_id: "BTC-USDT", asks: [["50000", "1"]], bids: [], ts: "1"},
        %BookEvent{inst_id: "ETH-USDT", asks: [["3000", "2"]], bids: [], ts: "1"}
      ]

      assert {:noreply, updated} =
               MultiOrderBook.handle_info({:blofin_event, :books, books}, state)

      assert updated.books["BTC-USDT"].asks == [["50000", "1"]]
      assert updated.books["ETH-USDT"].asks == [["3000", "2"]]
    end

    test "an unknown instrument in the batch is ignored, not crashed on" do
      state = %MultiOrderBook{
        inst_ids: ["BTC-USDT"],
        books: %{"BTC-USDT" => %{asks: [], bids: [], last_update: nil}}
      }

      books = [%BookEvent{inst_id: "DOGE-USDT", asks: [["0.1", "1"]], bids: [], ts: "1"}]

      assert {:noreply, updated} =
               MultiOrderBook.handle_info({:blofin_event, :books, books}, state)

      assert Map.keys(updated.books) == ["BTC-USDT"]
    end
  end
end
