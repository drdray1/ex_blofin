# Real-time ticker dashboard
#
# Usage:
#   mix run scripts/tickers.exs BTC-USDT ETH-USDT SOL-USDT
#   mix run scripts/tickers.exs BTC-USDT --demo
#
# Press Ctrl+C twice to exit.

require Logger
Logger.configure(level: :none)

{opts, args, _} =
  OptionParser.parse(System.argv(), strict: [demo: :boolean])

inst_ids = if args == [], do: ["BTC-USDT"], else: args
demo = Keyword.get(opts, :demo, false)

{:ok, _pid} = ExBlofin.Terminal.TickerDashboard.start(inst_ids, demo: demo)
Process.sleep(:infinity)
