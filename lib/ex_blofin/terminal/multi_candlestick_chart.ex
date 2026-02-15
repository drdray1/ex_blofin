defmodule ExBlofin.Terminal.MultiCandlestickChart do
  @moduledoc """
  Multi-instrument candlestick chart display in a grid layout.

  Displays 2-4 candlestick charts in the terminal.
  Uses a vertical stack for 2 instruments and a 2x2 grid for 3-4.

  ## Usage

  From the terminal:

      mix run scripts/chart.exs BTC-USDT ETH-USDT
      mix run scripts/chart.exs BTC-USDT ETH-USDT SOL-USDT DOGE-USDT --bar 5m

  From iex:

      {:ok, pid} = ExBlofin.Terminal.MultiCandlestickChart.start(["BTC-USDT", "ETH-USDT"])
      ExBlofin.Terminal.MultiCandlestickChart.stop(pid)
  """

  use GenServer

  require Logger

  alias ExBlofin.WebSocket.PublicConnection

  @label_w 12
  @vol_blocks ~w(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)
  @buffer_size 300
  @separator " │ "
  @separator_visual_len 3

  # EMA overlay styling
  @ema_colors {IO.ANSI.yellow(), IO.ANSI.cyan(), IO.ANSI.magenta()}
  @ema_char "*"

  # Per-panel overhead: title + top_divider + bottom_divider + volume + legend + footer = 6
  # (legend was already counted above)
  @panel_overhead 7
  @min_chart_height 5

  defstruct [
    :conn_pid,
    :bar,
    inst_ids: [],
    # Map of inst_id => %{candles: [...]}
    charts: %{},
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
  Starts the multi-instrument candlestick chart.

  ## Options

    - `:bar` - Candle timeframe (default: "1m")
    - `:height` - Chart height per panel in rows (default: auto)
    - `:width` - Number of candles per panel (default: auto)
    - `:demo` - Use demo environment (default: false)
  """
  def start(inst_ids, opts \\ []) when is_list(inst_ids) do
    GenServer.start_link(__MODULE__, {inst_ids, opts})
  end

  @doc "Stops the multi chart display."
  def stop(pid), do: GenServer.stop(pid, :normal)

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init({inst_ids, opts}) do
    bar = Keyword.get(opts, :bar, "1m")
    height = Keyword.get(opts, :height)
    width = Keyword.get(opts, :width)
    demo = Keyword.get(opts, :demo, false)

    ema_periods =
      case Keyword.get(opts, :ema) do
        [a, b, c] when is_integer(a) and is_integer(b) and is_integer(c) -> {a, b, c}
        _ -> nil
      end

    render_waiting(inst_ids, bar)

    # Fetch historical candles for all instruments in parallel
    client = ExBlofin.Client.new(nil, nil, nil, demo: demo)

    charts =
      inst_ids
      |> Enum.map(fn id ->
        Task.async(fn ->
          candles =
            case ExBlofin.MarketData.get_candles(client, id, bar: bar, limit: "#{@buffer_size}") do
              {:ok, data} when is_list(data) ->
                data
                |> Enum.map(&parse_candle_data/1)
                |> Enum.sort_by(& &1.ts)

              _ ->
                []
            end

          {id, %{candles: candles}}
        end)
      end)
      |> Task.await_many(30_000)
      |> Map.new()

    # Connect WebSocket for live updates
    {:ok, conn_pid} = PublicConnection.start_link(demo: demo)
    PublicConnection.add_subscriber(conn_pid, self())

    channel = "candle#{bar}"

    channels =
      Enum.map(inst_ids, &%{"channel" => channel, "instId" => &1})

    PublicConnection.subscribe(conn_pid, channels)

    state = %__MODULE__{
      conn_pid: conn_pid,
      inst_ids: inst_ids,
      bar: bar,
      chart_height: height,
      max_candles: width,
      charts: charts,
      ema_periods: ema_periods,
      dirty: true
    }

    :timer.send_interval(100, :do_render)
    {:ok, state}
  end

  @impl GenServer
  def handle_info({:blofin_event, _channel, events}, state) do
    charts =
      Enum.reduce(events, state.charts, fn event, acc ->
        inst_id = event.inst_id

        case Map.get(acc, inst_id) do
          nil ->
            acc

          chart_state ->
            candles =
              chart_state.candles
              |> upsert_candle(event)
              |> Enum.take(-@buffer_size)

            Map.put(acc, inst_id, %{chart_state | candles: candles})
        end
      end)

    {:noreply, %{state | charts: charts, dirty: true}}
  end

  @impl GenServer
  def handle_info(:do_render, state) do
    size = get_terminal_size()
    dirty = state.dirty or size != state.last_size

    has_data =
      Enum.any?(state.charts, fn {_id, cs} -> length(cs.candles) > 0 end)

    if dirty and has_data do
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

  defp render_ema_cell(ema_row_tuples, col_idx, row) do
    colors = Tuple.to_list(@ema_colors)

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
      "#{@ema_char} #{p1}" <>
      reset <>
      " " <>
      c2 <>
      "#{@ema_char} #{p2}" <>
      reset <>
      " " <>
      c3 <> "#{@ema_char} #{p3}" <> reset
  end

  # ============================================================================
  # Layout Calculation
  # ============================================================================

  defp grid_dims(state) do
    case length(state.inst_ids) do
      2 -> {2, 1}
      3 -> {2, 2}
      4 -> {2, 2}
      _ -> {1, 1}
    end
  end

  defp effective_layout(state) do
    {grid_rows, _grid_cols} = grid_dims(state)

    if state.chart_height do
      {grid_rows, state.chart_height}
    else
      {rows, _cols} = get_terminal_size()
      find_fitting_layout(rows, grid_rows)
    end
  end

  defp find_fitting_layout(rows, grid_rows) when grid_rows >= 1 do
    # overhead: 2 blanks + grid_rows * panel_overhead + (grid_rows - 1) * 1 separators
    overhead = 2 + grid_rows * @panel_overhead + max(grid_rows - 1, 0)
    available = rows - overhead
    chart_height = div(available, grid_rows)

    if chart_height >= @min_chart_height do
      {grid_rows, chart_height}
    else
      find_fitting_layout(rows, grid_rows - 1)
    end
  end

  defp find_fitting_layout(_rows, _grid_rows) do
    {1, @min_chart_height}
  end

  defp effective_widths(state) do
    {_grid_rows, grid_cols} = grid_dims(state)
    {_rows, cols} = get_terminal_size()

    if grid_cols == 1 do
      max_candles = state.max_candles || max(cols - @label_w - 2, 10)
      panel_w = @label_w + max_candles
      {max_candles, panel_w}
    else
      # Two columns: (panel_w * 2) + separator
      panel_w = div(cols - @separator_visual_len, 2)
      max_candles = state.max_candles || max(panel_w - @label_w - 2, 10)
      {max_candles, panel_w}
    end
  end

  # ============================================================================
  # Terminal Rendering
  # ============================================================================

  defp render_waiting(inst_ids, bar) do
    IO.write("\e[H\e[2J")
    IO.puts("")
    IO.puts("  Loading #{Enum.join(inst_ids, ", ")} #{bar} charts...")
    IO.puts("  Fetching historical data...")
  end

  defp render(state) do
    {grid_rows, chart_height} = effective_layout(state)
    {_grid_rows_d, grid_cols} = grid_dims(state)
    {max_candles, panel_w} = effective_widths(state)

    # Truncate instruments to what fits
    max_instruments = grid_rows * grid_cols
    visible_ids = Enum.take(state.inst_ids, max_instruments)

    panels =
      Enum.map(visible_ids, fn id ->
        chart_state = Map.get(state.charts, id)

        build_panel(
          id,
          chart_state,
          chart_height,
          max_candles,
          panel_w,
          state.bar,
          state.ema_periods
        )
      end)

    output =
      if grid_cols == 1 do
        # Vertical stack — just intersperse separators
        panels
        |> Enum.intersperse([row_separator(panel_w)])
        |> List.flatten()
      else
        # 2-column grid
        panels
        |> Enum.chunk_every(2)
        |> Enum.map(&merge_horizontal(&1, panel_w))
        |> Enum.intersperse([row_separator(panel_w * 2 + @separator_visual_len)])
        |> List.flatten()
      end

    output =
      ([""] ++ output ++ [""])
      |> Enum.map(fn line -> "\e[2K" <> line end)

    IO.write("\e[H" <> Enum.join(output, "\n") <> "\e[J")
  end

  defp build_panel(
         inst_id,
         %{candles: []},
         _chart_height,
         _max_candles,
         panel_w,
         _bar,
         _ema_periods
       ) do
    [
      IO.ANSI.bright() <> "  #{inst_id}" <> IO.ANSI.reset(),
      "",
      IO.ANSI.faint() <> "  Waiting for data..." <> IO.ANSI.reset(),
      ""
    ]
    |> Enum.map(&vpad(&1, panel_w))
  end

  defp build_panel(inst_id, chart_state, chart_height, max_candles, panel_w, bar, ema_periods) do
    candles = Enum.take(chart_state.candles, -max_candles)
    last = List.last(candles)
    total_w = @label_w + length(candles)

    {min_low, max_high} = price_range(candles)
    price_range_val = max_high - min_low
    price_range_val = if price_range_val == 0.0, do: 1.0, else: price_range_val

    # Compute EMA overlay rows (only if EMAs are enabled)
    ema_row_tuples =
      case ema_periods do
        {p1, p2, p3} ->
          chart_state.candles
          |> compute_emas(length(candles), [p1, p2, p3])
          |> Enum.map(fn ema_values ->
            ema_values
            |> Enum.map(fn
              nil -> nil
              price -> price_to_row(price, chart_height, min_low, price_range_val)
            end)
            |> List.to_tuple()
          end)

        nil ->
          []
      end

    chart_rows =
      for row <- 0..(chart_height - 1) do
        price = max_high - row / max(chart_height - 1, 1) * price_range_val
        label = pad_left(fmt_price(price), @label_w - 2) <> " ┤"

        cells =
          candles
          |> Enum.with_index()
          |> Enum.map(fn {c, col_idx} ->
            candle_cell = render_cell(c, row, chart_height, min_low, price_range_val)
            ema_cell = render_ema_cell(ema_row_tuples, col_idx, row)
            merge_cell(candle_cell, ema_cell)
          end)

        label <> Enum.join(cells)
      end

    vol_row = render_volume_row(candles)

    lines =
      [
        title_line(inst_id, bar, last),
        "  " <> String.duplicate("─", total_w),
        chart_rows,
        "  " <> String.duplicate("─", total_w),
        "  #{String.duplicate(" ", @label_w)}#{vol_row}",
        ema_legend_line(ema_periods),
        footer_line(last)
      ]
      |> List.flatten()
      |> Enum.map(&vpad(&1, panel_w))

    lines
  end

  defp title_line(inst_id, bar, last) do
    ts = format_timestamp(last.ts)

    IO.ANSI.bright() <>
      "  #{inst_id} #{bar}" <>
      IO.ANSI.reset() <>
      "  " <>
      IO.ANSI.green() <>
      "●" <>
      IO.ANSI.reset() <>
      " #{ts}"
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

  # ============================================================================
  # Cell Rendering
  # ============================================================================

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

  defp price_range(candles) do
    lows = Enum.map(candles, & &1.low)
    highs = Enum.map(candles, & &1.high)
    {Enum.min(lows), Enum.max(highs)}
  end

  # ============================================================================
  # Grid Merging (from MultiOrderBook pattern)
  # ============================================================================

  defp merge_horizontal([panel], panel_w) do
    empty = List.duplicate(vpad("", panel_w), length(panel))
    merge_horizontal([panel, empty], panel_w)
  end

  defp merge_horizontal([left, right], panel_w) do
    max_lines = max(length(left), length(right))
    empty = vpad("", panel_w)
    left = left ++ List.duplicate(empty, max_lines - length(left))
    right = right ++ List.duplicate(empty, max_lines - length(right))

    Enum.zip_with([left, right], fn [l, r] ->
      l <> @separator <> r
    end)
  end

  defp row_separator(total_w) do
    IO.ANSI.faint() <>
      String.duplicate("━", total_w) <> IO.ANSI.reset()
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

  defp vpad(s, width) do
    visual_len =
      s
      |> String.replace(~r/\e\[[0-9;]*m/, "")
      |> String.length()

    pad = width - visual_len
    if pad > 0, do: s <> String.duplicate(" ", pad), else: s
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
