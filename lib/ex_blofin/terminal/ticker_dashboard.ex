defmodule ExBlofin.Terminal.TickerDashboard do
  @moduledoc """
  Real-time ticker dashboard in the terminal.

  Streams ticker data via WebSocket and renders a live-updating
  watchlist with price, 24h change, volume, and bid/ask.

  ## Usage

  From the terminal:

      mix run scripts/tickers.exs BTC-USDT ETH-USDT SOL-USDT

  From iex:

      {:ok, pid} = ExBlofin.Terminal.TickerDashboard.start(["BTC-USDT", "ETH-USDT"])
      ExBlofin.Terminal.TickerDashboard.stop(pid)
  """

  use GenServer

  require Logger

  alias ExBlofin.WebSocket.PublicConnection

  defstruct [
    :conn_pid,
    inst_ids: [],
    tickers: %{},
    dirty: false
  ]

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Starts the ticker dashboard.

  ## Options

    - `:demo` - Use demo environment (default: false)
  """
  def start(inst_ids, opts \\ []) when is_list(inst_ids) do
    GenServer.start_link(__MODULE__, {inst_ids, opts})
  end

  @doc "Stops the ticker dashboard."
  def stop(pid), do: GenServer.stop(pid, :normal)

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init({inst_ids, opts}) do
    demo = Keyword.get(opts, :demo, false)

    {:ok, conn_pid} = PublicConnection.start_link(demo: demo)
    PublicConnection.add_subscriber(conn_pid, self())

    channels =
      Enum.map(inst_ids, &%{"channel" => "tickers", "instId" => &1})

    PublicConnection.subscribe(conn_pid, channels)

    state = %__MODULE__{
      conn_pid: conn_pid,
      inst_ids: inst_ids
    }

    render_waiting(inst_ids)
    :timer.send_interval(100, :do_render)
    {:ok, state}
  end

  @impl GenServer
  def handle_info({:blofin_event, :tickers, events}, state) do
    tickers =
      Enum.reduce(events, state.tickers, fn event, acc ->
        Map.put(acc, event.inst_id, event)
      end)

    {:noreply, %{state | tickers: tickers, dirty: true}}
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
    IO.puts("  Connecting to #{Enum.join(inst_ids, ", ")} tickers...")
    IO.puts("  Waiting for data...")
  end

  defp render(state) do
    lines =
      [
        "",
        title_line(),
        divider(),
        column_header(),
        divider(),
        format_rows(state),
        divider(),
        ""
      ]
      |> List.flatten()
      |> Enum.map(fn line -> "\e[2K" <> line end)

    IO.write("\e[H" <> Enum.join(lines, "\n") <> "\e[J")
  end

  defp title_line do
    IO.ANSI.bright() <>
      "  Ticker Dashboard" <>
      IO.ANSI.reset()
  end

  defp divider do
    "  " <> String.duplicate("─", 88)
  end

  defp column_header do
    IO.ANSI.faint() <>
      "  " <>
      pad_right("Instrument", 14) <>
      "│" <>
      pad_right(" Last", 14) <>
      "│" <>
      pad_right(" 24h Chg", 12) <>
      "│" <>
      pad_right(" 24h %", 9) <>
      "│" <>
      pad_right(" High", 14) <>
      "│" <>
      pad_right(" Low", 14) <>
      "│" <>
      " Volume" <>
      IO.ANSI.reset()
  end

  defp format_rows(state) do
    Enum.map(state.inst_ids, fn id ->
      case Map.get(state.tickers, id) do
        nil ->
          IO.ANSI.faint() <>
            "  #{pad_right(id, 14)}│  Waiting..." <>
            IO.ANSI.reset()

        ticker ->
          format_ticker_row(ticker)
      end
    end)
  end

  defp format_ticker_row(t) do
    last = parse_float(t.last)
    open = parse_float(t.open_24h)
    high = parse_float(t.high_24h)
    low = parse_float(t.low_24h)
    vol = parse_float(t.vol_24h)
    change = last - open
    change_pct = if open > 0, do: change / open * 100, else: 0.0
    color = if change >= 0, do: IO.ANSI.green(), else: IO.ANSI.red()
    arrow = if change >= 0, do: "▲", else: "▼"
    reset = IO.ANSI.reset()

    "  " <>
      pad_right(t.inst_id, 14) <>
      "│" <>
      color <>
      pad_right(" #{fmt_price(last)}", 14) <>
      "│" <>
      pad_right(" #{sign(change)}#{fmt_price(abs(change))}", 12) <>
      "│" <>
      pad_right(" #{arrow}#{fmt_pct(change_pct)}", 9) <>
      reset <>
      "│" <>
      pad_right(" #{fmt_price(high)}", 14) <>
      "│" <>
      pad_right(" #{fmt_price(low)}", 14) <>
      "│" <>
      " #{fmt_int(vol)}"
  end

  # ============================================================================
  # Formatting Helpers
  # ============================================================================

  defp sign(n) when n >= 0, do: "+"
  defp sign(_), do: "-"

  defp parse_float(nil), do: 0.0

  defp parse_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp fmt_price(n) do
    n |> :erlang.float_to_binary(decimals: 2) |> add_commas()
  end

  defp fmt_pct(n) do
    "#{:erlang.float_to_binary(abs(n), decimals: 2)}%"
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

  defp pad_right(s, width) do
    len = String.length(s)
    if len >= width, do: s, else: s <> String.duplicate(" ", width - len)
  end
end
