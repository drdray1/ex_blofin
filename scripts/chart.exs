# Real-time ASCII candlestick chart
#
# Usage:
#   mix run scripts/chart.exs BTC-USDT
#   mix run scripts/chart.exs ETH-USDT --bar 5m
#   mix run scripts/chart.exs BTC-USDT --bar 1H --height 30
#   mix run scripts/chart.exs BTC-USDT --demo
#
# Valid bars: 1m, 3m, 5m, 15m, 30m, 1H, 2H, 4H, 6H, 8H, 12H, 1D, 3D, 1W, 1M
#
# Press Ctrl+C twice to exit.

require Logger
Logger.configure(level: :none)

{opts, args, _} =
  OptionParser.parse(System.argv(),
    strict: [bar: :string, height: :integer, width: :integer, demo: :boolean]
  )

inst_id = List.first(args) || "BTC-USDT"
demo = Keyword.get(opts, :demo, false)

start_opts =
  [demo: demo] ++ Keyword.take(opts, [:bar, :height, :width])

{:ok, _pid} = ExBlofin.Terminal.CandlestickChart.start(inst_id, start_opts)
Process.sleep(:infinity)
