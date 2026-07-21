defmodule ExBlofin.Terminal.Screen do
  @moduledoc """
  Terminal size detection and frame output for the terminal UIs.

  ## Frame diffing

  The terminal modules previously rewrote the entire screen on every tick:
  each render built one large binary of every line prefixed with `\\e[2K`, then
  wrote the whole thing at 10Hz whether or not anything had changed. On a
  40-row order book that is ~40 line erases and several kilobytes per frame,
  ten times a second, mostly to redraw identical bytes.

  `write_frame/2` compares the new frame against the previous one and emits
  only the lines that actually differ, addressing each by row. A quiet market
  costs a single cursor-position write; a busy one costs the handful of rows
  that moved. It also removes the visible tearing that came from repainting
  static chrome (borders, headers, legends) on every tick.

  Callers keep the returned frame and pass it back next time:

      frame = build_frame(state)
      prev = Screen.write_frame(frame, state.prev_frame)

  Pass `nil` as the previous frame to force a full repaint — done on the first
  render and whenever the terminal is resized.
  """

  @default_size {24, 80}

  @doc """
  Returns `{rows, cols}` for the current terminal, falling back to 24x80.
  """
  @spec size() :: {pos_integer(), pos_integer()}
  def size do
    with {:ok, rows} <- :io.rows(),
         {:ok, cols} <- :io.columns() do
      {rows, cols}
    else
      _ -> @default_size
    end
  end

  @doc """
  Whether ANSI output is appropriate for the current device.

  False when output is redirected to a file or a pipe, which is what made
  `mix run scripts/tickers.exs > out.txt` fill the file with escape sequences.
  """
  @spec ansi?() :: boolean()
  def ansi?, do: IO.ANSI.enabled?()

  @doc """
  Writes a frame, emitting only the lines that differ from `previous`.

  Returns the frame, to be passed back as `previous` on the next call.
  """
  @spec write_frame([String.t()], [String.t()] | nil) :: [String.t()]
  def write_frame(lines, previous \\ nil)

  def write_frame(lines, nil) do
    # Full repaint: clear, home, write everything as one iodata write. Building
    # iodata rather than joining into a binary avoids copying the whole frame.
    IO.write([clear_all(), interleave(lines)])
    lines
  end

  def write_frame(lines, previous) when is_list(previous) do
    case diff(lines, previous) do
      [] -> :ok
      changes -> IO.write(changes)
    end

    lines
  end

  # Emits a cursor-position + erase-line + content sequence per changed row.
  # Rows the caller dropped since last frame are erased so stale content from a
  # taller previous frame cannot linger below the new one.
  defp diff(lines, previous) do
    max_len = max(length(lines), length(previous))

    Enum.reduce((max_len - 1)..0//-1, [], fn idx, acc ->
      new = Enum.at(lines, idx)
      old = Enum.at(previous, idx)

      cond do
        new == old -> acc
        is_nil(new) -> [[goto(idx), erase_line()] | acc]
        true -> [[goto(idx), erase_line(), new] | acc]
      end
    end)
  end

  defp interleave(lines) do
    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, idx} -> [goto(idx), erase_line(), line] end)
  end

  defp goto(idx), do: ["\e[", Integer.to_string(idx + 1), ";1H"]

  defp erase_line, do: "\e[2K"

  defp clear_all, do: "\e[H\e[2J"

  @doc """
  Clears the screen and homes the cursor.
  """
  @spec clear() :: :ok
  def clear, do: IO.write(clear_all())

  @doc """
  Renders a placeholder shown before the first data arrives.
  """
  @spec waiting(String.t()) :: [String.t()]
  def waiting(message) do
    ["", "  #{message}", ""]
  end

  @doc """
  Hides the cursor. Paired with `show_cursor/0` on shutdown.

  Without this the cursor sits blinking in the middle of the redrawn frame.
  """
  @spec hide_cursor() :: :ok
  def hide_cursor, do: IO.write("\e[?25l")

  @doc """
  Shows the cursor and moves below the frame, leaving the shell usable.
  """
  @spec show_cursor() :: :ok
  def show_cursor, do: IO.write("\e[?25h")

  @doc """
  Restores the terminal on exit: cursor visible, positioned below the frame.

  Called from each module's `terminate/2` so quitting does not leave the shell
  prompt overwriting the last frame.
  """
  @spec restore(pos_integer()) :: :ok
  def restore(rows \\ nil) do
    row = rows || elem(size(), 0)
    IO.write(["\e[", Integer.to_string(row), ";1H", "\e[?25h", "\n"])
  end
end
