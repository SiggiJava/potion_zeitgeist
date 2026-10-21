defmodule PotionZeitgeist.Invoicing.Letter do
  @moduledoc """
  Fills invoice letter templates and builds everything the printed invoice shows.

  Templates are plain text with placeholders such as `{{rechnungsnummer}}`.
  Values are substituted as plain text; the HTML layer escapes the result.
  Unknown placeholders stay as they are, so a typo is visible in the preview.
  `{{positionen}}` in the body marks where the table of items goes.

  The parts German invoices must always show are part of the fixed layout,
  not of the template text: sender, tax number, recipient, number, date,
  service period, items, totals and, for small businesses, the § 19 UStG note.
  """

  alias PotionZeitgeist.Invoicing.{Calculation, Format, Invoice}

  @placeholder ~r/\{\{\s*([a-z_]+)\s*\}\}/
  @items_placeholder ~r/\{\{\s*positionen\s*\}\}/

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
    {"stunden", "Total hours"},
    {"gesamtbetrag", "Total amount due"},
    {"netto", "Net amount (only with VAT)"},
    {"ust_satz", "VAT rate (only with VAT)"},
    {"ust", "VAT amount (only with VAT)"},
    {"steuernummer", "Your tax number line"}
  ]

  @doc "Placeholder names with a short description, for the template editor."
  def placeholders, do: @placeholders

  @doc "`\"rechnungsnummer\"` becomes `\"{{rechnungsnummer}}\"`."
  def tag(name), do: "{{" <> name <> "}}"

  def small_business_note, do: @small_business_note

  @doc "Replaces known placeholders in `text` with values from `vars`."
  def fill(nil, _vars), do: ""

  def fill(text, vars) do
    Regex.replace(@placeholder, text, fn whole, name -> Map.get(vars, name, whole) end)
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
      "steuernummer" => texts.tax_id || ""
    }
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
  """
  def build(%Invoice{} = invoice, entries \\ []) do
    texts = texts(invoice)
    vars = vars(invoice, texts)
    {before_items, after_items} = texts.body |> fill(vars) |> split_body()
    sender = fill(texts.sender, vars)

    %{
      watermark: watermark(invoice.status),
      sender: sender,
      sender_line: sender_line(sender),
      recipient: invoice.recipient || "",
      info: info(invoice, vars),
      subject: fill(texts.subject, vars),
      before_items: before_items,
      after_items: after_items,
      items: Enum.map(invoice.items, &item_row/1),
      totals: total_rows(invoice),
      tax_note: if(invoice.tax_mode == "standard", do: nil, else: @small_business_note),
      tax_id: fill(texts.tax_id, vars),
      footer: fill(texts.footer, vars),
      timesheet: timesheet(invoice, entries, vars)
    }
  end

  @doc """
  The letter of `template` filled with sample data, for the template preview.
  """
  def sample(template, today) do
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

    totals = Calculation.totals(items, 0)

    build(%Invoice{
      status: "issued",
      number: "#{today.year}-001",
      invoice_date: today,
      due_date: Date.add(today, 14),
      period_start: Date.beginning_of_month(previous),
      period_end: previous,
      recipient: "Beispiel GmbH\nFrau Erika Musterfrau\nHauptstraße 5\n10115 Berlin",
      tax_mode: "small_business",
      vat_rate: Decimal.new(0),
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
    })
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

  defp item_row(item) do
    %{
      position: item.position,
      description: item.description,
      hours: Format.hours(item.hours),
      rate: Format.money(item.hourly_rate),
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
  # never changes after it was saved.
  defp totals(invoice) do
    %{
      hours: invoice.items |> Enum.map(& &1.hours) |> Enum.reduce(Decimal.new(0), &Decimal.add/2),
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
