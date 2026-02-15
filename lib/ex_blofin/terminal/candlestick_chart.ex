defmodule ExBlofin.Terminal.CandlestickChart do
  @moduledoc """
  Real-time ASCII candlestick chart in the terminal.

  Fetches historical candles via REST, then streams live updates
  via WebSocket. Renders price candles with volume bars.

  ## Usage

  From the terminal:

      mix run scripts/chart.exs BTC-USDT
      mix run scripts/chart.exs ETH-USDT --bar 5m --height 20

  From iex:

      {:ok, pid} = ExBlofin.Terminal.CandlestickChart.start("BTC-USDT")
      ExBlofin.Terminal.CandlestickChart.stop(pid)
  """

  use GenServer

  require Logger

  alias ExBlofin.WebSocket.PublicConnection

  @label_w 12
  @vol_blocks ~w(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)
  # Keep a generous buffer so the chart can grow when the pane is widened
  @buffer_size 300
  # Overhead lines: blank + title + divider + divider + volume + divider + legend + footer + blank
  @overhead_rows 9

  # EMA overlay styling
  @ema_colors {IO.ANSI.yellow(), IO.ANSI.cyan(), IO.ANSI.magenta()}
  @ema_char "*"

  defstruct [
    :conn_pid,
    :inst_id,
    :bar,
    candles: [],
    # nil = auto-size from terminal dimensions
    chart_height: nil,
    max_candles: nil,
    last_size: {0, 0},
    dirty: false,
    ema_periods: nil
  ]

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Starts the candlestick chart.

  ## Options

    - `:bar` - Candle timeframe (default: "1m")
    - `:height` - Chart height in rows (default: 20)
    - `:width` - Number of candles to show (default: 60)
    - `:demo` - Use demo environment (default: false)
  """
  def start(inst_id, opts \\ []) do
    GenServer.start_link(__MODULE__, {inst_id, opts})
  end

  @doc "Stops the chart."
  def stop(pid), do: GenServer.stop(pid, :normal)

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init({inst_id, opts}) do
    bar = Keyword.get(opts, :bar, "1m")
    height = Keyword.get(opts, :height)
    width = Keyword.get(opts, :width)
    demo = Keyword.get(opts, :demo, false)

    ema_periods =
      case Keyword.get(opts, :ema) do
        [a, b, c] when is_integer(a) and is_integer(b) and is_integer(c) -> {a, b, c}
        _ -> nil
      end

    state = %__MODULE__{
      inst_id: inst_id,
      bar: bar,
      chart_height: height,
      max_candles: width,
      ema_periods: ema_periods
    }

    render_waiting(inst_id, bar)

    # Fetch a generous buffer of candles so the chart can fill a wide terminal
    client = ExBlofin.Client.new(nil, nil, nil, demo: demo)

    candles =
      case ExBlofin.MarketData.get_candles(
             client,
             inst_id,
             bar: bar,
             limit: "#{@buffer_size}"
           ) do
        {:ok, data} when is_list(data) ->
          data
          |> Enum.map(&parse_candle_data/1)
          |> Enum.sort_by(& &1.ts)

        _ ->
          []
      end

    # Connect WebSocket for live updates
    {:ok, conn_pid} = PublicConnection.start_link(demo: demo)
    PublicConnection.add_subscriber(conn_pid, self())
    channel = "candle#{bar}"

    PublicConnection.subscribe(conn_pid, [
      %{"channel" => channel, "instId" => inst_id}
    ])

    state = %{state | conn_pid: conn_pid, candles: candles, dirty: true}

    :timer.send_interval(100, :do_render)
    {:ok, state}
  end

  @impl GenServer
  def handle_info({:blofin_event, _channel, events}, state) do
    candles =
      Enum.reduce(events, state.candles, fn event, acc ->
        upsert_candle(acc, event)
      end)

    candles = Enum.take(candles, -@buffer_size)
    {:noreply, %{state | candles: candles, dirty: true}}
  end

  @impl GenServer
  def handle_info(:do_render, state) do
    size = get_terminal_size()
    dirty = state.dirty or size != state.last_size

    if dirty and length(state.candles) > 0 do
      render(state)
    end

    {:noreply, %{state | dirty: false, last_size: size}}
  end

  @impl GenServer
  def handle_info(_msg, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    if state.conn_pid && Process.alive?(state.conn_pid) do
      PublicConnection.stop(state.conn_pid)
    end

    :ok
  end

  # ============================================================================
  # Candle Management
  # ============================================================================

  defp parse_candle_data(data) when is_list(data) do
    %{
      ts: Enum.at(data, 0, "0"),
      open: parse_float(Enum.at(data, 1, "0")),
      high: parse_float(Enum.at(data, 2, "0")),
      low: parse_float(Enum.at(data, 3, "0")),
      close: parse_float(Enum.at(data, 4, "0")),
      vol: parse_float(Enum.at(data, 5, "0"))
    }
  end

  defp parse_candle_data(data) when is_map(data) do
    %{
      ts: data["ts"] || Map.get(data, :ts, "0"),
      open: parse_float(data["open"] || Map.get(data, :open, "0")),
      high: parse_float(data["high"] || Map.get(data, :high, "0")),
      low: parse_float(data["low"] || Map.get(data, :low, "0")),
      close: parse_float(data["close"] || Map.get(data, :close, "0")),
      vol: parse_float(data["vol"] || Map.get(data, :vol, "0"))
    }
  end

  defp upsert_candle(candles, event) do
    ts = event.ts
    new = struct_to_candle(event)

    case List.last(candles) do
      %{ts: ^ts} ->
        List.replace_at(candles, -1, new)

      _ ->
        candles ++ [new]
    end
  end

  defp struct_to_candle(e) do
    %{
      ts: e.ts,
      open: parse_float(e.open),
      high: parse_float(e.high),
      low: parse_float(e.low),
      close: parse_float(e.close),
      vol: parse_float(e.vol)
    }
  end

  # ============================================================================
  # EMA Calculation
  # ============================================================================

  defp compute_ema(candles, period) when length(candles) < period, do: []

  defp compute_ema(candles, period) do
    k = 2.0 / (period + 1)
    {seed, rest} = Enum.split(candles, period)
    sma = Enum.sum(Enum.map(seed, & &1.close)) / period

    {ema_values, _} =
      Enum.map_reduce(rest, sma, fn candle, prev ->
        ema = candle.close * k + prev * (1.0 - k)
        {ema, ema}
      end)

    List.duplicate(nil, period - 1) ++ [sma | ema_values]
  end

  defp compute_emas(all_candles, visible_count, periods) do
    visible_start = max(length(all_candles) - visible_count, 0)

    Enum.map(periods, fn period ->
      all_candles
      |> compute_ema(period)
      |> Enum.drop(visible_start)
    end)
  end

  # ============================================================================
  # Terminal Rendering
  # ============================================================================

  defp render_waiting(inst_id, bar) do
    IO.write("\e[H\e[2J")
    IO.puts("")
    IO.puts("  Loading #{inst_id} #{bar} chart...")
    IO.puts("  Fetching historical data...")
  end

  defp render(state) do
    {height, width} = effective_dims(state)
    candles = Enum.take(state.candles, -width)
    last = List.last(candles)
    total_w = @label_w + length(candles)

    {min_low, max_high} = price_range(candles)
    price_range_val = max_high - min_low
    price_range_val = if price_range_val == 0.0, do: 1.0, else: price_range_val

    # Compute EMA overlay rows (only if EMAs are enabled)
    ema_row_tuples =
      case state.ema_periods do
        {p1, p2, p3} ->
          state.candles
          |> compute_emas(length(candles), [p1, p2, p3])
          |> Enum.map(fn ema_values ->
            ema_values
            |> Enum.map(fn
              nil -> nil
              price -> price_to_row(price, height, min_low, price_range_val)
            end)
            |> List.to_tuple()
          end)

        nil ->
          []
      end

    chart_rows =
      for row <- 0..(height - 1) do
        price = max_high - row / max(height - 1, 1) * price_range_val
        label = pad_left(fmt_price(price), @label_w - 2) <> " ┤"

        cells =
          candles
          |> Enum.with_index()
          |> Enum.map(fn {c, col_idx} ->
            candle_cell = render_cell(c, row, height, min_low, price_range_val)
            ema_cell = render_ema_cell(ema_row_tuples, col_idx, row)
            merge_cell(candle_cell, ema_cell)
          end)

        label <> Enum.join(cells)
      end

    vol_row = render_volume_row(candles)

    lines =
      [
        "",
        title_line(state),
        "  " <> String.duplicate("─", total_w),
        chart_rows,
        "  " <> String.duplicate("─", total_w),
        "  #{String.duplicate(" ", @label_w)}#{vol_row}",
        "  " <> String.duplicate("─", total_w),
        ema_legend_line(state.ema_periods),
        footer_line(last),
        ""
      ]
      |> List.flatten()
      |> Enum.map(fn line -> "\e[2K" <> line end)

    IO.write("\e[H" <> Enum.join(lines, "\n") <> "\e[J")
  end

  defp title_line(state) do
    last = List.last(state.candles)
    ts = format_timestamp(last.ts)

    IO.ANSI.bright() <>
      "  #{state.inst_id} #{state.bar}" <>
      IO.ANSI.reset() <>
      "  " <>
      IO.ANSI.green() <>
      "●" <>
      IO.ANSI.reset() <>
      " #{ts}"
  end

  defp render_cell(candle, row, height, min_low, range) do
    high_row = price_to_row(candle.high, height, min_low, range)
    low_row = price_to_row(candle.low, height, min_low, range)
    body_top = price_to_row(max(candle.open, candle.close), height, min_low, range)
    body_bot = price_to_row(min(candle.open, candle.close), height, min_low, range)
    bullish = candle.close >= candle.open
    color = if bullish, do: IO.ANSI.green(), else: IO.ANSI.red()
    reset = IO.ANSI.reset()

    cond do
      row >= high_row and row < body_top ->
        color <> "│" <> reset

      row >= body_top and row <= body_bot ->
        color <> "█" <> reset

      row > body_bot and row <= low_row ->
        color <> "│" <> reset

      true ->
        " "
    end
  end

  defp render_ema_cell(ema_row_tuples, col_idx, row) do
    colors = Tuple.to_list(@ema_colors)

    # Walk slow to fast so the fast EMA (first) wins ties
    ema_row_tuples
    |> Enum.zip(colors)
    |> Enum.reverse()
    |> Enum.reduce(nil, fn {ema_tuple, color}, acc ->
      if tuple_size(ema_tuple) > col_idx and elem(ema_tuple, col_idx) == row do
        {color, @ema_char}
      else
        acc
      end
    end)
  end

  defp merge_cell(candle_cell, nil), do: candle_cell
  defp merge_cell(" ", {color, char}), do: color <> char <> IO.ANSI.reset()
  defp merge_cell(candle_cell, _ema), do: candle_cell

  defp ema_legend_line(nil), do: []

  defp ema_legend_line({p1, p2, p3}) do
    {c1, c2, c3} = @ema_colors
    reset = IO.ANSI.reset()

    "  " <>
      c1 <>
      "#{@ema_char} EMA #{p1}" <>
      reset <>
      "  " <>
      c2 <>
      "#{@ema_char} EMA #{p2}" <>
      reset <>
      "  " <>
      c3 <> "#{@ema_char} EMA #{p3}" <> reset
  end

  defp price_to_row(price, height, min_low, range) do
    row = (height - 1) * (1.0 - (price - min_low) / range)
    round(row) |> max(0) |> min(height - 1)
  end

  defp render_volume_row(candles) do
    max_vol =
      candles |> Enum.map(& &1.vol) |> Enum.max(fn -> 1.0 end)

    max_vol = if max_vol == 0.0, do: 1.0, else: max_vol

    candles
    |> Enum.map(fn c ->
      idx = round(c.vol / max_vol * 7) |> max(0) |> min(7)
      color = if c.close >= c.open, do: IO.ANSI.green(), else: IO.ANSI.red()
      color <> Enum.at(@vol_blocks, idx) <> IO.ANSI.reset()
    end)
    |> Enum.join()
  end

  defp footer_line(nil), do: ""

  defp footer_line(c) do
    color = if c.close >= c.open, do: IO.ANSI.green(), else: IO.ANSI.red()
    reset = IO.ANSI.reset()

    "  #{IO.ANSI.faint()}O:#{reset}#{fmt_price(c.open)}" <>
      " #{IO.ANSI.faint()}H:#{reset}#{fmt_price(c.high)}" <>
      " #{IO.ANSI.faint()}L:#{reset}#{fmt_price(c.low)}" <>
      " #{IO.ANSI.faint()}C:#{reset}#{color}#{fmt_price(c.close)}#{reset}" <>
      " #{IO.ANSI.faint()}Vol:#{reset}#{fmt_int(c.vol)}"
  end

  defp price_range(candles) do
    lows = Enum.map(candles, & &1.low)
    highs = Enum.map(candles, & &1.high)
    {Enum.min(lows), Enum.max(highs)}
  end

  # ============================================================================
  # Terminal Size
  # ============================================================================

  defp get_terminal_size do
    cols =
      case :io.columns() do
        {:ok, c} -> c
        _ -> 80
      end

    rows =
      case :io.rows() do
        {:ok, r} -> r
        _ -> 24
      end

    {rows, cols}
  end

  defp effective_dims(state) do
    {rows, cols} = get_terminal_size()
    height = state.chart_height || max(rows - @overhead_rows, 5)
    width = state.max_candles || max(cols - @label_w - 2, 10)
    {height, width}
  end

  # ============================================================================
  # Formatting Helpers
  # ============================================================================

  defp parse_float(n) when is_float(n), do: n
  defp parse_float(n) when is_integer(n), do: n / 1

  defp parse_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp parse_float(_), do: 0.0

  defp fmt_price(n) do
    n |> :erlang.float_to_binary(decimals: 2) |> add_commas()
  end

  defp fmt_int(n) do
    n |> round() |> Integer.to_string() |> add_commas()
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

  defp pad_left(s, width) do
    len = String.length(s)

    if len >= width,
      do: s,
      else: String.duplicate(" ", width - len) <> s
  end

  defp format_timestamp(nil), do: "--:--:--"

  defp format_timestamp(ts) when is_binary(ts) do
    case Integer.parse(ts) do
      {ms, _} ->
        ms
        |> DateTime.from_unix!(:millisecond)
        |> Calendar.strftime("%H:%M:%S")

      :error ->
        ts
    end
  end
end
