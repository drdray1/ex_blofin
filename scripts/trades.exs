# Real-time trade tape (time & sales)
#
# Usage:
#   mix run scripts/trades.exs BTC-USDT
#   mix run scripts/trades.exs BTC-USDT ETH-USDT
#   mix run scripts/trades.exs BTC-USDT --max 40
#   mix run scripts/trades.exs BTC-USDT --demo
#
# Press Ctrl+C twice to exit.

require Logger
Logger.configure(level: :none)

{opts, args, _} =
  OptionParser.parse(System.argv(), strict: [max: :integer, demo: :boolean])

inst_ids = if args == [], do: ["BTC-USDT"], else: args
demo = Keyword.get(opts, :demo, false)
start_opts = [demo: demo] ++ Keyword.take(opts, [:max])

{:ok, _pid} = ExBlofin.Terminal.TradeTape.start(inst_ids, start_opts)
Process.sleep(:infinity)
