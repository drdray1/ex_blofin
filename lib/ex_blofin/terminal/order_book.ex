defmodule ExBlofin.Terminal.OrderBook do
  @moduledoc """
  Real-time order book display in the terminal.

  Streams order book data via WebSocket and renders a live-updating
  table with bids, asks, spread, and cumulative depth.

  ## Usage

  From the terminal:

      mix run scripts/orderbook.exs BTC-USDT
      mix run scripts/orderbook.exs ETH-USDT --levels 20

  From iex:

      {:ok, pid} = ExBlofin.Terminal.OrderBook.start("BTC-USDT")
      ExBlofin.Terminal.OrderBook.stop(pid)
  """

  use GenServer

  require Logger

  alias ExBlofin.WebSocket.PublicConnection

  defstruct [
    :conn_pid,
    :inst_id,
    :last_update,
    asks: [],
    bids: [],
    levels: 15,
    dirty: false
  ]

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Starts the real-time order book display.

  ## Options

    - `:levels` - Number of price levels to display (default: 15)
    - `:demo` - Use demo environment (default: false)
  """
  def start(inst_id, opts \\ []) do
    GenServer.start_link(__MODULE__, {inst_id, opts})
  end

  @doc "Stops the order book display."
  def stop(pid), do: GenServer.stop(pid, :normal)

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init({inst_id, opts}) do
    levels = Keyword.get(opts, :levels, 15)
    demo = Keyword.get(opts, :demo, false)

    {:ok, conn_pid} = PublicConnection.start_link(demo: demo)
    PublicConnection.add_subscriber(conn_pid, self())
    PublicConnection.subscribe(conn_pid, [%{"channel" => "books", "instId" => inst_id}])

    state = %__MODULE__{
      conn_pid: conn_pid,
      inst_id: inst_id,
      levels: levels
    }

    render_waiting(inst_id)
    :timer.send_interval(100, :do_render)
    {:ok, state}
  end

  @impl GenServer
  def handle_info({:blofin_event, channel, [book]}, state)
      when channel in [:books, :books5] do
    state = apply_book_update(state, book)
    {:noreply, %{state | dirty: true}}
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

  defp apply_book_update(state, book) do
    case book.action do
      "snapshot" ->
        %{state | asks: sort_asks(book.asks), bids: sort_bids(book.bids), last_update: book.ts}

      _ ->
        asks = apply_deltas(state.asks, book.asks, :asc)
        bids = apply_deltas(state.bids, book.bids, :desc)
        %{state | asks: asks, bids: bids, last_update: book.ts}
    end
  end

  defp apply_deltas(existing, deltas, direction) do
    updated =
      Enum.reduce(deltas, existing, fn delta, acc ->
        [price | _] = delta
        size = Enum.at(delta, 1, "0")

        acc = Enum.reject(acc, fn [p | _] -> p == price end)

        if size == "0" do
          acc
        else
          [delta | acc]
        end
      end)

    case direction do
      :asc -> sort_asks(updated)
      :desc -> sort_bids(updated)
    end
  end

  defp sort_asks(levels) do
    Enum.sort_by(levels, fn [price | _] -> parse_float(price) end, :asc)
  end

  defp sort_bids(levels) do
    Enum.sort_by(levels, fn [price | _] -> parse_float(price) end, :desc)
  end

  defp parse_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  # ============================================================================
  # Terminal Rendering
  # ============================================================================

  defp render_waiting(inst_id) do
    IO.write("\e[H\e[2J")
    IO.puts("")
    IO.puts("  Connecting to #{inst_id} order book...")
    IO.puts("  Waiting for data...")
  end

  defp render(state) do
    top_asks = state.asks |> Enum.take(state.levels) |> Enum.reverse()
    top_bids = Enum.take(state.bids, state.levels)

    best_ask = List.first(state.asks)
    best_bid = List.first(state.bids)

    {spread, spread_pct, mid} = calc_spread(best_ask, best_bid)

    ts_display = format_timestamp(state.last_update)

    col_w = 14
    total_w = 3 * col_w + 4

    lines =
      [
        "",
        header_line(state.inst_id, ts_display, total_w),
        divider(total_w, "─"),
        column_header("Ask Price", "Size", "Total", col_w),
        divider(total_w, "─"),
        format_levels(top_asks, col_w, :ask),
        spread_line(spread, spread_pct, total_w),
        format_levels(top_bids, col_w, :bid),
        divider(total_w, "─"),
        footer_line(mid, top_asks, top_bids, total_w),
        ""
      ]
      |> List.flatten()
      |> Enum.map(fn line -> "\e[2K" <> line end)

    # Cursor home, draw lines, clear remaining screen below
    IO.write("\e[H" <> Enum.join(lines, "\n") <> "\e[J")
  end

  defp header_line(inst_id, ts, width) do
    left = "  #{inst_id} Order Book"
    right = "Live #{IO.ANSI.green()}●#{IO.ANSI.reset()} #{ts}  "
    pad = max(width - String.length(left) - String.length(ts) - 8, 1)
    "#{IO.ANSI.bright()}#{left}#{String.duplicate(" ", pad)}#{right}#{IO.ANSI.reset()}"
  end

  defp divider(width, char), do: "  #{String.duplicate(char, width)}"

  defp column_header(c1, c2, c3, w) do
    "  #{IO.ANSI.faint()}#{pad_center(c1, w)}│#{pad_center(c2, w)}│#{pad_center(c3, w)}#{IO.ANSI.reset()}"
  end

  defp spread_line(spread, spread_pct, width) do
    text = "  Spread: $#{format_number(spread)} (#{format_pct(spread_pct)})"

    [
      "  #{IO.ANSI.bright()}#{String.duplicate("═", width)}#{IO.ANSI.reset()}",
      "#{IO.ANSI.yellow()}#{text}#{IO.ANSI.reset()}",
      "  #{IO.ANSI.bright()}#{String.duplicate("═", width)}#{IO.ANSI.reset()}"
    ]
  end

  defp footer_line(mid, asks, bids, _width) do
    ask_vol = total_volume(asks)
    bid_vol = total_volume(bids)

    "  #{IO.ANSI.faint()}Mid: $#{format_number(mid)}   " <>
      "Vol(asks): #{format_int(ask_vol)}   " <>
      "Vol(bids): #{format_int(bid_vol)}#{IO.ANSI.reset()}"
  end

  defp format_levels(levels, col_w, side) do
    color = if side == :ask, do: IO.ANSI.red(), else: IO.ANSI.green()
    reset = IO.ANSI.reset()

    {_, rows} =
      Enum.reduce(levels, {0.0, []}, fn level, {cumulative, rows} ->
        [price_s, size_s | _] = level
        price = parse_float(price_s)
        size = parse_float(size_s)
        cumulative = cumulative + size

        row =
          "  #{color}#{pad_right(format_price(price), col_w)}│" <>
            "#{pad_right(format_int(size), col_w)}│" <>
            "#{pad_right(format_int(cumulative), col_w)}#{reset}"

        {cumulative, rows ++ [row]}
      end)

    rows
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
    Enum.reduce(levels, 0.0, fn [_, size_s | _], acc -> acc + parse_float(size_s) end)
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
      [int_part, dec_part] -> add_commas_int(int_part) <> "." <> dec_part
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
    if len >= width, do: s, else: do_pad_center(s, width, len)
  end

  defp do_pad_center(s, width, len) do
    left = div(width - len, 2)
    right = width - len - left
    String.duplicate(" ", left) <> s <> String.duplicate(" ", right)
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
