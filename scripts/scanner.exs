# Market scanner - polls all tickers and ranks by metrics
#
# Usage:
#   mix run scripts/scanner.exs
#   mix run scripts/scanner.exs --sort volume --top 20
#   mix run scripts/scanner.exs --sort change --top 15
#   mix run scripts/scanner.exs --sort gainers
#   mix run scripts/scanner.exs --sort losers
#   mix run scripts/scanner.exs --demo
#
# Sort options: volume (default), change, gainers, losers
#
# Press Ctrl+C twice to exit.

require Logger
Logger.configure(level: :none)

{opts, _args, _} =
  OptionParser.parse(System.argv(),
    strict: [sort: :string, top: :integer, demo: :boolean]
  )

demo = Keyword.get(opts, :demo, false)
top_n = Keyword.get(opts, :top, 25)

sort_by =
  case Keyword.get(opts, :sort, "volume") do
    "volume" -> :volume
    "change" -> :change
    "gainers" -> :gainers
    "losers" -> :losers
    _ -> :volume
  end

{:ok, _pid} =
  ExBlofin.Terminal.MarketScanner.start(
    demo: demo,
    sort: sort_by,
    top: top_n
  )

Process.sleep(:infinity)
