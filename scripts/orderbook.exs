# Real-time order book display
#
# Usage:
#   mix run scripts/orderbook.exs BTC-USDT
#   mix run scripts/orderbook.exs BTC-USDT ETH-USDT
#   mix run scripts/orderbook.exs BTC-USDT ETH-USDT SOL-USDT DOGE-USDT
#   mix run scripts/orderbook.exs ETH-USDT --levels 20
#   mix run scripts/orderbook.exs BTC-USDT --demo
#
# Pass 1 ticker for a single full-width view.
# Pass 2-4 tickers for a side-by-side grid view.
#
# Press Ctrl+C twice to exit.

require Logger
Logger.configure(level: :none)

{opts, args, _} =
  OptionParser.parse(System.argv(), strict: [levels: :integer, demo: :boolean])

inst_ids = if args == [], do: ["BTC-USDT"], else: Enum.take(args, 4)
demo = Keyword.get(opts, :demo, false)
levels_opt = Keyword.get(opts, :levels)

start_opts = [demo: demo] ++ if(levels_opt, do: [levels: levels_opt], else: [])

if length(inst_ids) == 1 do
  {:ok, _pid} = ExBlofin.Terminal.OrderBook.start(hd(inst_ids), start_opts)
else
  {:ok, _pid} = ExBlofin.Terminal.MultiOrderBook.start(inst_ids, start_opts)
end

Process.sleep(:infinity)
