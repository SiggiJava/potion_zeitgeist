defmodule PotionZeitgeist.Invoicing.LetterLayout do
  @moduledoc """
  The boxes of the printed invoice that hold free text, and how many lines a
  text prints with in them. The sizes match the layout in
  lib/potion_zeitgeist_web/components/invoice.css.

  The invoice brings its own font (Inter, in priv/static/fonts/inter), so
  the width of every line is known in advance. Lines are broken here the way
  the browser breaks them: at spaces, after a hyphen between two letters, and
  inside a word that is wider than the box. Where the browser has more ways
  to break a line, it needs fewer lines than counted here, never more.

  A text over its limit still prints cleanly, it only moves what follows
  further down (see invoice.css). The limits keep the address in the window
  of the envelope, the letterhead above it and the footer out of the text.
  """

  @boxes %{
    # Letterhead, top right.
    sender: %{width_mm: 85, size_pt: 8.5, lines: 7, name: "the letterhead"},
    # Address field, below the return address.
    recipient: %{width_mm: 80, size_pt: 10, lines: 6, name: "the address field"},
    # Footer with bank details, at the bottom of every page.
    footer: %{width_mm: 165, size_pt: 7.5, lines: 4, name: "the footer"},
    # The tax number line, at the top of the footer.
    tax_id: %{width_mm: 165, size_pt: 7.5, lines: 1, name: "the footer"}
  }

  # Advance widths of Inter Regular as shipped, in font units (2048 per em),
  # measured in Chromium. Each row starts with the code point of its first
  # character in hex: U+0020 to U+007E, U+00A0 to U+017F, then punctuation.
  # Any other character counts as 1 em, about as wide as a "W".
  #
  # Kerning moves some pairs of letters apart ("rn", "AA"), so each character
  # counts @kerning units more. Checked against Chromium with 18,000 made-up
  # addresses, letterheads and footers, also in capitals: never fewer lines
  # than the browser, and one more for 1 or 2 in 100, texts that just about
  # fill their last line.
  @units_per_em 2048
  @kerning 20
  @widths """
          0020 576 589 954 1297 1314 2011 1319 614 747 747 1026 1355 590 942 590 738
          0030 1292 833 1249 1265 1323 1215 1270 1159 1267 1270 590 618 1355 1355 1355 1047
          0040 1978 1413 1340 1496 1478 1231 1209 1528 1522 550 1169 1376 1158 1850 1543 1566
          0050 1308 1566 1318 1314 1322 1524 1413 2018 1397 1390 1288 747 738 747 965 934
          0060 661 1150 1254 1170 1254 1194 758 1256 1211 496 496 1124 496 1794 1210 1228
          0070 1254 1254 771 1081 670 1211 1151 1676 1118 1151 1131 873 681 873 1355
          00A0 576 589 1170 1251 1484 1126 553 1164 1210 1872 929 1193 1355 0 1364 978
          00B0 933 1355 905 913 661 1200 1234 590 549 623 988 1193 1643 1735 1806 1047
          00C0 1413 1413 1413 1413 1413 1413 2035 1496 1231 1231 1231 1231 550 550 550 550
          00D0 1505 1543 1566 1566 1566 1566 1566 1355 1566 1524 1524 1524 1524 1390 1302 1262
          00E0 1150 1150 1150 1150 1150 1150 1879 1170 1194 1194 1194 1194 496 496 496 496
          00F0 1193 1210 1228 1228 1228 1228 1228 1355 1228 1211 1211 1211 1211 1151 1254 1151
          0100 1413 1150 1413 1150 1413 1150 1496 1170 1496 1170 1496 1170 1496 1170 1478 1454
          0110 1505 1254 1231 1194 1231 1194 1231 1194 1231 1194 1231 1194 1528 1256 1528 1256
          0120 1528 1256 1528 1256 1522 1211 1590 1211 550 496 550 496 550 496 550 496
          0130 550 496 1719 992 1169 496 1376 1124 1076 1158 496 1158 496 1158 696 1152
          0140 736 1218 496 1543 1210 1543 1210 1543 1210 1237 1543 1210 1566 1228 1566 1228
          0150 1566 1228 2058 2047 1318 771 1318 771 1318 771 1314 1081 1314 1081 1314 1081
          0160 1314 1081 1322 670 1322 770 1322 670 1524 1211 1524 1211 1524 1211 1524 1211
          0170 1524 1211 1524 1211 2018 1676 1390 1151 1390 1288 1131 1288 1131 1288 1131 644
          2009 372
          2010 682 682
          2013 1024 2048
          2018 534 534 494
          201C 902 902 862
          2022 1152
          2026 1770
          202F 288
          20AC 1365
          2122 1251
          2212 1355
          """
          |> String.split("\n", trim: true)
          |> Enum.flat_map(fn row ->
            [first | widths] = String.split(row)

            widths
            |> Enum.map(&String.to_integer/1)
            |> Enum.with_index(String.to_integer(first, 16))
            |> Enum.map(fn {width, char} -> {char, width} end)
          end)
          |> Map.new()

  @doc "How many lines `box` holds: `:sender`, `:recipient`, `:footer` or `:tax_id`."
  def max_lines(box), do: Map.fetch!(@boxes, box).lines

  @doc """
  The lines `text` prints with in `box`: every line break starts a line,
  blank lines included, and a line wider than the box takes several.
  """
  def printed_lines(text, box), do: text |> line_counts(box) |> Enum.sum()

  @doc "`:ok`, or `{:error, message}` when `text` takes more lines than `box` holds."
  def check(text, box) do
    %{lines: max, name: name} = Map.fetch!(@boxes, box)
    counts = line_counts(text, box)
    total = Enum.sum(counts)
    wrapped = for {count, number} <- Enum.with_index(counts, 1), count > 1, do: number

    cond do
      total <= max ->
        :ok

      max == 1 ->
        {:error, "is too long for one line of #{name}"}

      wrapped == [] ->
        {:error, "has #{total} lines, #{name} has room for #{max}"}

      true ->
        {:error,
         "takes #{total} lines in #{name}, which has room for #{max}: " <>
           "#{numbered(wrapped)} too long for one line"}
    end
  end

  defp numbered([number]), do: "line #{number} is"

  defp numbered(numbers) do
    {rest, [last]} = Enum.split(numbers, -1)
    "lines #{Enum.join(rest, ", ")} and #{last} are"
  end

  # The printed lines of each line of `text`. The letter prints texts
  # trimmed, see `PotionZeitgeist.Invoicing.Letter.build/2`.
  defp line_counts(text, box) do
    case String.trim(text || "") do
      "" -> []
      text -> text |> String.split(["\r\n", "\n", "\r"]) |> Enum.map(&wrapped_lines(&1, box))
    end
  end

  # Fills lines like the browser: a piece of text goes on the current line
  # if it fits and starts the next line otherwise. A piece wider than a whole
  # line is split between its characters (overflow-wrap: break-word). Runs of
  # spaces print as one space and none at the start or end of a line.
  defp wrapped_lines(line, box) do
    available = available_units(box)
    space = width(" ")

    {lines, _used} =
      line
      |> String.split([" ", "\t"], trim: true)
      |> Enum.reduce({1, 0}, fn word, acc ->
        word
        |> pieces()
        |> Enum.with_index()
        |> Enum.reduce(acc, fn {piece, index}, {lines, used} ->
          gap = if index == 0 and used > 0, do: space, else: 0
          width = width(piece)

          cond do
            used + gap + width <= available -> {lines, used + gap + width}
            used > 0 -> split_piece(piece, lines + 1, available)
            true -> split_piece(piece, lines, available)
          end
        end)
      end)

    lines
  end

  # A word may break after a hyphen between two letters ("Berlin-|Mitte"),
  # not before a digit ("A-1", "12-14").
  defp pieces(word), do: String.split(word, ~r/(?<=\p{L}-)(?=\p{L})/u)

  # Places `piece` at the start of line `lines`, on further lines if needed.
  defp split_piece(piece, lines, available) do
    piece
    |> String.graphemes()
    |> Enum.reduce({lines, 0}, fn char, {lines, used} ->
      width = width(char)

      if used > 0 and used + width > available,
        do: {lines + 1, width},
        else: {lines, used + width}
    end)
  end

  # The box width in font units of its text size.
  defp available_units(box) do
    %{width_mm: width, size_pt: size} = Map.fetch!(@boxes, box)
    width / (size * 25.4 / 72) * @units_per_em
  end

  defp width(text) do
    text
    |> String.to_charlist()
    |> Enum.reduce(0, fn char, sum -> sum + char_width(char) end)
  end

  defp char_width(char), do: Map.get(@widths, char, @units_per_em) + @kerning
end
