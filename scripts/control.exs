# Dashboard Control Interface
#
# Usage:
#   mix run scripts/control.exs <state_file>
#
# Commands:
#   add TICKER      Add instrument to all panes
#   remove TICKER   Remove instrument from all panes
#   list            Show current instruments and settings
#   bar TIMEFRAME   Change chart timeframe
#   help            Show available commands
#
# State file is managed by dashboard.sh

require Logger
Logger.configure(level: :none)

defmodule DashboardControl do
  @moduledoc false

  @valid_bars ~w(1m 3m 5m 15m 30m 1H 2H 4H 6H 8H 12H 1D 3D 1W 1M)

  defstruct [
    :state_file,
    :project_dir,
    :pane_ids,
    instruments: [],
    bar: "1m",
    demo: false,
    use_scanner: false
  ]

  def start(state_file) do
    state = load_state(state_file)

    IO.write("\e[H\e[2J")
    print_header()
    print_status(state)
    IO.puts("")
    print_help()

    command_loop(state)
  end

  defp command_loop(state) do
    prompt = IO.ANSI.cyan() <> "> " <> IO.ANSI.reset()
    IO.write(prompt)

    input =
      case IO.gets("") do
        :eof -> "quit"
        {:error, _} -> "quit"
        line -> String.trim(line)
      end

    case parse_command(input) do
      :quit ->
        IO.puts("Exiting control pane.")

      :help ->
        print_help()
        command_loop(state)

      :list ->
        print_status(state)
        command_loop(state)

      {:add, ticker} ->
        state = add_instrument(state, ticker)
        command_loop(state)

      {:remove, ticker} ->
        state = remove_instrument(state, ticker)
        command_loop(state)

      {:bar, timeframe} ->
        state = change_bar(state, timeframe)
        command_loop(state)

      :empty ->
        command_loop(state)

      {:unknown, cmd} ->
        IO.puts(IO.ANSI.red() <> "Unknown command: #{cmd}" <> IO.ANSI.reset())
        IO.puts("Type 'help' for available commands.")
        command_loop(state)
    end
  end

  defp parse_command(""), do: :empty
  defp parse_command("quit" <> _), do: :quit
  defp parse_command("exit" <> _), do: :quit
  defp parse_command("help" <> _), do: :help
  defp parse_command("list" <> _), do: :list
  defp parse_command("status" <> _), do: :list

  defp parse_command("add " <> rest) do
    ticker = rest |> String.trim() |> String.upcase()
    if ticker == "", do: {:unknown, "add"}, else: {:add, ticker}
  end

  defp parse_command("remove " <> rest) do
    ticker = rest |> String.trim() |> String.upcase()
    if ticker == "", do: {:unknown, "remove"}, else: {:remove, ticker}
  end

  defp parse_command("rm " <> rest) do
    ticker = rest |> String.trim() |> String.upcase()
    if ticker == "", do: {:unknown, "rm"}, else: {:remove, ticker}
  end

  defp parse_command("bar " <> rest) do
    tf = String.trim(rest)
    if tf == "", do: {:unknown, "bar"}, else: {:bar, tf}
  end

  defp parse_command(cmd), do: {:unknown, cmd}

  # ============================================================================
  # Commands
  # ============================================================================

  defp add_instrument(state, ticker) do
    cond do
      ticker in state.instruments ->
        IO.puts("#{ticker} is already in the instrument list.")
        state

      length(state.instruments) >= 4 ->
        IO.puts(IO.ANSI.yellow() <> "Maximum 4 instruments supported." <> IO.ANSI.reset())
        state

      true ->
        new_instruments = state.instruments ++ [ticker]
        IO.puts("Adding #{ticker}...")

        new_state = %{state | instruments: new_instruments}
        save_state(new_state)
        respawn_all_panes(new_state)
        update_tmux_status(new_state)

        IO.puts(IO.ANSI.green() <> "Added #{ticker}." <> IO.ANSI.reset())
        print_status(new_state)
        new_state
    end
  end

  defp remove_instrument(state, ticker) do
    cond do
      ticker not in state.instruments ->
        IO.puts("#{ticker} is not in the instrument list.")
        state

      length(state.instruments) <= 1 ->
        IO.puts(IO.ANSI.yellow() <> "Cannot remove the last instrument." <> IO.ANSI.reset())
        state

      true ->
        new_instruments = Enum.reject(state.instruments, &(&1 == ticker))
        IO.puts("Removing #{ticker}...")

        new_state = %{state | instruments: new_instruments}
        save_state(new_state)
        respawn_all_panes(new_state)
        update_tmux_status(new_state)

        IO.puts(IO.ANSI.green() <> "Removed #{ticker}." <> IO.ANSI.reset())
        print_status(new_state)
        new_state
    end
  end

  defp change_bar(state, bar) do
    if bar not in @valid_bars do
      IO.puts(IO.ANSI.red() <> "Invalid timeframe: #{bar}" <> IO.ANSI.reset())
      IO.puts("Valid: #{Enum.join(@valid_bars, ", ")}")
      state
    else
      IO.puts("Changing chart timeframe to #{bar}...")

      new_state = %{state | bar: bar}
      save_state(new_state)
      respawn_chart_pane(new_state)
      update_chart_title(new_state)

      IO.puts(IO.ANSI.green() <> "Chart timeframe set to #{bar}." <> IO.ANSI.reset())
      new_state
    end
  end

  # ============================================================================
  # Tmux Pane Management
  # ============================================================================

  defp respawn_all_panes(state) do
    respawn_chart_pane(state)
    respawn_tickers_pane(state)
    respawn_trades_pane(state)
    respawn_orderbook_pane(state)
    respawn_funding_pane(state)
  end

  defp respawn_chart_pane(state) do
    inst_str = Enum.join(state.instruments, " ")
    demo_flag = if state.demo, do: "--demo", else: ""
    cmd = "mix run scripts/chart.exs #{inst_str} --bar #{state.bar} #{demo_flag}"
    tmux_respawn(state.pane_ids.chart, state.project_dir, cmd)
    update_chart_title(state)
  end

  defp respawn_tickers_pane(state) do
    inst_str = Enum.join(state.instruments, " ")
    demo_flag = if state.demo, do: "--demo", else: ""

    cmd =
      if state.use_scanner do
        "mix run scripts/scanner.exs --top 15 #{demo_flag}"
      else
        "mix run scripts/tickers.exs #{inst_str} #{demo_flag}"
      end

    tmux_respawn(state.pane_ids.tickers, state.project_dir, cmd)
  end

  defp respawn_trades_pane(state) do
    inst_str = Enum.join(state.instruments, " ")
    demo_flag = if state.demo, do: "--demo", else: ""
    cmd = "mix run scripts/trades.exs #{inst_str} --max 15 #{demo_flag}"
    tmux_respawn(state.pane_ids.trades, state.project_dir, cmd)
  end

  defp respawn_orderbook_pane(state) do
    inst_str = Enum.join(state.instruments, " ")
    demo_flag = if state.demo, do: "--demo", else: ""
    cmd = "mix run scripts/orderbook.exs #{inst_str} #{demo_flag}"
    tmux_respawn(state.pane_ids.orderbook, state.project_dir, cmd)
  end

  defp respawn_funding_pane(state) do
    inst_str = Enum.join(state.instruments, " ")
    demo_flag = if state.demo, do: "--demo", else: ""
    cmd = "mix run scripts/funding.exs #{inst_str} #{demo_flag}"
    tmux_respawn(state.pane_ids.funding, state.project_dir, cmd)
  end

  defp tmux_respawn(pane_id, project_dir, cmd) do
    System.cmd("tmux", [
      "respawn-pane",
      "-t",
      pane_id,
      "-k",
      "-c",
      project_dir,
      cmd
    ])
  end

  defp update_chart_title(state) do
    title =
      if length(state.instruments) > 1 do
        "Charts (#{length(state.instruments)}) [#{state.bar}]"
      else
        "Chart [#{hd(state.instruments)} #{state.bar}]"
      end

    System.cmd("tmux", ["select-pane", "-t", state.pane_ids.chart, "-T", title])
  end

  defp update_tmux_status(state) do
    inst_str = Enum.join(state.instruments, " ")

    System.cmd("tmux", [
      "set-option",
      "-t",
      "blofin-dashboard",
      "status-right",
      " #{inst_str} | %H:%M:%S "
    ])
  end

  # ============================================================================
  # State File
  # ============================================================================

  defp load_state(state_file) do
    data = File.read!(state_file) |> Jason.decode!()

    %__MODULE__{
      state_file: state_file,
      project_dir: data["project_dir"],
      pane_ids: %{
        chart: data["pane_chart"],
        tickers: data["pane_tickers"],
        trades: data["pane_trades"],
        orderbook: data["pane_orderbook"],
        funding: data["pane_funding"]
      },
      instruments: data["instruments"],
      bar: data["bar"],
      demo: data["demo"],
      use_scanner: data["use_scanner"] || false
    }
  end

  defp save_state(state) do
    data = %{
      "project_dir" => state.project_dir,
      "pane_chart" => state.pane_ids.chart,
      "pane_tickers" => state.pane_ids.tickers,
      "pane_trades" => state.pane_ids.trades,
      "pane_orderbook" => state.pane_ids.orderbook,
      "pane_funding" => state.pane_ids.funding,
      "instruments" => state.instruments,
      "bar" => state.bar,
      "demo" => state.demo,
      "use_scanner" => state.use_scanner
    }

    File.write!(state.state_file, Jason.encode!(data, pretty: true))
  end

  # ============================================================================
  # Display
  # ============================================================================

  defp print_header do
    IO.puts("")

    IO.puts(
      "  " <> IO.ANSI.bright() <> "BloFin Dashboard Control" <> IO.ANSI.reset()
    )

    IO.puts("  " <> String.duplicate("━", 40))
  end

  defp print_status(state) do
    IO.puts("")

    IO.puts(
      "  " <> IO.ANSI.faint() <> "Instruments:" <> IO.ANSI.reset() <>
        " " <> IO.ANSI.green() <> Enum.join(state.instruments, ", ") <> IO.ANSI.reset()
    )

    IO.puts(
      "  " <> IO.ANSI.faint() <> "Timeframe: " <> IO.ANSI.reset() <>
        " " <> IO.ANSI.cyan() <> state.bar <> IO.ANSI.reset()
    )

    IO.puts(
      "  " <> IO.ANSI.faint() <> "Mode:      " <> IO.ANSI.reset() <>
        " " <> if(state.demo, do: "Demo", else: "Live")
    )
  end

  defp print_help do
    IO.puts(
      "  " <> IO.ANSI.faint() <> "Commands:" <> IO.ANSI.reset()
    )

    IO.puts("    add TICKER      Add instrument")
    IO.puts("    remove TICKER   Remove instrument")
    IO.puts("    bar TIMEFRAME   Change chart timeframe")
    IO.puts("    list            Show current settings")
    IO.puts("    help            Show this help")
  end
end

state_file =
  case System.argv() do
    [file] ->
      file

    _ ->
      IO.puts("Usage: mix run scripts/control.exs <state_file>")
      System.halt(1)
  end

DashboardControl.start(state_file)
