defmodule ExBlofin.Terminal.MultiOrderBook do
  @moduledoc """
  Multi-instrument order book display in a grid layout.

  Displays 2-4 order books side by side in the terminal.
  Uses a 2-column grid: 2 instruments in a row, 3-4 in a 2x2 grid.

  ## Usage

  From the terminal:

      mix run scripts/orderbook.exs BTC-USDT ETH-USDT
      mix run scripts/orderbook.exs BTC-USDT ETH-USDT SOL-USDT DOGE-USDT

  From iex:

      {:ok, pid} = ExBlofin.Terminal.MultiOrderBook.start(["BTC-USDT", "ETH-USDT"])
      ExBlofin.Terminal.MultiOrderBook.stop(pid)
  """

  use GenServer

  require Logger

  alias ExBlofin.Terminal.{Format, Screen}

  alias ExBlofin.WebSocket.PublicConnection

  @separator " │ "
  @separator_visual_len 3

  # Fixed lines per panel: header + divider + col_header + divider + spread(3) + divider + footer
  @panel_overhead 9
  @min_levels 2
  @min_col_w 8

  defstruct [
    :prev_frame,
    :conn_pid,
    # nil = auto-size from terminal dimensions
    :levels,
    inst_ids: [],
    books: %{},
    last_size: {0, 0},
    dirty: false
  ]

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Starts the multi-instrument order book display.

  ## Options

    - `:levels` - Number of price levels per panel (default: 10 for 2, 7 for 3-4)
    - `:demo` - Use demo environment (default: false)
  """
  def start(inst_ids, opts \\ []) when is_list(inst_ids) do
    GenServer.start_link(__MODULE__, {inst_ids, opts})
  end

  @doc "Stops the multi order book display."
  def stop(pid), do: GenServer.stop(pid, :normal)

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init({inst_ids, opts}) do
    levels = Keyword.get(opts, :levels)
    demo = Keyword.get(opts, :demo, false)

    {:ok, conn_pid} = PublicConnection.start_link(demo: demo)
    PublicConnection.add_subscriber(conn_pid, self())

    channels =
      Enum.map(inst_ids, &%{"channel" => "books", "instId" => &1})

    PublicConnection.subscribe(conn_pid, channels)

    books =
      Map.new(inst_ids, fn id ->
        {id, %{asks: [], bids: [], last_update: nil}}
      end)

    state = %__MODULE__{
      conn_pid: conn_pid,
      inst_ids: inst_ids,
      levels: levels,
      books: books
    }

    render_waiting(inst_ids)
    :timer.send_interval(100, :do_render)
    {:ok, state}
  end

  # Matches any non-empty batch. The previous `[book]` pattern only matched a
  # single-element list, so a batched message fell through to the catch-all and
  # was dropped silently while the "Live" indicator stayed green.
  @impl GenServer
  def handle_info({:blofin_event, channel, [_ | _] = books}, state)
      when channel in [:books, :books5] do
    updated_books = Enum.reduce(books, state.books, &merge_book/2)
    {:noreply, %{state | books: updated_books, dirty: true}}
  end

  @impl GenServer
  def handle_info(:do_render, state) do
    size = get_terminal_size()
    resized? = size != state.last_size

    # A resize invalidates the diff baseline: the previous frame was laid out
    # for the old width, so force a full repaint rather than patching rows.
    state = if resized?, do: %{state | prev_frame: nil}, else: state

    state =
      if state.dirty or resized? do
        %{state | prev_frame: render(state)}
      else
        state
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
  #
  # Book State Management
  # ============================================================================
  defp merge_book(book, books) do
    case Map.fetch(books, book.inst_id) do
      {:ok, book_state} -> Map.put(books, book.inst_id, apply_book_update(book_state, book))
      :error -> books
    end
  end

  # ============================================================================

  # Only an explicit "update" action is treated as incremental. `action` is nil
  # whenever the payload arrives as a JSON array, and defaulting that to
  # incremental meant the snapshot BloFin re-sends after a reconnect was merged
  # into the stale book instead of replacing it — leaving price levels that had
  # since disappeared on screen forever.
  defp apply_book_update(book_state, book) do
    case book.action do
      "update" ->
        asks = apply_deltas(book_state.asks, book.asks, :asc)
        bids = apply_deltas(book_state.bids, book.bids, :desc)
        %{book_state | asks: asks, bids: bids, last_update: book.ts}

      _snapshot_or_unknown ->
        %{
          book_state
          | asks: sort_asks(book.asks),
            bids: sort_bids(book.bids),
            last_update: book.ts
        }
    end
  end

  defp apply_deltas(existing, deltas, direction) do
    updated =
      Enum.reduce(deltas, existing, fn delta, acc ->
        [price | _] = delta
        size = Enum.at(delta, 1, "0")
        target = Format.parse_float(price)
        acc = Enum.reject(acc, fn [p | _] -> Format.parse_float(p) == target end)
        if Format.parse_float(size) == 0.0, do: acc, else: [delta | acc]
      end)

    case direction do
      :asc -> sort_asks(updated)
      :desc -> sort_bids(updated)
    end
  end

  defp sort_asks(levels) do
    Enum.sort_by(levels, fn [p | _] -> parse_float(p) end, :asc)
  end

  defp sort_bids(levels) do
    Enum.sort_by(levels, fn [p | _] -> parse_float(p) end, :desc)
  end

  # ============================================================================
  # Terminal Rendering
  # ============================================================================

  defp render_waiting(inst_ids) do
    IO.write("\e[H\e[2J")
    IO.puts("")

    IO.puts("  Connecting to #{Enum.join(inst_ids, ", ")} order books...")

    IO.puts("  Waiting for data...")
  end

  defp render(state) do
    {max_grid_rows, levels} = effective_layout(state)
    {col_w, panel_w} = effective_widths()

    # Truncate instruments to what fits in available grid rows
    max_instruments = max_grid_rows * 2
    visible_ids = Enum.take(state.inst_ids, max_instruments)

    panels =
      Enum.map(visible_ids, fn id ->
        book = Map.get(state.books, id)
        build_panel(id, book, levels, col_w, panel_w)
      end)

    rows = Enum.chunk_every(panels, 2)

    output =
      rows
      |> Enum.map(&merge_horizontal(&1, panel_w))
      |> Enum.intersperse(row_separator(panel_w))
      |> List.flatten()
      |> then(fn lines -> ["" | lines] ++ [""] end)

    Screen.write_frame(output, state.prev_frame)
  end

  defp merge_horizontal([panel], panel_w) do
    empty =
      List.duplicate(vpad("", panel_w), length(panel))

    merge_horizontal([panel, empty], panel_w)
  end

  defp merge_horizontal([left, right], panel_w) do
    max_lines = max(length(left), length(right))
    empty = vpad("", panel_w)
    left = left ++ List.duplicate(empty, max_lines - length(left))

    right =
      right ++ List.duplicate(empty, max_lines - length(right))

    Enum.zip_with([left, right], fn [l, r] ->
      l <> @separator <> r
    end)
  end

  defp row_separator(panel_w) do
    total_w = 2 * panel_w + @separator_visual_len

    [
      "",
      IO.ANSI.faint() <>
        String.duplicate("━", total_w) <> IO.ANSI.reset()
    ]
  end

  # ============================================================================
  # Terminal Size
  # ============================================================================

  defp effective_widths do
    {_rows, cols} = get_terminal_size()
    # Two panels side by side: 2 * (3 * col_w + 4) + 3 = 6 * col_w + 11
    col_w = max(div(cols - @separator_visual_len - 8, 6), @min_col_w)
    panel_w = 3 * col_w + 4
    {col_w, panel_w}
  end

  defp effective_layout(state) do
    if state.levels do
      # Explicit levels — use original grid layout
      max_grid_rows = ceil(length(state.inst_ids) / 2)
      {max_grid_rows, state.levels}
    else
      {rows, _cols} = get_terminal_size()
      num_instruments = length(state.inst_ids)
      max_grid_rows = ceil(num_instruments / 2)

      # Try from max grid rows down to 1, find first that fits
      find_fitting_layout(rows, max_grid_rows)
    end
  end

  defp find_fitting_layout(rows, grid_rows) when grid_rows >= 1 do
    # overhead = 2 blanks + grid_rows * 9 fixed per panel + (grid_rows-1) * 2 separators
    overhead = 2 + grid_rows * @panel_overhead + max(grid_rows - 1, 0) * 2
    available = rows - overhead
    levels = div(available, grid_rows * 2)

    if levels >= @min_levels do
      {grid_rows, levels}
    else
      find_fitting_layout(rows, grid_rows - 1)
    end
  end

  defp find_fitting_layout(_rows, _grid_rows) do
    # Absolute minimum: 1 grid row, 2 levels
    {1, @min_levels}
  end

  # ============================================================================
  # Panel Building
  # ============================================================================

  defp build_panel(inst_id, %{asks: [], bids: []}, _levels, _col_w, panel_w) do
    [
      IO.ANSI.bright() <>
        "  #{inst_id}" <> IO.ANSI.reset(),
      divider("─", panel_w),
      "",
      IO.ANSI.faint() <>
        "  Waiting for data..." <> IO.ANSI.reset(),
      ""
    ]
    |> Enum.map(&vpad(&1, panel_w))
  end

  defp build_panel(inst_id, book_state, levels, col_w, panel_w) do
    top_asks =
      book_state.asks |> Enum.take(levels) |> Enum.reverse()

    top_bids = Enum.take(book_state.bids, levels)
    best_ask = List.first(book_state.asks)
    best_bid = List.first(book_state.bids)
    {spread, spread_pct, mid} = calc_spread(best_ask, best_bid)
    ts = format_timestamp(book_state.last_update)

    [
      header_line(inst_id, ts, panel_w),
      divider("─", panel_w),
      column_header(col_w),
      divider("─", panel_w),
      format_levels(top_asks, :ask, col_w),
      spread_line(spread, spread_pct, panel_w),
      format_levels(top_bids, :bid, col_w),
      divider("─", panel_w),
      footer_line(mid, top_asks, top_bids)
    ]
    |> List.flatten()
    |> Enum.map(&vpad(&1, panel_w))
  end

  defp header_line(inst_id, ts, panel_w) do
    left = "  #{inst_id}"
    visual_right = 2 + String.length(ts)
    pad = max(panel_w - String.length(left) - visual_right, 1)

    IO.ANSI.bright() <>
      left <>
      String.duplicate(" ", pad) <>
      IO.ANSI.green() <>
      "●" <>
      IO.ANSI.reset() <>
      IO.ANSI.bright() <> " #{ts}" <> IO.ANSI.reset()
  end

  defp divider(char, panel_w) do
    "  " <> String.duplicate(char, panel_w - 2)
  end

  defp column_header(col_w) do
    IO.ANSI.faint() <>
      "  #{pad_center("Price", col_w)}│" <>
      "#{pad_center("Size", col_w)}│" <>
      "#{pad_center("Total", col_w)}" <>
      IO.ANSI.reset()
  end

  defp spread_line(spread, spread_pct, panel_w) do
    text =
      "  Spread: $#{format_number(spread)} " <>
        "(#{format_pct(spread_pct)})"

    eq = "  " <> String.duplicate("═", panel_w - 2)

    [
      IO.ANSI.bright() <> eq <> IO.ANSI.reset(),
      IO.ANSI.yellow() <> text <> IO.ANSI.reset(),
      IO.ANSI.bright() <> eq <> IO.ANSI.reset()
    ]
  end

  defp format_levels(levels, side, col_w) do
    color =
      if side == :ask, do: IO.ANSI.red(), else: IO.ANSI.green()

    reset = IO.ANSI.reset()

    {_, rows} =
      Enum.reduce(levels, {0.0, []}, fn level, {cum, rows} ->
        [price_s, size_s | _] = level
        price = parse_float(price_s)
        size = parse_float(size_s)
        cum = cum + size

        row =
          "  #{color}#{pad_right(format_price(price), col_w)}│" <>
            "#{pad_right(format_int(size), col_w)}│" <>
            "#{pad_right(format_int(cum), col_w)}#{reset}"

        {cum, rows ++ [row]}
      end)

    rows
  end

  defp footer_line(mid, asks, bids) do
    ask_vol = total_volume(asks)
    bid_vol = total_volume(bids)

    IO.ANSI.faint() <>
      "  Mid:$#{format_number(mid)}" <>
      " A:#{format_int(ask_vol)}" <>
      " B:#{format_int(bid_vol)}" <>
      IO.ANSI.reset()
  end

  # ============================================================================
  # Formatting Helpers
  # ============================================================================

  defp calc_spread(nil, _), do: {0.0, 0.0, 0.0}
  defp calc_spread(_, nil), do: {0.0, 0.0, 0.0}

  defp calc_spread([ask_p | _], [bid_p | _]) do
    ask = parse_float(ask_p)
    bid = parse_float(bid_p)
    spread = ask - bid
    mid = (ask + bid) / 2
    pct = if mid > 0, do: spread / mid * 100, else: 0.0
    {spread, pct, mid}
  end

  defp total_volume(levels) do
    Enum.reduce(levels, 0.0, fn [_, s | _], acc ->
      acc + parse_float(s)
    end)
  end

  defp format_pct(n) when is_float(n) do
    "#{:erlang.float_to_binary(n, decimals: 4)}%"
  end

  # Shared implementations live in ExBlofin.Terminal.Format/Screen; these
  # thin wrappers keep the local call sites unchanged.
  defp parse_float(v), do: Format.parse_float(v)
  defp format_price(v), do: Format.format_price(v)
  defp format_int(v), do: Format.format_int(v)
  defp format_number(v), do: Format.format_number(v)
  defp pad_right(s, w), do: Format.pad_right(s, w)
  defp pad_center(s, w), do: Format.pad_center(s, w)
  defp format_timestamp(v), do: Format.format_timestamp(v)
  defp get_terminal_size, do: Screen.size()
  defp vpad(s, w), do: Format.fit(s, w)
end
