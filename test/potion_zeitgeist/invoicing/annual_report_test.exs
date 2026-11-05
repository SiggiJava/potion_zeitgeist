defmodule PotionZeitgeist.Invoicing.AnnualReportTest do
  use ExUnit.Case, async: true

  alias PotionZeitgeist.Invoicing.{AnnualReport, Invoice, InvoiceItem}

  defp time_item(position, description, project, hours, rate) do
    hours = Decimal.new(hours)
    rate = Decimal.new(rate)

    %InvoiceItem{
      kind: "time",
      position: position,
      description: description,
      project: project && %{name: project},
      hours: hours,
      hourly_rate: rate,
      amount: hours |> Decimal.mult(rate) |> Decimal.round(2)
    }
  end

  defp other_item(position, description, quantity, unit, price) do
    quantity = Decimal.new(quantity)
    price = Decimal.new(price)

    %InvoiceItem{
      kind: "manual",
      position: position,
      description: description,
      quantity: quantity,
      unit: unit,
      unit_price: price,
      amount: quantity |> Decimal.mult(price) |> Decimal.round(2)
    }
  end

  defp invoice(attrs) do
    attrs = Map.new(attrs)
    items = Map.fetch!(attrs, :items)
    net = Enum.reduce(items, Decimal.new("0.00"), &Decimal.add(&1.amount, &2))
    rate = Map.get(attrs, :vat_rate, Decimal.new("0.00"))
    vat = net |> Decimal.mult(rate) |> Decimal.div(100) |> Decimal.round(2)

    struct!(
      Invoice,
      Map.merge(
        %{
          status: "issued",
          period_start: ~D[2026-02-01],
          period_end: ~D[2026-02-28],
          recipient: "Kunde GmbH\nWeg 2\n10115 Berlin",
          tax_mode: if(Decimal.gt?(rate, 0), do: "standard", else: "small_business"),
          vat_rate: rate,
          net_total: net,
          vat_total: vat,
          gross_total: Decimal.add(net, vat)
        },
        attrs
      )
    )
  end

  # Two invoices paid in 2026: one for time and material, without VAT, one
  # with a flat fee and 19 % VAT, dated earlier but paid later.
  defp report(basis \\ "paid") do
    first =
      invoice(
        id: 1,
        number: "2026-002",
        invoice_date: ~D[2026-03-02],
        paid_on: ~D[2026-03-10],
        items: [
          time_item(1, "Website-Relaunch", "Website", "32.50", "80.00"),
          time_item(2, "Dienstleistungen", nil, "1.25", "80.00"),
          other_item(3, "Netzwerkkabel", "2.500", "m", "4.00")
        ]
      )

    second =
      invoice(
        id: 2,
        number: "2026-001",
        invoice_date: ~D[2026-01-15],
        paid_on: ~D[2026-12-30],
        recipient: "\n  Andere \"AG\"; Berlin \nAllee 1\n20095 Hamburg",
        vat_rate: Decimal.new("19.00"),
        items: [other_item(1, "Pauschale Wartung", "1250.000", nil, "0.80")]
      )

    AnnualReport.build(2026, basis, %{counted: [second, first], unpaid: [], cancelled: []})
  end

  test "lists the invoices by the day of payment, with the sums of the year" do
    report = report()

    assert Enum.map(report.invoices, & &1.number) == ["2026-002", "2026-001"]
    assert [first, second] = report.invoices
    assert first.recipient == "Kunde GmbH"
    assert second.recipient == "Andere \"AG\"; Berlin"
    assert Decimal.equal?(first.hours, Decimal.new("33.75"))
    assert second.hours == nil
    assert report.vat?

    totals = report.totals
    assert totals.count == 2
    assert Decimal.equal?(totals.hours, Decimal.new("33.75"))
    assert Decimal.equal?(totals.time_amount, Decimal.new("2700.00"))
    assert Decimal.equal?(totals.other_amount, Decimal.new("1010.00"))
    assert Decimal.equal?(totals.net, Decimal.new("3710.00"))
    assert Decimal.equal?(totals.vat, Decimal.new("190.00"))
    assert Decimal.equal?(totals.gross, Decimal.new("3900.00"))

    # By invoice date, the earlier invoice comes first.
    assert Enum.map(report("invoice").invoices, & &1.number) == ["2026-001", "2026-002"]
  end

  test "the invoices CSV is made for a German spreadsheet, with a row of sums" do
    csv = AnnualReport.invoices_csv(report())

    assert csv ==
             "﻿" <>
               "Rechnungsnummer;Rechnungsdatum;Bezahlt am;Empfänger;Leistungszeitraum;" <>
               "Stunden;Netto;USt-Satz;USt;Brutto\r\n" <>
               "2026-002;02.03.2026;10.03.2026;Kunde GmbH;01.02.2026 – 28.02.2026;" <>
               "33,75;2710,00;0;0,00;2710,00\r\n" <>
               "2026-001;15.01.2026;30.12.2026;\"Andere \"\"AG\"\"; Berlin\";" <>
               "01.02.2026 – 28.02.2026;;1000,00;19;190,00;1190,00\r\n" <>
               "Summe (2 Rechnungen);;;;;33,75;3710,00;;190,00;3900,00\r\n"
  end

  test "the items CSV lists time and other items, with the sums of each" do
    csv = AnnualReport.items_csv(report())

    assert csv ==
             "﻿" <>
               "Rechnungsnummer;Rechnungsdatum;Bezahlt am;Empfänger;Pos.;Art;Bezeichnung;" <>
               "Projekt;Menge;Einheit;Einzelpreis;Betrag netto\r\n" <>
               "2026-002;02.03.2026;10.03.2026;Kunde GmbH;1;Zeit;Website-Relaunch;" <>
               "Website;32,50;Std.;80,00;2600,00\r\n" <>
               "2026-002;02.03.2026;10.03.2026;Kunde GmbH;2;Zeit;Dienstleistungen;" <>
               ";1,25;Std.;80,00;100,00\r\n" <>
               "2026-002;02.03.2026;10.03.2026;Kunde GmbH;3;Einzelposten;Netzwerkkabel;" <>
               ";2,5;m;4,00;10,00\r\n" <>
               "2026-001;15.01.2026;30.12.2026;\"Andere \"\"AG\"\"; Berlin\";1;Einzelposten;" <>
               "Pauschale Wartung;;1250;;0,80;1000,00\r\n" <>
               "Summe Zeit;;;;;;;;33,75;Std.;;2700,00\r\n" <>
               "Summe Einzelposten;;;;;;;;;;;1010,00\r\n" <>
               "Summe (2 Rechnungen);;;;;;;;;;;3710,00\r\n"

    assert AnnualReport.csv_filename(report(), "items") ==
             "positionen_2026_nach_zahlungseingang.csv"

    assert AnnualReport.csv_filename(report("invoice"), "invoices") ==
             "rechnungen_2026_nach_rechnungsdatum.csv"
  end

  test "texts a spreadsheet would read as a formula stay text" do
    items =
      for {text, position} <- Enum.with_index(["=1+1", "+49 30", "-x", "@SUM(A1)", "a=b"], 1) do
        other_item(position, text, "1", nil, "1.00")
      end

    report =
      AnnualReport.build(2026, "paid", %{
        counted: [
          invoice(
            id: 1,
            number: "=2026",
            invoice_date: ~D[2026-01-02],
            paid_on: ~D[2026-01-03],
            items: items
          )
        ]
      })

    csv = AnnualReport.items_csv(report)
    assert csv =~ "\r\n'=2026;02.01.2026;"

    for text <- ["'=1+1", "'+49 30", "'-x", "'@SUM(A1)", ";a=b;"] do
      assert csv =~ text
    end
  end

  test "the small business note needs every listed invoice without VAT" do
    plain = invoice(id: 1, number: "2026-001", invoice_date: ~D[2026-01-02], items: [])

    cancelled =
      invoice(
        id: 2,
        number: "2026-002",
        invoice_date: ~D[2026-01-05],
        status: "cancelled",
        cancelled_at: ~U[2026-03-31 22:30:00Z],
        vat_rate: Decimal.new("19.00"),
        items: [other_item(1, "Wartung", "1", nil, "100.00")]
      )

    report = AnnualReport.build(2026, "invoice", %{counted: [plain], cancelled: [cancelled]})
    refute report.vat?
    refute report.small_business?
    # The day in the app's time zone: 00:30 summer time in Berlin.
    assert hd(report.cancelled).cancelled_on == ~D[2026-04-01]

    assert AnnualReport.build(2026, "invoice", %{counted: [plain]}).small_business?
  end

  test "a year without invoices has sums of zero" do
    report = AnnualReport.build(2025, "invoice", %{counted: []})

    assert report.totals.count == 0
    assert report.totals.hours == nil
    refute report.totals.time? or report.totals.other? or report.vat?

    assert AnnualReport.invoices_csv(report) =~
             "\r\nSumme (0 Rechnungen);;;;;;0,00;;0,00;0,00\r\n"
  end

  test "year and basis from the address of a page" do
    assert AnnualReport.parse_year("2026") == 2026
    assert AnnualReport.parse_year(" 2025 ") == 2025
    assert AnnualReport.parse_year("2026x") == nil
    assert AnnualReport.parse_year("0") == nil
    assert AnnualReport.parse_year(nil) == nil
    assert AnnualReport.parse_basis("invoice") == "invoice"
    assert AnnualReport.parse_basis("paid") == "paid"
    assert AnnualReport.parse_basis("other") == "paid"
    assert AnnualReport.recipient_name(nil) == ""
  end
end
