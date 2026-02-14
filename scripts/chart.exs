# Real-time ASCII candlestick chart
#
# Usage:
#   mix run scripts/chart.exs BTC-USDT
#   mix run scripts/chart.exs ETH-USDT --bar 5m
#   mix run scripts/chart.exs BTC-USDT --bar 1H --height 30
#   mix run scripts/chart.exs BTC-USDT --ema 12,26,50
#   mix run scripts/chart.exs BTC-USDT ETH-USDT
#   mix run scripts/chart.exs BTC-USDT ETH-USDT SOL-USDT DOGE-USDT --bar 1H
#   mix run scripts/chart.exs BTC-USDT --demo
#
# Pass 1 ticker for full-width chart.
# Pass 2-4 tickers for multi-chart grid.
#
# Valid bars: 1m, 3m, 5m, 15m, 30m, 1H, 2H, 4H, 6H, 8H, 12H, 1D, 3D, 1W, 1M
#
# Press Ctrl+C twice to exit.

require Logger
Logger.configure(level: :none)

{opts, args, _} =
  OptionParser.parse(System.argv(),
    strict: [bar: :string, height: :integer, width: :integer, demo: :boolean, ema: :string]
  )

inst_ids = if args == [], do: ["BTC-USDT"], else: Enum.take(args, 4)
demo = Keyword.get(opts, :demo, false)

ema_opt =
  case Keyword.get(opts, :ema) do
    nil ->
      []

    s ->
      periods = s |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.map(&String.to_integer/1)

      case periods do
        [_, _, _] -> [ema: periods]
        _ ->
          IO.puts("Warning: --ema requires 3 comma-separated periods (e.g. --ema 9,21,55)")
          []
      end
  end

start_opts =
  [demo: demo] ++ Keyword.take(opts, [:bar, :height, :width]) ++ ema_opt

if length(inst_ids) == 1 do
  {:ok, _pid} = ExBlofin.Terminal.CandlestickChart.start(hd(inst_ids), start_opts)
else
  {:ok, _pid} = ExBlofin.Terminal.MultiCandlestickChart.start(inst_ids, start_opts)
end

Process.sleep(:infinity)
