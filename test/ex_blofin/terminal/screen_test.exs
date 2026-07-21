defmodule ExBlofin.Terminal.ScreenTest do
  @moduledoc """
  The frame-diffing contract. These assertions are what make it safe to render
  at 10Hz: an unchanged frame must cost nothing, and a changed one must cost
  only the rows that moved.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias ExBlofin.Terminal.{Format, Screen}

  defp write(lines, prev), do: capture_io(fn -> Screen.write_frame(lines, prev) end)

  describe "write_frame/2 first paint" do
    test "clears and writes every line" do
      out = write(["a", "b", "c"], nil)

      assert out =~ "\e[H\e[2J"
      assert out =~ "a"
      assert out =~ "b"
      assert out =~ "c"
    end

    test "addresses each row explicitly" do
      out = write(["a", "b"], nil)

      assert out =~ "\e[1;1H"
      assert out =~ "\e[2;1H"
    end
  end

  describe "write_frame/2 diffing" do
    test "an identical frame writes nothing at all" do
      frame = ["header", "row 1", "row 2", "footer"]

      assert write(frame, frame) == ""
    end

    test "only the changed row is written" do
      prev = ["header", "50000.00", "footer"]
      next = ["header", "50001.00", "footer"]

      out = write(next, prev)

      assert out =~ "50001.00"
      refute out =~ "header"
      refute out =~ "footer"
    end

    test "the changed row is addressed by its index" do
      prev = ["a", "b", "c"]
      next = ["a", "b", "CHANGED"]

      out = write(next, prev)

      # Third row -> row 3, one-based.
      assert out =~ "\e[3;1H"
      refute out =~ "\e[1;1H"
      refute out =~ "\e[2;1H"
    end

    test "several changed rows are all written, in order" do
      prev = ["a", "b", "c", "d"]
      next = ["a", "B", "c", "D"]

      out = write(next, prev)

      assert out =~ "B"
      assert out =~ "D"
      refute out =~ "\e[1;1H"

      # Rows must be emitted top-down so the cursor walks forward.
      assert :binary.match(out, "\e[2;1H") < :binary.match(out, "\e[4;1H")
    end

    test "rows dropped since the previous frame are erased" do
      # Otherwise a taller previous frame leaves stale content below the new one.
      prev = ["a", "b", "c", "stale", "stale"]
      next = ["a", "b", "c"]

      out = write(next, prev)

      assert out =~ "\e[4;1H"
      assert out =~ "\e[5;1H"
      assert out =~ "\e[2K"
      refute out =~ "stale"
    end

    test "rows added since the previous frame are written" do
      out = write(["a", "b", "c"], ["a"])

      assert out =~ "b"
      assert out =~ "c"
      refute out =~ "\e[1;1H"
    end

    test "returns the frame for use as the next previous" do
      frame = ["a", "b"]
      assert capture_io(fn -> assert Screen.write_frame(frame, nil) == frame end) != ""
    end
  end

  describe "write_frame/2 cost" do
    test "a quiet frame costs orders of magnitude less than a full repaint" do
      # 40 rows of a busy order book, one row ticking.
      prev = for i <- 1..40, do: "row #{i} 50000.00 1.2345 61728.39"
      next = List.replace_at(prev, 20, "row 21 50001.00 1.2345 61729.62")

      full = write(next, nil)
      diffed = write(next, prev)

      assert byte_size(diffed) < byte_size(full) / 10
    end
  end

  describe "size/0" do
    test "returns a plausible size, falling back rather than raising" do
      assert {rows, cols} = Screen.size()
      assert is_integer(rows) and rows > 0
      assert is_integer(cols) and cols > 0
    end
  end

  describe "waiting/1" do
    test "returns lines rather than writing them" do
      assert [_, line, _] = Screen.waiting("Waiting for data...")
      assert line =~ "Waiting for data..."
    end
  end

  describe "cursor handling" do
    test "restore/1 makes the cursor visible again" do
      out = capture_io(fn -> Screen.restore(24) end)

      assert out =~ "\e[?25h"
      assert out =~ "\e[24;1H"
    end

    test "hide and show emit the paired sequences" do
      assert capture_io(&Screen.hide_cursor/0) =~ "\e[?25l"
      assert capture_io(&Screen.show_cursor/0) =~ "\e[?25h"
    end
  end

  describe "integration with Format" do
    test "diffing is unaffected by ANSI colour in unchanged rows" do
      row = IO.ANSI.green() <> Format.pad_right("BTC-USDT", 12) <> IO.ANSI.reset()
      frame = ["header", row]

      assert write(frame, frame) == ""
    end
  end

  describe "misc" do
    test "ansi?/0 reports a boolean" do
      assert is_boolean(Screen.ansi?())
    end

    test "clear/0 homes the cursor and clears" do
      assert capture_io(&Screen.clear/0) =~ "\e[H\e[2J"
    end

    test "restore/0 defaults to the detected terminal height" do
      assert capture_io(fn -> Screen.restore() end) =~ "\e[?25h"
    end

    test "an empty frame against an empty previous writes nothing" do
      assert write([], []) == ""
    end

    test "write_frame/1 defaults to a full repaint" do
      out = capture_io(fn -> Screen.write_frame(["a"]) end)
      assert out =~ "\e[H\e[2J"
    end
  end
end
