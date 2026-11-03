defmodule PotionZeitgeist.Invoicing.LetterLayout do
  @moduledoc """
  The boxes of the printed invoice that hold free text, and how many lines a
  text prints with in them. The sizes match the layout in
  lib/potion_zeitgeist_web/components/invoice.css.

  The letter prints with its own font (Inter, in priv/static/fonts/inter)
  and without ligatures or contextual alternates, so the width of a line is
  known in advance: priv/invoice_font/metrics.txt has the width of every
  character the font has and the kerning between them, read from the font
  files by generate_metrics.py there. A text with a character the font does
  not have, such as an emoji, is not accepted (see `check/3`): a browser
  would print it with a font of the computer, of a width not known here.

  Lines are broken where Chromium breaks them: at spaces, after hyphens and
  dashes (see break_after?/3) and, in a word wider than the box, between
  any two characters. Chromium breaks at further places, for example after
  "/" before "Ö", which can only make for fewer lines, except in a word
  wider than the box: there each character other than a letter or digit
  may end a line early, so each counts one line more. The count is
  therefore never lower than the lines Chromium prints. This was checked
  for the break opportunities between all characters of the font and
  against Chromium's line breaks for generated addresses, letterheads and
  footers.

  The widths are those of a browser that places characters at fractions of
  a pixel, as Chromium does with smoothed text, the default on every system.
  Chromium on Windows with font smoothing turned off rounds each character
  to whole pixels, and a minimum font size in the browser settings enlarges
  the small print; text can then take more lines than counted here. The
  print page notices that, warns, and keeps the room the footer really
  takes (see `PotionZeitgeistWeb.InvoiceComponents.print_toolbar/1`).

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
    tax_id: %{width_mm: 165, size_pt: 7.5, lines: 1, name: "the footer"},
    # The return address in small print above the recipient, made from the
    # letterhead by `PotionZeitgeist.Invoicing.Letter.build/2`.
    return: %{width_mm: 80, size_pt: 7, lines: 4, name: "the return address line"},
    # The unit of an item entered on the invoice form (see
    # `PotionZeitgeist.Invoicing.ManualItem`) in the table of items: the
    # 19 mm unit column less its 2 mm padding.
    unit: %{width_mm: 17, size_pt: 9.5, lines: 1, name: "the unit column"}
  }

  @metrics_path Path.expand("../../../priv/invoice_font/metrics.txt", __DIR__)
  @external_resource @metrics_path

  {units_per_em, widths, kerning} =
    @metrics_path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Enum.reduce({nil, %{}, %{}}, fn line, {units, widths, kerning} ->
      case String.split(line) do
        ["units_per_em", value] ->
          {String.to_integer(value), widths, kerning}

        ["w", first | values] ->
          first = String.to_integer(first, 16)

          widths =
            values
            |> Enum.with_index(first)
            |> Enum.reduce(widths, fn {width, char}, acc ->
              Map.put(acc, char, String.to_integer(width))
            end)

          {units, widths, kerning}

        ["k", first | pairs] ->
          first = String.to_integer(first, 16)

          kerning =
            Enum.reduce(pairs, kerning, fn pair, acc ->
              [second, value] = String.split(pair, ":")
              Map.put(acc, {first, String.to_integer(second, 16)}, String.to_integer(value))
            end)

          {units, widths, kerning}
      end
    end)

  @units_per_em units_per_em
  # Advance widths in font units of the characters the font has.
  @widths widths
  # Kerning in font units that moves a pair of characters apart.
  @kerning kerning

  # A character the font does not have counts as wide as the widest the
  # fonts of a computer print, for texts saved before such characters were
  # refused.
  @missing_width 3 * @units_per_em

  # Characters after which Chromium breaks a word before a letter or digit:
  # dashes, ellipsis, question mark and the narrow spaces.
  @breaking [0x2010, 0x2013, 0x2014, 0x2026, ??] ++
              [0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2008, 0x2009, 0x200A, 0x205F]

  # What may come before a dash at the start of a word: nothing, or a
  # no-break space.
  @word_start [nil, 0x00A0, 0x2007, 0x202F]

  @doc """
  How many lines `box` holds: `:sender`, `:recipient`, `:footer`, `:tax_id`,
  `:return` or `:unit`.
  """
  def max_lines(box), do: Map.fetch!(@boxes, box).lines

  @doc """
  `text` as the letter prints it: composed characters ("a" with a combining
  diaeresis becomes "ä"), and without invisible format characters such as
  soft hyphens or zero width spaces, which could change the line breaks.
  """
  def clean(nil), do: ""

  def clean(text) do
    case :unicode.characters_to_nfc_binary(text) do
      composed when is_binary(composed) -> String.replace(composed, ~r/\p{Cf}/u, "")
      # Bytes that are not UTF-8 count as the replacement character "�",
      # which the font does not have.
      _invalid -> text |> replace_invalid() |> clean()
    end
  end

  defp replace_invalid(text) do
    text
    |> String.codepoints()
    |> Enum.map_join(&if(String.valid?(&1), do: &1, else: "\uFFFD"))
  end

  @doc """
  The lines `text` prints with in `box`: every line break starts a line,
  blank lines included, and a line wider than the box takes several.
  """
  def printed_lines(text, box) do
    text
    |> typed_lines()
    |> counts(box)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sum()
  end

  @doc """
  `:ok`, or `{:error, message}` when `text` has a character the invoice
  font does not have or takes more lines than `box` holds.

  `fill` turns each line of `text` into the text it prints with, for
  example by filling in placeholders. Line numbers in messages are those of
  `text`.
  """
  def check(text, box, fill \\ &Function.identity/1) do
    text
    |> numbered_lines()
    |> Enum.map(fn {line, number} -> {fill.(line), number} end)
    |> check_lines(box)
  end

  @doc """
  Like `check/3`, for the lines of a text as they print, each with its
  number in the typed text, such as
  `PotionZeitgeist.Invoicing.Letter.fill_lines/2` gives them.
  """
  def check_lines(lines, box) do
    %{lines: max, name: name} = Map.fetch!(@boxes, box)
    lines = printed(lines)

    case unsupported(lines) do
      [] -> check_counts(counts(lines, box), box, max, name)
      chars -> unsupported_error(chars)
    end
  end

  @doc """
  `:ok`, or `{:error, message}` when `text` has a character the invoice
  font does not have, for texts printed outside the boxes, such as the
  invoice number.
  """
  def check_characters(text) do
    case text |> typed_lines() |> unsupported() do
      [] -> :ok
      chars -> unsupported_error(chars)
    end
  end

  defp unsupported_error(chars),
    do: {:error, "has characters the invoice font does not have: #{Enum.join(chars, " ")}"}

  defp check_counts(counts, box, max, name) do
    total = counts |> Enum.map(&elem(&1, 0)) |> Enum.sum()
    wrapped = for {_count, number, true} <- counts, do: number

    cond do
      total <= max ->
        :ok

      # The return address is made from the letterhead, see
      # `PotionZeitgeist.Invoicing.Letter.build/2`, so the message is about that.
      box == :return ->
        {:error,
         "gives a return address of #{total} lines above the recipient, which has room " <>
           "for #{max}: shorten the lines with name, street, postcode and city"}

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

  # Each line of `text` as it prints, with its number in `text`.
  defp typed_lines(text), do: text |> numbered_lines() |> printed()

  defp numbered_lines(text) do
    (text || "")
    |> String.split(["\r\n", "\n", "\r"])
    |> Enum.with_index(1)
  end

  # The letter prints texts trimmed (see
  # `PotionZeitgeist.Invoicing.Letter.build/2`), so blank lines at the start
  # and end do not count, nor does a line break at the start or end of a
  # filled in value there.
  defp printed(lines) do
    lines
    |> Enum.map(fn {line, number} -> {clean(line), number} end)
    |> Enum.drop_while(&blank?/1)
    |> Enum.reverse()
    |> Enum.drop_while(&blank?/1)
    |> trim_edge(&String.trim_trailing/1)
    |> Enum.reverse()
    |> trim_edge(&String.trim_leading/1)
  end

  defp trim_edge([{line, number} | rest], trim), do: [{trim.(line), number} | rest]
  defp trim_edge([], _trim), do: []

  defp blank?({line, _number}), do: String.trim(line) == ""

  # Printed lines of each line, its number and whether it wraps. A filled
  # in placeholder can make several lines of one.
  defp counts(lines, box) do
    Enum.map(lines, fn {line, number} ->
      counts = line |> String.split(["\r\n", "\n", "\r"]) |> Enum.map(&wrapped_lines(&1, box))
      {Enum.sum(counts), number, Enum.any?(counts, &(&1 > 1))}
    end)
  end

  # Characters of `lines` the font does not have, each once, as shown in an
  # error message.
  defp unsupported(lines) do
    lines
    |> Enum.flat_map(fn {line, _number} -> String.to_charlist(line) end)
    |> Enum.uniq()
    |> Enum.reject(&(&1 in [?\t, ?\n, ?\r] or Map.has_key?(@widths, &1)))
    |> Enum.map(fn char ->
      if <<char::utf8>> =~ ~r/^[\p{L}\p{N}\p{P}\p{S}]$/u,
        do: <<char::utf8>>,
        else: "U+" <> String.pad_leading(Integer.to_string(char, 16), 4, "0")
    end)
  end

  # Fills lines like the browser: a piece of text goes on the current line
  # if it fits and starts the next line otherwise. A piece wider than a whole
  # line is split between its characters (overflow-wrap: break-word). Runs of
  # spaces print as one space and none at the start or end of a line.
  defp wrapped_lines(line, box) do
    %{available: available, allowance: allowance} = measures(box)

    {lines, _used, _last} =
      line
      |> String.split([" ", "\t"], trim: true)
      |> Enum.reduce({1, 0, nil}, fn word, acc ->
        word
        |> String.to_charlist()
        |> pieces()
        |> Enum.with_index()
        |> Enum.reduce(acc, fn {piece, index}, {lines, used, last} ->
          width = width(piece, allowance)
          first = hd(piece)

          join =
            cond do
              used == 0 -> 0
              index == 0 -> kern(last, ?\s) + char_width(?\s, allowance) + kern(?\s, first)
              true -> kern(last, first)
            end

          cond do
            used + join + width <= available -> {lines, used + join + width, List.last(piece)}
            used > 0 -> split_piece(piece, width, lines + 1, available, allowance)
            true -> split_piece(piece, width, lines, available, allowance)
          end
        end)
      end)

    lines
  end

  # The parts of a word between the places where Chromium breaks it.
  defp pieces(chars) do
    {pieces, current} =
      [nil | chars]
      |> Enum.zip(chars)
      |> Enum.zip(tl(chars) ++ [nil])
      |> Enum.reduce({[], []}, fn {{previous, char}, next}, {pieces, current} ->
        current = [char | current]

        if break_after?(previous, char, next),
          do: {[Enum.reverse(current) | pieces], []},
          else: {pieces, current}
      end)

    Enum.reverse(if current == [], do: pieces, else: [Enum.reverse(current) | pieces])
  end

  # Where Chromium breaks inside a word, as measured for every character of
  # the font:
  # - after "-" before an ASCII letter ("Berlin-|Mitte", "und -|ver"), before
  #   another letter unless the hyphen starts the word or follows a no-break
  #   space ("Müller-|Übergabe", not "und -übergabe"), and before a digit
  #   when an ASCII letter or digit comes first ("BE-|973277", not "ä-1")
  # - after "–" and "‐" before a letter or digit, unless the dash starts the
  #   word or follows a no-break space; then only before a digit
  # - after "—", "…", "?" and the narrow spaces before a letter or digit
  defp break_after?(_previous, _char, nil), do: false

  defp break_after?(previous, ?-, next) when previous in @word_start,
    do: ascii_letter?(next)

  defp break_after?(previous, ?-, next),
    do: letter?(next) or (digit?(next) and ascii_alnum?(previous))

  defp break_after?(previous, char, next)
       when char in [0x2010, 0x2013] and previous in @word_start,
       do: digit?(next)

  defp break_after?(_previous, char, next) when char in @breaking,
    do: letter?(next) or digit?(next)

  defp break_after?(_previous, _char, _next), do: false

  defp letter?(char), do: <<char::utf8>> =~ ~r/^\p{L}$/u
  defp digit?(char), do: <<char::utf8>> =~ ~r/^\p{Nd}$/u
  defp ascii_letter?(char), do: char in ?a..?z or char in ?A..?Z
  defp ascii_alnum?(nil), do: false
  defp ascii_alnum?(char), do: ascii_letter?(char) or char in ?0..?9

  # Places `piece` (`width` wide) at the start of line `lines`, on further
  # lines if it is wider than a line. Chromium may then end a line early
  # wherever a character other than a letter or digit gives it a place to
  # break, so each of them counts one line more.
  defp split_piece(piece, width, lines, available, allowance) do
    {lines, used, last} =
      Enum.reduce(piece, {lines, 0, nil}, fn char, {lines, used, last} ->
        width = char_width(char, allowance) + kern(last, char)

        if used > 0 and used + width > available,
          do: {lines + 1, width, char},
          else: {lines, used + width, char}
      end)

    extra = if width > available, do: Enum.count(piece, &(not letter_or_digit?(&1))), else: 0
    {lines + extra, used, last}
  end

  defp letter_or_digit?(char), do: <<char::utf8>> =~ ~r/^[\p{Lu}\p{Ll}\p{Lt}\p{Lo}\p{Nd}]$/u

  # The room of a box, in font units of its text size, and what each
  # character counts more: Chromium lays out lines in steps of 1/64 pixel,
  # so the box may be up to one step narrower and each piece of text up to
  # one step wider than measured in font units.
  defp measures(box) do
    %{width_mm: width, size_pt: size} = Map.fetch!(@boxes, box)
    size_px = size * 96 / 72
    step = @units_per_em / size_px / 64
    width_px = Float.floor(width * 96 / 25.4 * 64) / 64

    %{available: width_px / size_px * @units_per_em, allowance: step}
  end

  defp width(chars, allowance) do
    {width, _last} =
      Enum.reduce(chars, {0, nil}, fn char, {sum, last} ->
        {sum + kern(last, char) + char_width(char, allowance), char}
      end)

    width
  end

  defp char_width(char, allowance), do: Map.get(@widths, char, @missing_width) + allowance

  defp kern(nil, _char), do: 0
  defp kern(first, second), do: Map.get(@kerning, {first, second}, 0)
end
