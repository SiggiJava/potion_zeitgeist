defmodule PotionZeitgeist.Invoicing.AnnualReport do
  @moduledoc """
  The annual report of issued invoices: the invoices of a year with their
  items (time and other items), the sums per invoice and for the whole year,
  as the report page, its print page and its CSV files show them.

  Basis `"paid"` counts each issued invoice in the year its payment came in
  (`paid_on`). That is how the EÜR counts income: in the year it is received
  (Zuflussprinzip, § 11 EStG). Basis `"invoice"` counts issued invoices by
  their invoice date. Drafts never count. Cancelled invoices never count
  either; the report lists those of the year apart, and on basis `"paid"`
  also the issued invoices that have no payment yet.

  Amounts are the totals stored with each invoice, so the report always
  matches the printed invoices. The CSV files are written for a German
  spreadsheet: semicolons between the fields, decimal commas, German dates
  and a byte order mark, so Excel reads umlauts as UTF-8.
  """

  alias PotionZeitgeist.Invoicing.{Format, InvoiceItem}

  @bases ~w(paid invoice)

  @doc "The bases the report can count invoices on."
  def bases, do: @bases

  @doc "`\"invoice\"` stays, anything else is the default basis `\"paid\"`."
  def parse_basis("invoice"), do: "invoice"
  def parse_basis(_value), do: "paid"

  @doc "A year such as `\"2026\"` as an integer, or `nil` when it is none."
  def parse_year(year) when is_integer(year) and year in 1..9999, do: year

  def parse_year(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {year, ""} when year in 1..9999 -> year
      _ -> nil
    end
  end

  def parse_year(_value), do: nil

  @doc "The first and the last day of `year`."
  def year_range(year), do: {Date.new!(year, 1, 1), Date.new!(year, 12, 31)}

  @doc """
  Builds the report of `year` on `basis` from invoices with their items
  (and the items' projects) loaded:

    * `:counted`, the issued invoices of the year on that basis,
    * `:unpaid`, issued invoices up to the end of the year without payment,
    * `:paid_later`, issued invoices dated in the year but paid later,
    * `:cancelled`, the cancelled invoices dated in the year.

  Only `:counted` adds to the totals; the others are listed so the sums
  can be followed. Returns the rows of each, sorted by the date the basis
  counts and by number, and the totals of the counted invoices.
  """
  def build(year, basis, invoices) do
    rows = invoices |> Map.get(:counted, []) |> rows(basis)

    %{
      year: year,
      basis: basis,
      invoices: rows,
      unpaid: invoices |> Map.get(:unpaid, []) |> rows("invoice"),
      paid_later: invoices |> Map.get(:paid_later, []) |> rows("invoice"),
      cancelled: invoices |> Map.get(:cancelled, []) |> rows("invoice"),
      totals: totals(rows),
      vat?: Enum.any?(rows, & &1.vat?)
    }
  end

  defp rows(invoices, basis) do
    invoices
    |> Enum.sort_by(&sort_key(&1, basis))
    |> Enum.map(&row/1)
  end

  # Invoices without a payment date sort by invoice date (only the counted
  # invoices of basis "paid" sort by payment, and they all have one).
  defp sort_key(invoice, basis) do
    date =
      if basis == "paid", do: invoice.paid_on || invoice.invoice_date, else: invoice.invoice_date

    {Date.to_gregorian_days(date), Date.to_gregorian_days(invoice.invoice_date),
     to_string(invoice.number), invoice.id}
  end

  defp row(invoice) do
    time_items = Enum.filter(invoice.items, &InvoiceItem.time?/1)

    %{
      id: invoice.id,
      number: invoice.number,
      invoice_date: invoice.invoice_date,
      paid_on: invoice.paid_on,
      cancelled_at: invoice.cancelled_at,
      recipient: recipient_name(invoice.recipient),
      period: Format.period(invoice.period_start, invoice.period_end),
      hours: if(time_items == [], do: nil, else: sum(time_items, :hours)),
      vat?: invoice.tax_mode == "standard",
      vat_rate: invoice.vat_rate,
      net: invoice.net_total,
      vat: invoice.vat_total,
      gross: invoice.gross_total,
      items: Enum.map(invoice.items, &item_row/1)
    }
  end

  # Items of time print as on the invoice: hours ("Std.") at the hourly rate.
  defp item_row(item) do
    if InvoiceItem.time?(item) do
      %{
        position: item.position,
        time?: true,
        kind: "Zeit",
        description: item.description,
        project: project_name(item),
        quantity: item.hours,
        unit: "Std.",
        price: item.hourly_rate,
        amount: item.amount
      }
    else
      %{
        position: item.position,
        time?: false,
        kind: "Einzelposten",
        description: item.description,
        project: nil,
        quantity: item.quantity,
        unit: item.unit || "",
        price: item.unit_price,
        amount: item.amount
      }
    end
  end

  defp totals(rows) do
    items = Enum.flat_map(rows, & &1.items)
    {time_items, other_items} = Enum.split_with(items, & &1.time?)
    hours = rows |> Enum.map(& &1.hours) |> Enum.reject(&is_nil/1)

    %{
      count: length(rows),
      hours: if(hours == [], do: nil, else: Enum.reduce(hours, &Decimal.add/2)),
      time_amount: sum(time_items, :amount),
      other_amount: sum(other_items, :amount),
      time?: time_items != [],
      other?: other_items != [],
      net: sum(rows, :net),
      vat: sum(rows, :vat),
      gross: sum(rows, :gross)
    }
  end

  defp sum(list, key) do
    Enum.reduce(list, Decimal.new("0.00"), &Decimal.add(Map.fetch!(&1, key), &2))
  end

  @doc "The name of the recipient: the first line of the address."
  def recipient_name(recipient) do
    recipient
    |> to_string()
    |> String.split(["\r\n", "\n", "\r"])
    |> Enum.map(&String.trim/1)
    |> Enum.find("", &(&1 != ""))
  end

  defp project_name(%{project: %{name: name}}), do: name
  defp project_name(_item), do: nil

  @doc "\"1 Rechnung\", \"3 Rechnungen\"."
  def count_label(1), do: "1 Rechnung"
  def count_label(count), do: "#{count} Rechnungen"

  @doc "The German name of a basis, for the print page and file names."
  def basis_title("paid"), do: "nach Zahlungseingang"
  def basis_title("invoice"), do: "nach Rechnungsdatum"

  @doc """
  The file name of a CSV file of the report, `type` `"invoices"` or
  `"items"`: "rechnungen_2026_nach_zahlungseingang.csv".
  """
  def csv_filename(report, type) do
    name = if type == "items", do: "positionen", else: "rechnungen"
    basis = report.basis |> basis_title() |> String.downcase() |> String.replace(" ", "_")
    "#{name}_#{report.year}_#{basis}.csv"
  end

  ## CSV

  @doc """
  CSV with one row per counted invoice and a last row with the sums of the
  year.
  """
  def invoices_csv(report) do
    header = [
      "Rechnungsnummer",
      "Rechnungsdatum",
      "Bezahlt am",
      "Empfänger",
      "Leistungszeitraum",
      "Stunden",
      "Netto",
      "USt-Satz",
      "USt",
      "Brutto"
    ]

    rows =
      Enum.map(report.invoices, fn row ->
        [
          text(row.number),
          date(row.invoice_date),
          date(row.paid_on),
          text(row.recipient),
          row.period,
          amount(row.hours),
          amount(row.net),
          number(row.vat_rate),
          amount(row.vat),
          amount(row.gross)
        ]
      end)

    totals = report.totals

    sums = [
      "Summe (#{count_label(totals.count)})",
      "",
      "",
      "",
      "",
      amount(totals.hours),
      amount(totals.net),
      "",
      amount(totals.vat),
      amount(totals.gross)
    ]

    to_csv([header | rows] ++ [sums])
  end

  @doc """
  CSV with one row per item of the counted invoices, time and other items,
  and last rows with the sums of the year: of the time, of the other items
  and of all items (the net total of the invoices).
  """
  def items_csv(report) do
    header = [
      "Rechnungsnummer",
      "Rechnungsdatum",
      "Bezahlt am",
      "Empfänger",
      "Pos.",
      "Art",
      "Bezeichnung",
      "Projekt",
      "Menge",
      "Einheit",
      "Einzelpreis",
      "Betrag netto"
    ]

    rows =
      for row <- report.invoices, item <- row.items do
        [
          text(row.number),
          date(row.invoice_date),
          date(row.paid_on),
          text(row.recipient),
          to_string(item.position),
          item.kind,
          text(item.description),
          text(item.project),
          if(item.time?, do: amount(item.quantity), else: number(item.quantity)),
          text(item.unit),
          amount(item.price),
          amount(item.amount)
        ]
      end

    totals = report.totals
    blank = List.duplicate("", 7)

    sums =
      [
        totals.time? &&
          ["Summe Zeit" | blank] ++ [amount(totals.hours), "Std.", "", amount(totals.time_amount)],
        totals.other? &&
          ["Summe Einzelposten" | blank] ++ ["", "", "", amount(totals.other_amount)],
        ["Summe (#{count_label(totals.count)})" | blank] ++ ["", "", "", amount(totals.net)]
      ]
      |> Enum.filter(& &1)

    to_csv([header | rows] ++ sums)
  end

  # A text a spreadsheet could take for a formula gets a leading apostrophe.
  defp text(nil), do: ""

  defp text(value) do
    value = to_string(value)

    if String.starts_with?(value, ["=", "+", "-", "@", "\t", "\r"]),
      do: "'" <> value,
      else: value
  end

  defp date(nil), do: ""
  defp date(%Date{} = date), do: Format.date(date)

  # Amounts and hours with two decimals and a decimal comma, without
  # thousands separators, which spreadsheets would read as text.
  defp amount(nil), do: ""

  defp amount(value) do
    value
    |> Decimal.round(2, :half_up)
    |> Decimal.to_string(:normal)
    |> String.replace(".", ",")
  end

  # Quantities and rates with the decimals they have: "2,5", "1250", "19".
  defp number(nil), do: ""

  defp number(value) do
    value
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
    |> String.replace(".", ",")
  end

  defp to_csv(rows) do
    "﻿" <>
      Enum.map_join(rows, fn row -> Enum.map_join(row, ";", &escape/1) <> "\r\n" end)
  end

  defp escape(value) do
    if String.contains?(value, [";", "\"", "\n", "\r"]),
      do: "\"" <> String.replace(value, "\"", "\"\"") <> "\"",
      else: value
  end
end
