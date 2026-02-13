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

  alias ExBlofin.WebSocket.PublicConnection

  @col_w 12
  @panel_w 3 * @col_w + 4
  @separator " │ "

  defstruct [
    :conn_pid,
    :levels,
    inst_ids: [],
    books: %{},
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
    count = length(inst_ids)
    default_levels = if count <= 2, do: 10, else: 7
    levels = Keyword.get(opts, :levels, default_levels)
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

  @impl GenServer
  def handle_info({:blofin_event, channel, [book]}, state)
      when channel in [:books, :books5] do
    inst_id = book.inst_id

    if Map.has_key?(state.books, inst_id) do
      book_state = Map.get(state.books, inst_id)
      updated = apply_book_update(book_state, book)

      {:noreply, %{state | books: Map.put(state.books, inst_id, updated), dirty: true}}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(:do_render, %{dirty: true} = state) do
    render(state)
    {:noreply, %{state | dirty: false}}
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
  # Book State Management
  # ============================================================================

  defp apply_book_update(book_state, book) do
    case book.action do
      "snapshot" ->
        %{
          book_state
          | asks: sort_asks(book.asks),
            bids: sort_bids(book.bids),
            last_update: book.ts
        }

      _ ->
        asks = apply_deltas(book_state.asks, book.asks, :asc)
        bids = apply_deltas(book_state.bids, book.bids, :desc)
        %{book_state | asks: asks, bids: bids, last_update: book.ts}
    end
  end

  defp apply_deltas(existing, deltas, direction) do
    updated =
      Enum.reduce(deltas, existing, fn delta, acc ->
        [price | _] = delta
        size = Enum.at(delta, 1, "0")
        acc = Enum.reject(acc, fn [p | _] -> p == price end)
        if size == "0", do: acc, else: [delta | acc]
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
    panels =
      Enum.map(state.inst_ids, fn id ->
        book = Map.get(state.books, id)
        build_panel(id, book, state.levels)
      end)

    rows = Enum.chunk_every(panels, 2)

    output =
      rows
      |> Enum.map(&merge_horizontal/1)
      |> Enum.intersperse(row_separator())
      |> List.flatten()
      |> then(fn lines -> ["" | lines] ++ [""] end)
      |> Enum.map(fn line -> "\e[2K" <> line end)

    IO.write("\e[H" <> Enum.join(output, "\n") <> "\e[J")
  end

  defp merge_horizontal([panel]) do
    empty =
      List.duplicate(vpad("", @panel_w), length(panel))

    merge_horizontal([panel, empty])
  end

  defp merge_horizontal([left, right]) do
    max_lines = max(length(left), length(right))
    empty = vpad("", @panel_w)
    left = left ++ List.duplicate(empty, max_lines - length(left))

    right =
      right ++ List.duplicate(empty, max_lines - length(right))

    Enum.zip_with([left, right], fn [l, r] ->
      l <> @separator <> r
    end)
  end

  defp row_separator do
    total_w = 2 * @panel_w + String.length(@separator)

    [
      "",
      IO.ANSI.faint() <>
        String.duplicate("━", total_w) <> IO.ANSI.reset()
    ]
  end

  # ============================================================================
  # Panel Building
  # ============================================================================

  defp build_panel(inst_id, %{asks: [], bids: []}, _levels) do
    [
      IO.ANSI.bright() <>
        "  #{inst_id}" <> IO.ANSI.reset(),
      divider("─"),
      "",
      IO.ANSI.faint() <>
        "  Waiting for data..." <> IO.ANSI.reset(),
      ""
    ]
    |> Enum.map(&vpad(&1, @panel_w))
  end

  defp build_panel(inst_id, book_state, levels) do
    top_asks =
      book_state.asks |> Enum.take(levels) |> Enum.reverse()

    top_bids = Enum.take(book_state.bids, levels)
    best_ask = List.first(book_state.asks)
    best_bid = List.first(book_state.bids)
    {spread, spread_pct, mid} = calc_spread(best_ask, best_bid)
    ts = format_timestamp(book_state.last_update)

    [
      header_line(inst_id, ts),
      divider("─"),
      column_header(),
      divider("─"),
      format_levels(top_asks, :ask),
      spread_line(spread, spread_pct),
      format_levels(top_bids, :bid),
      divider("─"),
      footer_line(mid, top_asks, top_bids)
    ]
    |> List.flatten()
    |> Enum.map(&vpad(&1, @panel_w))
  end

  defp header_line(inst_id, ts) do
    left = "  #{inst_id}"
    visual_right = 2 + String.length(ts)
    pad = max(@panel_w - String.length(left) - visual_right, 1)

    IO.ANSI.bright() <>
      left <>
      String.duplicate(" ", pad) <>
      IO.ANSI.green() <>
      "●" <>
      IO.ANSI.reset() <>
      IO.ANSI.bright() <> " #{ts}" <> IO.ANSI.reset()
  end

  defp divider(char) do
    "  " <> String.duplicate(char, @panel_w - 2)
  end

  defp column_header do
    IO.ANSI.faint() <>
      "  #{pad_center("Price", @col_w)}│" <>
      "#{pad_center("Size", @col_w)}│" <>
      "#{pad_center("Total", @col_w)}" <>
      IO.ANSI.reset()
  end

  defp spread_line(spread, spread_pct) do
    text =
      "  Spread: $#{format_number(spread)} " <>
        "(#{format_pct(spread_pct)})"

    eq = "  " <> String.duplicate("═", @panel_w - 2)

    [
      IO.ANSI.bright() <> eq <> IO.ANSI.reset(),
      IO.ANSI.yellow() <> text <> IO.ANSI.reset(),
      IO.ANSI.bright() <> eq <> IO.ANSI.reset()
    ]
  end

  defp format_levels(levels, side) do
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
          "  #{color}#{pad_right(format_price(price), @col_w)}│" <>
            "#{pad_right(format_int(size), @col_w)}│" <>
            "#{pad_right(format_int(cum), @col_w)}#{reset}"

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

  defp parse_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp format_price(n) when is_float(n) do
    n
    |> :erlang.float_to_binary(decimals: 2)
    |> add_commas()
  end

  defp format_number(n) when is_float(n) do
    n
    |> :erlang.float_to_binary(decimals: 2)
    |> add_commas()
  end

  defp format_int(n) when is_float(n) do
    n
    |> round()
    |> Integer.to_string()
    |> add_commas()
  end

  defp format_pct(n) when is_float(n) do
    "#{:erlang.float_to_binary(n, decimals: 4)}%"
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

  defp pad_center(s, width) do
    len = String.length(s)

    if len >= width do
      s
    else
      left = div(width - len, 2)
      right = width - len - left

      String.duplicate(" ", left) <>
        s <> String.duplicate(" ", right)
    end
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

  defp vpad(s, width) do
    visual_len =
      s
      |> String.replace(~r/\e\[[0-9;]*m/, "")
      |> String.length()

    pad = width - visual_len
    if pad > 0, do: s <> String.duplicate(" ", pad), else: s
  end
end
