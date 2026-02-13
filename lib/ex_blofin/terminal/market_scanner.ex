defmodule ExBlofin.Terminal.MarketScanner do
  @moduledoc """
  Market scanner that polls all tickers and ranks instruments.

  Periodically fetches ticker data via REST API and displays
  a sorted table of instruments by volume, price change, etc.

  ## Usage

  From the terminal:

      mix run scripts/scanner.exs
      mix run scripts/scanner.exs --sort volume --top 20
      mix run scripts/scanner.exs --sort change --top 15

  From iex:

      {:ok, pid} = ExBlofin.Terminal.MarketScanner.start()
      ExBlofin.Terminal.MarketScanner.stop(pid)
  """

  use GenServer

  require Logger

  @poll_interval 5_000

  defstruct [
    :client,
    :poll_timer,
    sort_by: :volume,
    top_n: 25,
    tickers: [],
    last_poll: nil,
    dirty: false
  ]

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Starts the market scanner.

  ## Options

    - `:sort` - Sort method: :volume, :change, :gainers, :losers (default: :volume)
    - `:top` - Number of instruments to show (default: 25)
    - `:demo` - Use demo environment (default: false)
  """
  def start(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Stops the scanner."
  def stop(pid), do: GenServer.stop(pid, :normal)

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init(opts) do
    demo = Keyword.get(opts, :demo, false)
    sort_by = Keyword.get(opts, :sort, :volume)
    top_n = Keyword.get(opts, :top, 25)

    client = ExBlofin.Client.new(nil, nil, nil, demo: demo)

    state = %__MODULE__{
      client: client,
      sort_by: sort_by,
      top_n: top_n
    }

    render_waiting()
    send(self(), :poll)
    :timer.send_interval(100, :do_render)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:poll, state) do
    tickers =
      case ExBlofin.MarketData.get_tickers(state.client) do
        {:ok, data} when is_list(data) ->
          Enum.map(data, &parse_ticker/1)

        _ ->
          state.tickers
      end

    if state.poll_timer, do: Process.cancel_timer(state.poll_timer)
    timer = Process.send_after(self(), :poll, @poll_interval)

    {:noreply,
     %{
       state
       | tickers: tickers,
         last_poll: System.system_time(:second),
         poll_timer: timer,
         dirty: true
     }}
  end

  @impl GenServer
  def handle_info(:do_render, %{dirty: true} = state) do
    if length(state.tickers) > 0, do: render(state)
    {:noreply, %{state | dirty: false}}
  end

  @impl GenServer
  def handle_info(_msg, state), do: {:noreply, state}

  # ============================================================================
  # Data Processing
  # ============================================================================

  defp parse_ticker(data) when is_map(data) do
    last = parse_float(data["last"])
    open = parse_float(data["open24h"])
    change = if open > 0, do: (last - open) / open * 100, else: 0.0

    %{
      inst_id: data["instId"],
      last: last,
      open: open,
      high: parse_float(data["high24h"]),
      low: parse_float(data["low24h"]),
      volume: parse_float(data["volCurrency24h"]),
      bid: parse_float(data["bidPrice"]),
      ask: parse_float(data["askPrice"]),
      change_pct: change
    }
  end

  defp sort_tickers(tickers, sort_by) do
    case sort_by do
      :volume ->
        Enum.sort_by(tickers, & &1.volume, :desc)

      :change ->
        Enum.sort_by(tickers, &abs(&1.change_pct), :desc)

      :gainers ->
        Enum.sort_by(tickers, & &1.change_pct, :desc)

      :losers ->
        Enum.sort_by(tickers, & &1.change_pct, :asc)

      _ ->
        Enum.sort_by(tickers, & &1.volume, :desc)
    end
  end

  # ============================================================================
  # Terminal Rendering
  # ============================================================================

  defp render_waiting do
    IO.write("\e[H\e[2J")
    IO.puts("")
    IO.puts("  Market Scanner")
    IO.puts("  Fetching tickers...")
  end

  defp render(state) do
    sorted =
      state.tickers
      |> sort_tickers(state.sort_by)
      |> Enum.take(state.top_n)

    countdown = refresh_countdown(state.last_poll)

    lines =
      [
        "",
        title_line(state.sort_by, countdown),
        divider(),
        column_header(),
        divider(),
        format_rows(sorted),
        divider(),
        footer_line(state.tickers),
        ""
      ]
      |> List.flatten()
      |> Enum.map(fn line -> "\e[2K" <> line end)

    IO.write("\e[H" <> Enum.join(lines, "\n") <> "\e[J")
  end

  defp title_line(sort_by, countdown) do
    sort_label =
      case sort_by do
        :volume -> "Volume"
        :change -> "Change"
        :gainers -> "Gainers"
        :losers -> "Losers"
        _ -> "Volume"
      end

    IO.ANSI.bright() <>
      "  Market Scanner" <>
      IO.ANSI.reset() <>
      IO.ANSI.faint() <>
      "  (sorted by #{sort_label})" <>
      "  Refresh: #{countdown}s" <>
      IO.ANSI.reset()
  end

  defp divider do
    "  " <> String.duplicate("─", 88)
  end

  defp column_header do
    IO.ANSI.faint() <>
      "  " <>
      pad_right("#", 4) <>
      pad_right("Instrument", 14) <>
      "│" <>
      pad_right(" Last", 14) <>
      "│" <>
      pad_right(" 24h Chg%", 11) <>
      "│" <>
      pad_right(" Volume", 16) <>
      "│" <>
      pad_right(" Bid", 14) <>
      "│" <>
      " Ask" <>
      IO.ANSI.reset()
  end

  defp format_rows(tickers) do
    tickers
    |> Enum.with_index(1)
    |> Enum.map(fn {t, idx} -> format_row(t, idx) end)
  end

  defp format_row(t, idx) do
    color =
      if t.change_pct >= 0, do: IO.ANSI.green(), else: IO.ANSI.red()

    arrow = if t.change_pct >= 0, do: "▲", else: "▼"
    reset = IO.ANSI.reset()

    "  " <>
      pad_right("#{idx}", 4) <>
      pad_right(t.inst_id, 14) <>
      "│" <>
      pad_right(" #{fmt_price(t.last)}", 14) <>
      "│" <>
      color <>
      pad_right(" #{arrow}#{fmt_pct(t.change_pct)}", 11) <>
      reset <>
      "│" <>
      pad_right(" #{fmt_vol(t.volume)}", 16) <>
      "│" <>
      pad_right(" #{fmt_price(t.bid)}", 14) <>
      "│" <>
      " #{fmt_price(t.ask)}"
  end

  defp footer_line(tickers) do
    total = length(tickers)
    gainers = Enum.count(tickers, &(&1.change_pct > 0))
    losers = Enum.count(tickers, &(&1.change_pct < 0))

    IO.ANSI.faint() <>
      "  Total: #{total}  " <>
      IO.ANSI.green() <>
      "▲ #{gainers}" <>
      IO.ANSI.reset() <>
      IO.ANSI.faint() <>
      "  " <>
      IO.ANSI.red() <>
      "▼ #{losers}" <>
      IO.ANSI.reset() <>
      IO.ANSI.faint() <>
      "  Flat: #{total - gainers - losers}" <>
      IO.ANSI.reset()
  end

  defp refresh_countdown(nil), do: "--"

  defp refresh_countdown(last_poll) do
    elapsed = System.system_time(:second) - last_poll
    remaining = max(div(@poll_interval, 1000) - elapsed, 0)
    "#{remaining}"
  end

  # ============================================================================
  # Formatting Helpers
  # ============================================================================

  defp parse_float(nil), do: 0.0

  defp parse_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp parse_float(n) when is_number(n), do: n / 1

  defp fmt_price(n) when n == 0.0, do: "--"

  defp fmt_price(n) do
    n |> :erlang.float_to_binary(decimals: 2) |> add_commas()
  end

  defp fmt_pct(n) do
    "#{:erlang.float_to_binary(abs(n), decimals: 2)}%"
  end

  defp fmt_vol(n) when n >= 1_000_000 do
    "#{:erlang.float_to_binary(n / 1_000_000, decimals: 2)}M"
  end

  defp fmt_vol(n) when n >= 1_000 do
    "#{:erlang.float_to_binary(n / 1_000, decimals: 2)}K"
  end

  defp fmt_vol(n) do
    :erlang.float_to_binary(n, decimals: 2)
  end

  defp add_commas(s) when is_binary(s) do
    case String.split(s, ".") do
      [int_part] -> add_commas_int(int_part)
      [int_part, dec] -> add_commas_int(int_part) <> "." <> dec
    end
  end

  defp add_commas_int(s) do
    s
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp pad_right(s, width) do
    len = String.length(s)
    if len >= width, do: s, else: s <> String.duplicate(" ", width - len)
  end
end
