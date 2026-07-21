defmodule ExBlofin.Terminal.FormatTest do
  use ExUnit.Case, async: true

  doctest ExBlofin.Terminal.Format

  alias ExBlofin.Terminal.Format

  describe "parse_float/1" do
    test "accepts every shape the API has been seen to send" do
      assert Format.parse_float("50000.5") == 50_000.5
      assert Format.parse_float(50_000.5) == 50_000.5
      assert Format.parse_float(50_000) == 50_000.0
      assert Format.parse_float(nil) == 0.0
      assert Format.parse_float("") == 0.0
      assert Format.parse_float("garbage") == 0.0
      assert Format.parse_float(%{}) == 0.0
    end

    test "handles negative and exponent forms" do
      assert Format.parse_float("-1.5") == -1.5
      assert Format.parse_float("1.0e-8") == 1.0e-8
    end
  end

  describe "format_price/1 precision" do
    test "keeps two decimals for large prices" do
      assert Format.format_price("50000.5") == "50,000.50"
      assert Format.format_price("1234.567") == "1,234.57"
    end

    test "shows sub-cent prices instead of collapsing them to 0.00" do
      # The old formatter hardcoded decimals: 2, so every one of these — and
      # therefore most of the instrument universe — rendered as "0.00".
      refute Format.format_price("0.00000123") == "0.00"
      assert Format.format_price("0.00000123") == "0.00000123"
      assert Format.format_price("0.0001234") == "0.000123"
      assert Format.format_price("0.05123") == "0.05123"
    end

    test "scales decimals with magnitude" do
      assert Format.price_decimals(5000.0) == 2
      assert Format.price_decimals(5.0) == 4
      assert Format.price_decimals(0.05) == 5
      assert Format.price_decimals(0.0005) == 6
      assert Format.price_decimals(0.000005) == 8
    end

    test "zero renders cleanly" do
      assert Format.format_price("0") == "0.00"
    end
  end

  describe "format_size/1" do
    test "keeps fractional contract sizes visible" do
      # The old helper round()ed, so fractional sizes became "0".
      refute Format.format_size("0.5") == "0"
      assert Format.format_size("0.5") == "0.5"
      assert Format.format_size("0.0025") == "0.0025"
    end

    test "drops noise decimals on whole sizes" do
      assert Format.format_size("100") == "100"
      assert Format.format_size("1500") == "1,500"
      assert Format.format_size("0") == "0"
    end
  end

  describe "add_commas/1" do
    test "groups the integer part only" do
      assert Format.add_commas("1234567.89") == "1,234,567.89"
      assert Format.add_commas("100") == "100"
      assert Format.add_commas("1000") == "1,000"
    end

    test "does not put a comma after a minus sign" do
      assert Format.add_commas("-1234.5") == "-1,234.5"
    end
  end

  describe "ANSI-aware measurement" do
    test "visual_length ignores escape sequences" do
      assert Format.visual_length("up") == 2
      assert Format.visual_length(IO.ANSI.green() <> "up" <> IO.ANSI.reset()) == 2
    end

    test "padding aligns coloured and plain text identically" do
      plain = Format.pad_right("up", 10)
      coloured = Format.pad_right(IO.ANSI.green() <> "up" <> IO.ANSI.reset(), 10)

      assert Format.visual_length(plain) == 10
      assert Format.visual_length(coloured) == 10
    end

    test "pad_left and pad_center measure visually too" do
      coloured = IO.ANSI.red() <> "ab" <> IO.ANSI.reset()

      assert Format.visual_length(Format.pad_left(coloured, 8)) == 8
      assert Format.visual_length(Format.pad_center(coloured, 9)) == 9
    end

    test "padding never shrinks an over-long string" do
      assert Format.pad_right("toolong", 3) == "toolong"
    end
  end

  describe "fit/2" do
    test "pads short strings and truncates long ones" do
      assert Format.fit("ab", 5) == "ab   "
      assert Format.visual_length(Format.fit("abcdefgh", 5)) == 5
    end

    test "truncating a coloured string appends a reset so colour cannot bleed" do
      coloured = IO.ANSI.green() <> "abcdefgh" <> IO.ANSI.reset()
      out = Format.fit(coloured, 4)

      assert Format.visual_length(out) == 4
      assert String.ends_with?(out, IO.ANSI.reset())
    end

    test "an exact-width string is untouched" do
      assert Format.fit("abcde", 5) == "abcde"
    end

    test "zero width yields an empty string" do
      assert Format.truncate("abc", 0) == ""
    end
  end

  describe "format_timestamp/1" do
    test "renders HH:MM:SS from a millisecond epoch" do
      assert Format.format_timestamp("1697021343571") =~ ~r/^\d{2}:\d{2}:\d{2}$/
      assert Format.format_timestamp(1_697_021_343_571) =~ ~r/^\d{2}:\d{2}:\d{2}$/
    end

    test "degrades to a placeholder rather than crashing the render loop" do
      assert Format.format_timestamp(nil) == "--:--:--"
      assert Format.format_timestamp("not a number") == "--:--:--"
      assert Format.format_timestamp(%{}) == "--:--:--"
    end
  end

  describe "format_number/2 and format_pct/2" do
    test "honour an explicit decimal count" do
      assert Format.format_number("1234.5678") == "1,234.57"
      assert Format.format_number("1234.5678", 0) == "1,235"
      assert Format.format_number("1234.5678", 4) == "1,234.5678"
    end

    test "format_pct appends a percent sign" do
      assert Format.format_pct("1.23456") == "1.2346%"
      assert Format.format_pct("1.23456", 2) == "1.23%"
      assert Format.format_pct(nil) == "0.0000%"
    end
  end

  describe "format_int/1" do
    test "rounds and groups" do
      assert Format.format_int("1234.7") == "1,235"
      assert Format.format_int("999") == "999"
      assert Format.format_int(nil) == "0"
    end
  end

  describe "strip_ansi/1" do
    test "removes colour and cursor sequences alike" do
      assert Format.strip_ansi(IO.ANSI.green() <> "x" <> IO.ANSI.reset()) == "x"
      assert Format.strip_ansi("\e[2Krow") == "row"
      assert Format.strip_ansi("\e[10;1Hrow") == "row"
    end
  end

  describe "truncate/2 across escape boundaries" do
    test "keeps sequences that precede the cut" do
      s = IO.ANSI.red() <> "abc" <> IO.ANSI.green() <> "def"
      out = Format.truncate(s, 4)

      assert Format.visual_length(out) == 4
      assert out =~ IO.ANSI.red()
    end

    test "a string shorter than the width is returned unchanged" do
      assert Format.truncate("ab", 10) == "ab"
    end
  end
end
