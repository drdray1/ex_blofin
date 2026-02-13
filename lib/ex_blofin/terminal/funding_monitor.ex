defmodule ExBlofin.Terminal.FundingMonitor do
  @moduledoc """
  Real-time funding rate monitor in the terminal.

  Streams funding rate data via WebSocket for perpetual futures
  and displays current rates, annualized rates, and countdown
  to next funding.

  ## Usage

  From the terminal:

      mix run scripts/funding.exs BTC-USDT ETH-USDT SOL-USDT

  From iex:

      {:ok, pid} = ExBlofin.Terminal.FundingMonitor.start(["BTC-USDT", "ETH-USDT"])
      ExBlofin.Terminal.FundingMonitor.stop(pid)
  """

  use GenServer

  require Logger

  alias ExBlofin.WebSocket.PublicConnection

  defstruct [
    :conn_pid,
    inst_ids: [],
    rates: %{},
    dirty: false
  ]

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Starts the funding rate monitor.

  ## Options

    - `:demo` - Use demo environment (default: false)
  """
  def start(inst_ids, opts \\ []) when is_list(inst_ids) do
    GenServer.start_link(__MODULE__, {inst_ids, opts})
  end

  @doc "Stops the funding rate monitor."
  def stop(pid), do: GenServer.stop(pid, :normal)

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init({inst_ids, opts}) do
    demo = Keyword.get(opts, :demo, false)

    # Fetch initial funding rates via REST
    client = ExBlofin.Client.new(nil, nil, nil, demo: demo)
    initial_rates = fetch_initial_rates(client, inst_ids)

    # Connect WebSocket for live updates
    {:ok, conn_pid} = PublicConnection.start_link(demo: demo)
    PublicConnection.add_subscriber(conn_pid, self())

    channels =
      Enum.map(
        inst_ids,
        &%{"channel" => "funding-rate", "instId" => &1}
      )

    PublicConnection.subscribe(conn_pid, channels)

    state = %__MODULE__{
      conn_pid: conn_pid,
      inst_ids: inst_ids,
      rates: initial_rates,
      dirty: map_size(initial_rates) > 0
    }

    render_waiting(inst_ids)
    :timer.send_interval(1000, :do_render)
    {:ok, state}
  end

  @impl GenServer
  def handle_info({:blofin_event, :"funding-rate", events}, state) do
    rates =
      Enum.reduce(events, state.rates, fn event, acc ->
        Map.put(acc, event.inst_id, event)
      end)

    {:noreply, %{state | rates: rates, dirty: true}}
  end

  @impl GenServer
  def handle_info(:do_render, state) do
    # Always render on tick to update countdown timers
    if map_size(state.rates) > 0 do
      render(state)
    end

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
  # Data Fetching
  # ============================================================================

  defp fetch_initial_rates(client, inst_ids) do
    Enum.reduce(inst_ids, %{}, fn id, acc ->
      case ExBlofin.MarketData.get_funding_rate(client, instId: id) do
        {:ok, [data | _]} ->
          rate = %{
            inst_id: data["instId"] || id,
            funding_rate: data["fundingRate"],
            next_funding_rate: data["nextFundingRate"],
            funding_time: data["fundingTime"],
            next_funding_time: data["nextFundingTime"]
          }

          Map.put(acc, id, rate)

        _ ->
          acc
      end
    end)
  end

  # ============================================================================
  # Terminal Rendering
  # ============================================================================

  defp render_waiting(inst_ids) do
    IO.write("\e[H\e[2J")
    IO.puts("")

    IO.puts("  Connecting to #{Enum.join(inst_ids, ", ")} funding rates...")

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
        legend(),
        ""
      ]
      |> List.flatten()
      |> Enum.map(fn line -> "\e[2K" <> line end)

    IO.write("\e[H" <> Enum.join(lines, "\n") <> "\e[J")
  end

  defp title_line do
    IO.ANSI.bright() <>
      "  Funding Rate Monitor" <>
      IO.ANSI.reset()
  end

  defp divider do
    "  " <> String.duplicate("─", 78)
  end

  defp column_header do
    IO.ANSI.faint() <>
      "  " <>
      pad_right("Instrument", 14) <>
      "│" <>
      pad_right(" Current", 12) <>
      "│" <>
      pad_right(" Annualized", 13) <>
      "│" <>
      pad_right(" Next Rate", 12) <>
      "│" <>
      " Next Funding" <>
      IO.ANSI.reset()
  end

  defp format_rows(state) do
    Enum.map(state.inst_ids, fn id ->
      case Map.get(state.rates, id) do
        nil ->
          IO.ANSI.faint() <>
            "  #{pad_right(id, 14)}│  Waiting..." <>
            IO.ANSI.reset()

        rate ->
          format_rate_row(rate)
      end
    end)
  end

  defp format_rate_row(r) do
    current = parse_float(r.funding_rate)
    next = parse_float(r.next_funding_rate)
    # 3 funding periods per day * 365 days
    annualized = current * 3 * 365 * 100
    color = rate_color(current)
    reset = IO.ANSI.reset()
    countdown = format_countdown(r.next_funding_time)

    "  " <>
      pad_right(r.inst_id, 14) <>
      "│" <>
      color <>
      pad_right(" #{fmt_rate(current)}", 12) <>
      "│" <>
      pad_right(" #{fmt_pct(annualized)}", 13) <>
      reset <>
      "│" <>
      rate_color(next) <>
      pad_right(" #{fmt_rate(next)}", 12) <>
      reset <>
      "│ " <>
      countdown
  end

  defp legend do
    IO.ANSI.faint() <>
      "  " <>
      IO.ANSI.green() <>
      "■" <>
      IO.ANSI.reset() <>
      IO.ANSI.faint() <>
      " Negative = longs paid   " <>
      IO.ANSI.red() <>
      "■" <>
      IO.ANSI.reset() <>
      IO.ANSI.faint() <>
      " Positive = longs pay" <>
      IO.ANSI.reset()
  end

  # ============================================================================
  # Formatting Helpers
  # ============================================================================

  defp rate_color(rate) when rate < 0, do: IO.ANSI.green()
  defp rate_color(rate) when rate > 0, do: IO.ANSI.red()
  defp rate_color(_), do: IO.ANSI.faint()

  defp parse_float(nil), do: 0.0

  defp parse_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp fmt_rate(n) do
    sign = if n >= 0, do: "+", else: ""
    "#{sign}#{:erlang.float_to_binary(n * 100, decimals: 4)}%"
  end

  defp fmt_pct(n) do
    sign = if n >= 0, do: "+", else: ""
    "#{sign}#{:erlang.float_to_binary(n, decimals: 2)}%"
  end

  defp format_countdown(nil), do: "--:--:--"

  defp format_countdown(ts) when is_binary(ts) do
    case Integer.parse(ts) do
      {ms, _} ->
        now_ms = System.system_time(:millisecond)
        diff_s = max(div(ms - now_ms, 1000), 0)
        hours = div(diff_s, 3600)
        minutes = div(rem(diff_s, 3600), 60)
        seconds = rem(diff_s, 60)

        h = String.pad_leading("#{hours}", 2, "0")
        m = String.pad_leading("#{minutes}", 2, "0")
        s = String.pad_leading("#{seconds}", 2, "0")
        "#{h}:#{m}:#{s}"

      :error ->
        ts
    end
  end

  defp pad_right(s, width) do
    len = String.length(s)
    if len >= width, do: s, else: s <> String.duplicate(" ", width - len)
  end
end
