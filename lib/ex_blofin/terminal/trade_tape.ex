defmodule ExBlofin.Terminal.TradeTape do
  @moduledoc """
  Real-time trade tape (time & sales) display in the terminal.

  Streams trade executions via WebSocket and renders a scrolling
  table with price, size, and side for each trade.

  ## Usage

  From the terminal:

      mix run scripts/trades.exs BTC-USDT
      mix run scripts/trades.exs BTC-USDT ETH-USDT --max 40

  From iex:

      {:ok, pid} = ExBlofin.Terminal.TradeTape.start(["BTC-USDT"])
      ExBlofin.Terminal.TradeTape.stop(pid)
  """

  use GenServer

  require Logger

  alias ExBlofin.Terminal.{Format, Screen}

  alias ExBlofin.WebSocket.PublicConnection

  defstruct [
    :prev_frame,
    :conn_pid,
    inst_ids: [],
    trades: [],
    max_trades: 50,
    buy_count: 0,
    sell_count: 0,
    dirty: false
  ]

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Starts the trade tape display.

  ## Options

    - `:max` - Maximum number of trades to display (default: 50)
    - `:demo` - Use demo environment (default: false)
  """
  def start(inst_ids, opts \\ []) when is_list(inst_ids) do
    GenServer.start_link(__MODULE__, {inst_ids, opts})
  end

  @doc "Stops the trade tape display."
  def stop(pid), do: GenServer.stop(pid, :normal)

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init({inst_ids, opts}) do
    max_trades = Keyword.get(opts, :max, 50)
    demo = Keyword.get(opts, :demo, false)

    {:ok, conn_pid} = PublicConnection.start_link(demo: demo)
    PublicConnection.add_subscriber(conn_pid, self())

    channels =
      Enum.map(inst_ids, &%{"channel" => "trades", "instId" => &1})

    PublicConnection.subscribe(conn_pid, channels)

    state = %__MODULE__{
      conn_pid: conn_pid,
      inst_ids: inst_ids,
      max_trades: max_trades
    }

    render_waiting(inst_ids)
    :timer.send_interval(100, :do_render)
    {:ok, state}
  end

  @impl GenServer
  def handle_info({:blofin_event, :trades, events}, state) do
    {buys, sells} =
      Enum.reduce(events, {0, 0}, fn e, {b, s} ->
        if e.side == "buy", do: {b + 1, s}, else: {b, s + 1}
      end)

    trades =
      (events ++ state.trades)
      |> Enum.take(state.max_trades)

    {:noreply,
     %{
       state
       | trades: trades,
         buy_count: state.buy_count + buys,
         sell_count: state.sell_count + sells,
         dirty: true
     }}
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
  # Terminal Rendering
  # ============================================================================

  defp render_waiting(inst_ids) do
    IO.write("\e[H\e[2J")
    IO.puts("")
    IO.puts("  Connecting to #{Enum.join(inst_ids, ", ")} trades...")
    IO.puts("  Waiting for data...")
  end

  defp render(state) do
    multi = length(state.inst_ids) > 1
    header = Enum.join(state.inst_ids, ", ")

    lines =
      [
        "",
        title_line(header),
        divider(),
        column_header(multi),
        divider(),
        format_trades(state.trades, multi),
        divider(),
        footer_line(state)
      ]
      |> List.flatten()

    Screen.write_frame(lines, state.prev_frame)
  end

  defp title_line(header) do
    IO.ANSI.bright() <>
      "  Trade Tape — #{header}" <>
      IO.ANSI.reset()
  end

  defp divider do
    "  " <> String.duplicate("─", 68)
  end

  defp column_header(multi) do
    inst_col = if multi, do: "Instrument  │", else: ""

    IO.ANSI.faint() <>
      "  Time     │#{inst_col}" <>
      " Side │    Price       │     Size     " <>
      IO.ANSI.reset()
  end

  defp format_trades(trades, multi) do
    Enum.map(trades, fn trade ->
      color =
        if trade.side == "buy",
          do: IO.ANSI.green(),
          else: IO.ANSI.red()

      reset = IO.ANSI.reset()
      ts = format_timestamp(trade.ts)
      side = pad_right(trade.side, 4)
      price = pad_right(format_number(trade.price), 14)
      size = pad_right(trade.size, 12)

      inst_col =
        if multi,
          do: pad_right(trade.inst_id, 12) <> "│",
          else: ""

      "  #{color}#{ts} │#{inst_col}" <>
        " #{side} │#{price} │#{size}#{reset}"
    end)
  end

  defp footer_line(state) do
    total = state.buy_count + state.sell_count
    total_vol = total_volume(state.trades)

    ratio =
      if total > 0,
        do: "#{pct(state.buy_count, total)}B/#{pct(state.sell_count, total)}S",
        else: "--"

    IO.ANSI.faint() <>
      "  Trades: #{add_commas(total)} " <>
      " Vol: #{format_number(total_vol)} " <>
      " Ratio: #{ratio}" <>
      IO.ANSI.reset()
  end

  # ============================================================================
  # Formatting Helpers
  # ============================================================================

  defp total_volume(trades) do
    Enum.reduce(trades, 0.0, fn t, acc ->
      acc + parse_float(t.size)
    end)
  end

  defp pct(n, total), do: "#{round(n / total * 100)}%"

  # Shared implementations live in ExBlofin.Terminal.Format/Screen; these
  # thin wrappers keep the local call sites unchanged.
  defp parse_float(v), do: Format.parse_float(v)

  defp format_number(v) when is_binary(v) do
    # Unparseable values are echoed rather than shown as 0.00.
    if Float.parse(v) == :error, do: v, else: Format.format_number(v)
  end

  defp format_number(v), do: Format.format_number(v)
  defp pad_right(s, w), do: Format.pad_right(s, w)
  defp format_timestamp(v), do: Format.format_timestamp(v)
  defp add_commas(s), do: Format.add_commas(s)
end
