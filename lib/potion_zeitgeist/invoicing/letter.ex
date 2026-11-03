defmodule PotionZeitgeist.Invoicing.Letter do
  @moduledoc """
  Fills invoice letter templates and builds everything the printed invoice shows.

  Templates are plain text with placeholders such as `{{rechnungsnummer}}`.
  Values are substituted as plain text; the HTML layer escapes the result.
  Unknown placeholders stay as they are, so a typo is visible in the preview.
  `{{positionen}}` in the body marks where the table of items goes.

  Text in a block such as `{{#faellig_am}} bis zum {{faellig_am}}{{/faellig_am}}`
  prints only when its placeholder has a value, text in
  `{{^faellig_am}}…{{/faellig_am}}` only when it has none, so a template
  works for invoices with and without a due date. A block opens and closes
  on one line. A line that holds nothing but blocks that are left out is
  left out too, and with it the blank line that set it apart as a paragraph.

  The parts German invoices must always show are part of the fixed layout,
  not of the template text: sender, tax number, recipient, number, date,
  service period, items, totals and, for small businesses, the § 19 UStG note.
  """

  alias PotionZeitgeist.Invoicing.{Calculation, Format, Invoice, InvoiceItem, LetterLayout}

  # A placeholder stays on one line, so each line of a text can be filled
  # (and measured, see `PotionZeitgeist.Invoicing.LetterLayout.check_lines/2`)
  # on its own.
  @placeholder ~r/\{\{[ \t]*([a-z_]+)[ \t]*\}\}/
  @items_placeholder ~r/\{\{\s*positionen\s*\}\}/

  # A block with its opening tag ("#" prints with a value, "^" without),
  # name and text, up to the first closing tag of the same name.
  @block ~r/\{\{[ \t]*([#^])[ \t]*([a-z_]+)[ \t]*\}\}(.*?)\{\{[ \t]*\/[ \t]*\2[ \t]*\}\}/
  @block_tag ~r/\{\{[ \t]*([#^\/])[ \t]*([a-z_]+)[ \t]*\}\}/
  @line_break ~r/\r\n|\n|\r/

  # A postcode line such as "12345 Musterstadt", "D-12345 Musterstadt" or "A-1010 Wien".
  @postcode_line ~r/^([A-Z]{1,2}-)?\d{4,5}\s/u

  @small_business_note "Gemäß § 19 UStG wird keine Umsatzsteuer berechnet (Kleinunternehmerregelung)."

  @placeholders [
    {"rechnungsnummer", "Invoice number (\"ENTWURF\" while the invoice is a draft)"},
    {"rechnungsdatum", "Invoice date"},
    {"faellig_am", "Due date"},
    {"leistungszeitraum", "Service period, e.g. 01.10.2026 – 31.10.2026"},
    {"monat", "Billed month, e.g. Oktober 2026"},
    {"empfaenger", "Recipient address"},
    {"positionen", "Table of items with totals (letter text only)"},
    {"stunden", "Total hours of the time entries"},
    {"gesamtbetrag", "Total amount due"},
    {"netto", "Net amount (only with VAT)"},
    {"ust_satz", "VAT rate (only with VAT)"},
    {"ust", "VAT amount (only with VAT)"},
    {"steuernummer", "Your tax number line"}
  ]

  # Placeholders that have a value of their own, which a block can depend on.
  # `{{positionen}}` is the place of the table of items, not a value.
  @block_names for {name, _description} <- @placeholders, name != "positionen", do: name

  @doc "Placeholder names with a short description, for the template editor."
  def placeholders, do: @placeholders

  @doc "`\"rechnungsnummer\"` becomes `\"{{rechnungsnummer}}\"`."
  def tag(name), do: "{{" <> name <> "}}"

  def small_business_note, do: @small_business_note

  @doc """
  Replaces known placeholders in `text` with values from `vars`, and keeps
  or leaves out the text of its blocks, see the module documentation.
  """
  def fill(nil, _vars), do: ""

  def fill(text, vars) do
    text
    |> filled_lines(vars)
    |> Enum.map_join(fn {line, break, _number} -> line <> break end)
  end

  @doc """
  The lines of `text` as `fill/2` prints them, each with its number in
  `text`, for measuring them (see
  `PotionZeitgeist.Invoicing.LetterLayout.check_lines/2`). A filled in
  value can hold line breaks of its own.
  """
  def fill_lines(text, vars), do: numbered(filled_lines(text || "", vars))

  @doc """
  Like `fill_lines/2`, but with the placeholders as typed: the blocks print
  or are left out as with `vars`. A placeholder can be longer or shorter
  than its value, so the line limits are checked both ways.
  """
  def typed_lines(text, vars), do: numbered(filled_lines(text || "", %{}, has_value(vars)))

  # Texts with more block names than this are measured as typed with the
  # text of all their blocks (more lines than any of them prints), instead
  # of once for each way their blocks can print.
  @max_variant_names 6

  @doc """
  The lines of `text` as `typed_lines/2` gives them, once for each way its
  blocks can print: each block name it uses with and without a value. For
  checking the line limits of a template, whatever invoice it prints.
  """
  def typed_variants(text) do
    text = text || ""
    names = @block_tag |> Regex.scan(text) |> Enum.map(&List.last/1) |> Enum.uniq()
    names = Enum.filter(names, &(&1 in @block_names))

    if length(names) > @max_variant_names do
      numbered_lines = text |> lines() |> Enum.with_index(1)
      [for({line, number} <- numbered_lines, do: {without_block_tags(line), number})]
    else
      for with_value <- subsets(names) do
        decide = &if(&1 in @block_names, do: &1 in with_value, else: :unknown)
        numbered(filled_lines(text, %{}, decide))
      end
    end
  end

  defp subsets(names) do
    Enum.reduce(names, [[]], fn name, subsets -> subsets ++ Enum.map(subsets, &[name | &1]) end)
  end

  defp numbered(filled_lines), do: for({line, _break, number} <- filled_lines, do: {line, number})

  # Whether the placeholder `name` has a value in `vars`, `:unknown` for
  # names that are no placeholders.
  defp has_value(vars) do
    fn name ->
      case Map.fetch(vars, name) do
        {:ok, value} -> not blank?(value)
        :error -> :unknown
      end
    end
  end

  # Each line of `text` filled in, with the line break after it and its
  # number in `text`, without the lines that only held left out blocks.
  # `decide` tells for each block name whether it has a value.
  defp filled_lines(text, vars), do: filled_lines(text, vars, has_value(vars))

  defp filled_lines(text, vars, decide) do
    @line_break
    |> Regex.split(text, include_captures: true)
    |> with_breaks(1)
    |> Enum.map(fn {line, break, number} ->
      case fill_blocks(line, decide) do
        ^line ->
          {:keep, fill_placeholders(line, vars), break, number}

        blocks_filled ->
          filled = fill_placeholders(blocks_filled, vars)
          {if(blank?(filled), do: :drop, else: :keep), filled, break, number}
      end
    end)
    |> drop_left_out([])
  end

  defp with_breaks([line, break | rest], number),
    do: [{line, break, number} | with_breaks(rest, number + 1)]

  defp with_breaks([line], number), do: [{line, "", number}]

  # A left out line goes with its line break. When it stood alone between
  # blank lines (or at the start or end of the text), as a paragraph of its
  # own, one of those blank lines goes too, so no gap is left.
  defp drop_left_out([], kept), do: Enum.reverse(kept)

  defp drop_left_out([{:keep, line, break, number} | rest], kept),
    do: drop_left_out(rest, [{line, break, number} | kept])

  defp drop_left_out(lines, kept) do
    {_dropped, rest} = Enum.split_while(lines, &(elem(&1, 0) == :drop))
    alone? = paragraph_edge?(List.first(kept)) and paragraph_edge?(List.first(rest))

    {rest, kept} =
      cond do
        # The blank line after it.
        alone? and rest != [] -> {tl(rest), kept}
        # At the end of the text, the blank line before it.
        alone? and kept != [] -> {rest, tl(kept)}
        true -> {rest, kept}
      end

    # The line before the left out ones now ends the text.
    kept =
      case {rest, kept} do
        {[], [{line, _break, number} | earlier]} -> [{line, "", number} | earlier]
        _ -> kept
      end

    drop_left_out(rest, kept)
  end

  defp paragraph_edge?(nil), do: true
  defp paragraph_edge?({line, _break, _number}), do: blank?(line)
  defp paragraph_edge?({_keep, line, _break, _number}), do: blank?(line)

  defp blank?(text), do: String.trim(text) == ""

  defp fill_blocks(line, decide) do
    Regex.replace(@block, line, fn whole, kind, name, text ->
      case decide.(name) do
        :unknown -> whole
        has_value when has_value == (kind == "#") -> fill_blocks(text, decide)
        _left_out -> ""
      end
    end)
  end

  defp fill_placeholders(line, vars) do
    Regex.replace(@placeholder, line, fn whole, name -> Map.get(vars, name, whole) end)
  end

  defp without_block_tags(line) do
    Regex.replace(@block_tag, line, fn whole, _kind, name ->
      if name in @block_names, do: "", else: whole
    end)
  end

  @doc """
  Messages for the blocks of `text` that do not open and close on one line,
  or that sit in a block of the same name.
  """
  def block_errors(text) do
    text
    |> lines()
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, number} -> line_block_errors(line, number) end)
  end

  defp lines(text), do: String.split(text || "", ["\r\n", "\n", "\r"])

  defp line_block_errors(line, number) do
    @block_tag
    |> Regex.scan(line)
    |> Enum.filter(fn [_whole, _kind, name] -> name in @block_names end)
    |> Enum.reduce_while([], fn
      [_whole, "/", name], [{_kind, name} | open] ->
        {:cont, open}

      [_whole, "/", name], [{_kind, inner} | _open] = open ->
        message =
          if List.keymember?(open, name, 1),
            do: "closes #{tag("/" <> name)} before #{tag("/" <> inner)}",
            else: "has #{tag("/" <> name)} without #{tag("#" <> name)} before it"

        {:halt, {:error, message}}

      [_whole, "/", name], [] ->
        {:halt, {:error, "has #{tag("/" <> name)} without #{tag("#" <> name)} before it"}}

      [_whole, kind, name], open ->
        if List.keymember?(open, name, 1),
          do: {:halt, {:error, "has #{tag(kind <> name)} in a block of the same name"}},
          else: {:cont, [{kind, name} | open]}
    end)
    |> case do
      [] ->
        []

      {:error, message} ->
        ["#{message} in line #{number}"]

      open ->
        {kind, name} = List.last(open)

        [
          "has #{tag(kind <> name)} in line #{number} without #{tag("/" <> name)} " <>
            "on the same line"
        ]
    end
  end

  @doc """
  Whether `text` prints the placeholder `name` outside a
  `{{#name}}…{{/name}}` block, where an empty value leaves a gap.
  """
  def bare_placeholder?(text, name) do
    name = Regex.escape(name)
    block = ~r/\{\{[ \t]*#[ \t]*#{name}[ \t]*\}\}.*?\{\{[ \t]*\/[ \t]*#{name}[ \t]*\}\}/
    placeholder = ~r/\{\{[ \t]*#{name}[ \t]*\}\}/

    text
    |> lines()
    |> Enum.any?(&Regex.match?(placeholder, Regex.replace(block, &1, "")))
  end

  @doc """
  Splits the letter body at `{{positionen}}` into the text before and after
  the table of items. Without the placeholder the table follows the body.
  """
  def split_body(body) do
    case Regex.split(@items_placeholder, body || "", parts: 2) do
      [before, after_items] -> {String.trim(before), String.trim(after_items)}
      [before] -> {String.trim(before), ""}
    end
  end

  def has_items_placeholder?(body), do: Regex.match?(@items_placeholder, body || "")

  @doc "Placeholder values of an invoice with `:items` loaded."
  def vars(%Invoice{} = invoice, texts \\ nil) do
    texts = texts || texts(invoice)
    totals = totals(invoice)
    vat? = invoice.tax_mode == "standard"

    %{
      "rechnungsnummer" => number(invoice),
      "rechnungsdatum" => Format.date(invoice.invoice_date),
      "faellig_am" => Format.date(invoice.due_date),
      "leistungszeitraum" => Format.period(invoice.period_start, invoice.period_end),
      "monat" => if(invoice.period_start, do: Format.month(invoice.period_start), else: ""),
      "empfaenger" => invoice.recipient || "",
      "stunden" => Format.hours(totals.hours),
      "gesamtbetrag" => Format.money(totals.gross),
      "netto" => if(vat?, do: Format.money(totals.net), else: ""),
      "ust_satz" => if(vat?, do: Format.percent(invoice.vat_rate), else: ""),
      "ust" => if(vat?, do: Format.money(totals.vat), else: ""),
      "steuernummer" => tax_id_value(texts, invoice)
    }
  end

  # The tax number line as {{steuernummer}} prints it. With blocks (such as
  # a VAT number only on invoices with VAT), as the tax number line prints;
  # without, as typed, as before blocks existed.
  defp tax_id_value(%{tax_id: nil}, _invoice), do: ""

  defp tax_id_value(%{tax_id: tax_id} = texts, invoice) do
    if Regex.match?(@block_tag, tax_id),
      do: fill(tax_id, vars(invoice, %{texts | tax_id: ""})),
      else: tax_id
  end

  @doc """
  The template texts an invoice is printed with: the texts frozen when it was
  issued, or the current texts of its template while it is a draft.
  """
  def texts(%Invoice{status: "draft", template: %{} = template}) do
    Map.take(template, [:sender, :tax_id, :subject, :body, :footer])
  end

  def texts(%Invoice{status: "draft"}) do
    %{sender: "", tax_id: "", subject: "", body: "", footer: ""}
  end

  def texts(%Invoice{} = invoice) do
    %{
      sender: invoice.letter_sender,
      tax_id: invoice.letter_tax_id,
      subject: invoice.letter_subject,
      body: invoice.letter_body,
      footer: invoice.letter_footer
    }
  end

  @doc """
  The default file name when saving the invoice as PDF, e.g.
  "Rechnung 2026-007 Beispiel GmbH".
  """
  def document_title(%Invoice{} = invoice) do
    recipient = invoice.recipient |> to_string() |> String.split(["\r\n", "\n"]) |> List.first("")

    title =
      case invoice.status do
        "draft" -> "ENTWURF Rechnung #{recipient} #{Format.month(invoice.period_start)}"
        "cancelled" -> "Rechnung #{invoice.number} #{recipient} (storniert)"
        _ -> "Rechnung #{invoice.number} #{recipient}"
      end

    title |> String.replace(["/", "\\", ":"], "-") |> String.trim()
  end

  @doc """
  Everything the printed invoice shows, as plain strings.

  Expects `:items` and, for drafts, `:template` loaded. `entries` are the
  invoice's `PotionZeitgeist.Invoicing.InvoiceEntry` rows for the time sheet.

  The table of items has the columns of `:item_columns`: `:hours` (hours
  and hourly rate) when all items bill time entries, as invoices printed
  before there were other items, or `:quantity` (quantity, unit and price
  per unit) when there are other items too, where time prints in hours
  ("Std.") at the hourly rate.
  """
  def build(%Invoice{} = invoice, entries \\ []) do
    texts = texts(invoice)
    vars = vars(invoice, texts)
    {before_items, after_items} = texts.body |> fill(vars) |> split_body()
    sender = texts.sender |> fill(vars) |> boxed()
    columns = item_columns(invoice.items)

    %{
      watermark: watermark(invoice.status),
      sender: sender,
      sender_line: sender_line(sender),
      recipient: boxed(invoice.recipient),
      info: info(invoice, vars),
      subject: texts.subject |> fill(vars) |> String.trim(),
      before_items: before_items,
      after_items: after_items,
      item_columns: columns,
      items: Enum.map(invoice.items, &item_row(&1, columns)),
      totals: total_rows(invoice),
      tax_note: if(invoice.tax_mode == "standard", do: nil, else: @small_business_note),
      tax_id: texts.tax_id |> fill(vars) |> boxed(),
      footer: texts.footer |> fill(vars) |> boxed(),
      timesheet: timesheet(invoice, entries, vars)
    }
  end

  # A text printed in a box of fixed size, see
  # `PotionZeitgeist.Invoicing.LetterLayout`: without invisible characters
  # that could change its line breaks, and without line breaks at the start
  # or end, which would print as blank lines.
  defp boxed(text), do: text |> LetterLayout.clean() |> String.trim()

  @doc """
  The letter of `template` filled with sample data, for the template preview.
  With `due_date: false`, the sample invoice has no due date, with
  `vat: true` it charges 19 % VAT.
  """
  def sample(template, today, opts \\ []),
    do: template |> sample_invoice(today, opts) |> build()

  @doc """
  An issued invoice of `template` with sample data, the one `sample/3`
  shows.
  """
  def sample_invoice(template, today, opts \\ []) do
    previous = today |> Date.beginning_of_month() |> Date.add(-1)
    rate = Decimal.new(85)

    items =
      [{"Website-Relaunch", 1950}, {"Wartung und Support", 240}]
      |> Enum.with_index(1)
      |> Enum.map(fn {{description, minutes}, position} ->
        hours = Calculation.hours(minutes)

        %{
          position: position,
          description: description,
          minutes: minutes,
          hours: hours,
          hourly_rate: rate,
          amount: Calculation.amount(hours, rate)
        }
      end)

    vat_rate = if Keyword.get(opts, :vat, false), do: Decimal.new(19), else: Decimal.new(0)
    totals = Calculation.totals(items, vat_rate)

    %Invoice{
      status: "issued",
      number: "#{today.year}-001",
      invoice_date: today,
      due_date: if(Keyword.get(opts, :due_date, true), do: Date.add(today, 14)),
      period_start: Date.beginning_of_month(previous),
      period_end: previous,
      recipient: "Beispiel GmbH\nFrau Erika Musterfrau\nHauptstraße 5\n10115 Berlin",
      tax_mode: if(Decimal.gt?(vat_rate, 0), do: "standard", else: "small_business"),
      vat_rate: vat_rate,
      net_total: totals.net,
      vat_total: totals.vat,
      gross_total: totals.gross,
      show_timesheet: false,
      items: items,
      letter_sender: template.sender,
      letter_tax_id: template.tax_id,
      letter_subject: template.subject,
      letter_body: template.body,
      letter_footer: template.footer
    }
  end

  defp number(%Invoice{number: number}) when is_binary(number) and number != "", do: number
  defp number(_invoice), do: "ENTWURF"

  defp watermark("draft"), do: "ENTWURF"
  defp watermark("cancelled"), do: "STORNIERT"
  defp watermark(_status), do: nil

  # The small return address above the recipient window.
  defp sender_line(sender) do
    lines =
      sender
      |> String.split(["\r\n", "\n"], trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    # Name, street and postcode with city, also when a company or trade line
    # sits between name and street.
    case Enum.find_index(lines, &Regex.match?(@postcode_line, &1)) do
      index when is_integer(index) and index > 0 ->
        [hd(lines) | lines |> Enum.slice(1..index//1) |> Enum.take(-2)]

      _ ->
        Enum.take(lines, 3)
    end
    |> Enum.join(" · ")
  end

  defp info(invoice, vars) do
    [
      {"Rechnungsnummer", vars["rechnungsnummer"]},
      {"Rechnungsdatum", vars["rechnungsdatum"]},
      {"Leistungszeitraum", vars["leistungszeitraum"]}
    ] ++ if(invoice.due_date, do: [{"Fällig am", vars["faellig_am"]}], else: [])
  end

  defp item_columns(items) do
    if Enum.all?(items, &InvoiceItem.time?/1), do: :hours, else: :quantity
  end

  defp item_row(item, :hours) do
    %{
      position: item.position,
      description: item.description,
      hours: Format.hours(item.hours),
      rate: Format.money(item.hourly_rate),
      amount: Format.money(item.amount)
    }
  end

  defp item_row(item, :quantity) do
    {quantity, unit, price} =
      if InvoiceItem.time?(item),
        do: {Format.hours(item.hours), "Std.", Format.money(item.hourly_rate)},
        else: {Format.quantity(item.quantity), item.unit || "", Format.money(item.unit_price)}

    %{
      position: item.position,
      description: item.description,
      quantity: quantity,
      unit: unit,
      price: price,
      amount: Format.money(item.amount)
    }
  end

  defp total_rows(invoice) do
    totals = totals(invoice)

    if invoice.tax_mode == "standard" do
      [
        {"Nettobetrag", Format.money(totals.net)},
        {"Umsatzsteuer #{Format.percent(invoice.vat_rate)}", Format.money(totals.vat)},
        {"Gesamtbetrag", Format.money(totals.gross)}
      ]
    else
      [{"Gesamtbetrag", Format.money(totals.gross)}]
    end
  end

  # Amounts come from the totals stored with the invoice, so a printed invoice
  # never changes after it was saved. Hours are those of the time entries.
  defp totals(invoice) do
    %{
      hours:
        invoice.items
        |> Enum.filter(&InvoiceItem.time?/1)
        |> Enum.map(& &1.hours)
        |> Enum.reduce(Decimal.new(0), &Decimal.add/2),
      net: invoice.net_total,
      vat: invoice.vat_total,
      gross: invoice.gross_total
    }
  end

  # One row per day, item and person; several clock-ins of a day are added up.
  defp timesheet(%Invoice{show_timesheet: false}, _entries, _vars), do: nil
  defp timesheet(_invoice, [], _vars), do: nil

  defp timesheet(_invoice, entries, vars) do
    rows =
      entries
      |> Enum.group_by(&{&1.date, &1.description, &1.user_name})
      |> Enum.map(fn {{date, description, user_name}, day_entries} ->
        %{
          sort: {Date.to_gregorian_days(date), description, to_string(user_name)},
          date: Format.date(date),
          project: description,
          user: user_name || "",
          minutes: day_entries |> Enum.map(& &1.minutes) |> Enum.sum(),
          notes:
            day_entries
            |> Enum.map(&String.trim(&1.notes || ""))
            |> Enum.reject(&(&1 == ""))
            |> Enum.uniq()
            |> Enum.join("; ")
        }
      end)
      |> Enum.sort_by(& &1.sort)
      |> Enum.map(&Map.put(&1, :duration, Format.duration(&1.minutes)))

    %{
      title: "Tätigkeitsnachweis zur Rechnung #{vars["rechnungsnummer"]}",
      period: vars["leistungszeitraum"],
      show_user: rows |> Enum.map(& &1.user) |> Enum.uniq() |> length() > 1,
      show_project: rows |> Enum.map(& &1.project) |> Enum.uniq() |> length() > 1,
      rows: rows,
      total: rows |> Enum.map(& &1.minutes) |> Enum.sum() |> Format.duration()
    }
  end
end
