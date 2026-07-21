defmodule ExBlofin.Terminal.Format do
  @moduledoc """
  Shared value formatting for the terminal UIs.

  Every terminal module previously carried its own copy of these helpers. The
  copies had drifted — `parse_float/1` in particular accepted different input
  types in different modules — so a value that rendered fine in one pane could
  crash another.

  ## Precision

  `format_price/1` picks its decimal count from the magnitude of the value
  rather than hardcoding two places. Two decimals is right for BTC at 50,000
  and useless for an asset priced at 0.0000012, which would render as `0.00`
  along with every other sub-cent instrument.
  """

  @doc """
  Parses an exchange-supplied numeric value into a float.

  Accepts the string form the API actually sends, plus numbers and `nil`, since
  different endpoints have been observed to use all three for the same field.

      iex> alias ExBlofin.Terminal.Format
      iex> {Format.parse_float("1.5"), Format.parse_float(2), Format.parse_float(nil)}
      {1.5, 2.0, 0.0}
  """
  @spec parse_float(term()) :: float()
  def parse_float(nil), do: 0.0
  def parse_float(""), do: 0.0
  def parse_float(n) when is_float(n), do: n
  def parse_float(n) when is_integer(n), do: n * 1.0

  def parse_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  def parse_float(_), do: 0.0

  @doc """
  Formats a price with a decimal count chosen from its magnitude.

  Large values get few decimals because the integer part carries the
  information; small values get more because it is all they have.

      iex> alias ExBlofin.Terminal.Format
      iex> {Format.format_price(50_000.0), Format.format_price(0.00000123)}
      {"50,000.00", "0.00000123"}
  """
  @spec format_price(term()) :: String.t()
  def format_price(value) do
    n = parse_float(value)
    n |> :erlang.float_to_binary(decimals: price_decimals(abs(n))) |> add_commas()
  end

  @doc """
  Decimal places for a price of the given magnitude.

  The brackets follow how exchanges quote tick sizes: roughly two significant
  decimals past the leading digit, capped at 8 (the smallest tick BloFin uses).
  """
  @spec price_decimals(float()) :: non_neg_integer()
  def price_decimals(magnitude) do
    cond do
      magnitude == 0.0 -> 2
      magnitude >= 1_000 -> 2
      magnitude >= 1 -> 4
      magnitude >= 0.01 -> 5
      magnitude >= 0.0001 -> 6
      true -> 8
    end
  end

  @doc """
  Formats a quantity, keeping fractional contract sizes visible.

  The previous implementations rounded to an integer, so any instrument quoted
  in fractions rendered its whole size column as `0`.
  """
  @spec format_size(term()) :: String.t()
  def format_size(value) do
    n = parse_float(value)

    cond do
      n == 0.0 -> "0"
      n >= 1_000 -> n |> :erlang.float_to_binary(decimals: 0) |> add_commas()
      n >= 1 -> n |> :erlang.float_to_binary(decimals: 2) |> trim_zeros() |> add_commas()
      true -> n |> :erlang.float_to_binary(decimals: 4) |> trim_zeros()
    end
  end

  @doc """
  Formats a value as a plain number with a fixed number of decimals.
  """
  @spec format_number(term(), non_neg_integer()) :: String.t()
  def format_number(value, decimals \\ 2) do
    value
    |> parse_float()
    |> :erlang.float_to_binary(decimals: decimals)
    |> add_commas()
  end

  @doc """
  Formats a value as an integer with thousands separators.
  """
  @spec format_int(term()) :: String.t()
  def format_int(value) do
    value |> parse_float() |> round() |> Integer.to_string() |> add_commas()
  end

  @doc """
  Formats a percentage to four decimal places, with a trailing `%`.
  """
  @spec format_pct(term(), non_neg_integer()) :: String.t()
  def format_pct(value, decimals \\ 4) do
    "#{:erlang.float_to_binary(parse_float(value), decimals: decimals)}%"
  end

  @doc """
  Inserts thousands separators into the integer part of a numeric string.
  """
  @spec add_commas(String.t()) :: String.t()
  def add_commas(s) when is_binary(s) do
    case String.split(s, ".") do
      [int_part] -> add_commas_int(int_part)
      [int_part, dec_part] -> add_commas_int(int_part) <> "." <> dec_part
    end
  end

  defp add_commas_int("-" <> digits), do: "-" <> add_commas_int(digits)

  defp add_commas_int(s) do
    s
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp trim_zeros(s) do
    if String.contains?(s, ".") do
      s |> String.trim_trailing("0") |> String.trim_trailing(".")
    else
      s
    end
  end

  @doc """
  Formats a millisecond epoch timestamp as local wall-clock `HH:MM:SS`.

  Previously rendered in UTC with no label, which reads as a stalled clock to
  anyone not in UTC.
  """
  @spec format_timestamp(term()) :: String.t()
  def format_timestamp(nil), do: "--:--:--"

  def format_timestamp(ts) when is_binary(ts) do
    case Integer.parse(ts) do
      {ms, _} -> format_timestamp(ms)
      :error -> "--:--:--"
    end
  end

  def format_timestamp(ms) when is_integer(ms) do
    ms
    |> DateTime.from_unix!(:millisecond)
    |> DateTime.shift_zone!(local_time_zone(), Calendar.get_time_zone_database())
    |> Calendar.strftime("%H:%M:%S")
  rescue
    # Falls back to UTC when no tz database is configured, rather than crashing
    # the render loop over a cosmetic value.
    _ -> ms |> DateTime.from_unix!(:millisecond) |> Calendar.strftime("%H:%M:%S")
  end

  def format_timestamp(_), do: "--:--:--"

  defp local_time_zone do
    case :os.getenv(~c"TZ") do
      false -> "Etc/UTC"
      ~c"" -> "Etc/UTC"
      tz -> List.to_string(tz)
    end
  end

  # ===========================================================================
  # Padding
  # ===========================================================================

  @doc """
  Visible length of a string, ignoring ANSI escape sequences.

  Padding computed with `String.length/1` on a coloured string counts the
  escape bytes and silently shears the column.

      iex> ExBlofin.Terminal.Format.visual_length("\\e[32mup\\e[0m")
      2
  """
  @spec visual_length(String.t()) :: non_neg_integer()
  def visual_length(s), do: s |> strip_ansi() |> String.length()

  @doc """
  Removes ANSI escape sequences from a string.
  """
  @spec strip_ansi(String.t()) :: String.t()
  def strip_ansi(s), do: String.replace(s, ~r/\e\[[0-9;?]*[a-zA-Z]/, "")

  @doc "Pads on the right to `width` visible characters."
  @spec pad_right(String.t(), non_neg_integer()) :: String.t()
  def pad_right(s, width) do
    pad = width - visual_length(s)
    if pad > 0, do: s <> String.duplicate(" ", pad), else: s
  end

  @doc "Pads on the left to `width` visible characters."
  @spec pad_left(String.t(), non_neg_integer()) :: String.t()
  def pad_left(s, width) do
    pad = width - visual_length(s)
    if pad > 0, do: String.duplicate(" ", pad) <> s, else: s
  end

  @doc "Centres within `width` visible characters."
  @spec pad_center(String.t(), non_neg_integer()) :: String.t()
  def pad_center(s, width) do
    len = visual_length(s)

    if len >= width do
      s
    else
      left = div(width - len, 2)
      String.duplicate(" ", left) <> s <> String.duplicate(" ", width - len - left)
    end
  end

  @doc """
  Pads or truncates to exactly `width` visible characters.

  Truncation is the part the old `vpad/2` helpers were missing: they only ever
  padded, so on a narrow terminal an over-long row overflowed its panel and
  sheared every column to its right.
  """
  @spec fit(String.t(), non_neg_integer()) :: String.t()
  def fit(s, width) do
    case visual_length(s) - width do
      overflow when overflow > 0 -> truncate(s, width)
      0 -> s
      _ -> pad_right(s, width)
    end
  end

  @doc """
  Truncates to `width` visible characters, preserving ANSI sequences and
  appending a reset so colour cannot bleed past the cut.
  """
  @spec truncate(String.t(), non_neg_integer()) :: String.t()
  def truncate(_s, width) when width <= 0, do: ""

  def truncate(s, width) do
    if visual_length(s) <= width do
      s
    else
      {taken, _} = take_visible(s, width)
      taken <> IO.ANSI.reset()
    end
  end

  # Walks the string keeping escape sequences (zero visible width) and counting
  # only printable graphemes.
  defp take_visible(s, width) do
    Regex.split(~r/(\e\[[0-9;?]*[a-zA-Z])/, s, include_captures: true, trim: true)
    |> Enum.reduce({"", 0}, fn part, {acc, count} ->
      cond do
        count >= width -> {acc, count}
        String.starts_with?(part, "\e[") -> {acc <> part, count}
        true -> take_plain(part, acc, count, width)
      end
    end)
  end

  defp take_plain(part, acc, count, width) do
    remaining = width - count
    len = String.length(part)

    if len <= remaining do
      {acc <> part, count + len}
    else
      {acc <> String.slice(part, 0, remaining), width}
    end
  end
end
