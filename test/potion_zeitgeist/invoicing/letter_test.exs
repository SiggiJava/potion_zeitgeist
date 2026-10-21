defmodule PotionZeitgeist.Invoicing.LetterTest do
  use ExUnit.Case, async: true

  alias PotionZeitgeist.Invoicing.{Invoice, InvoiceEntry, InvoiceTemplate, Letter}

  test "fills known placeholders and keeps unknown ones visible" do
    vars = %{"rechnungsnummer" => "2026-001"}

    assert Letter.fill(
             "Rechnung {{rechnungsnummer}} / {{ rechnungsnummer }} {{tippfehler}}",
             vars
           ) ==
             "Rechnung 2026-001 / 2026-001 {{tippfehler}}"
  end

  test "splits the body at the items placeholder" do
    assert Letter.split_body("Hallo,\n\n{{positionen}}\n\nGruß") == {"Hallo,", "Gruß"}
    assert Letter.split_body("Nur Text") == {"Nur Text", ""}
  end

  defp issued_invoice(attrs) do
    struct!(
      %Invoice{
        status: "issued",
        number: "2026-007",
        invoice_date: ~D[2026-11-02],
        due_date: ~D[2026-11-16],
        period_start: ~D[2026-10-01],
        period_end: ~D[2026-10-31],
        recipient: "Kunde GmbH\nWeg 2\n10115 Berlin",
        tax_mode: "small_business",
        vat_rate: Decimal.new(0),
        net_total: Decimal.new("170.00"),
        vat_total: Decimal.new("0.00"),
        gross_total: Decimal.new("170.00"),
        show_timesheet: true,
        items: [
          %{
            position: 1,
            description: "Website",
            minutes: 120,
            hours: Decimal.new("2.00"),
            hourly_rate: Decimal.new("85.00"),
            amount: Decimal.new("170.00")
          }
        ],
        letter_sender: "Michael Beispiel\nHauptstraße 1\n12345 Musterstadt",
        letter_tax_id: "Steuernummer: 12/345/67890",
        letter_subject: "Rechnung Nr. {{rechnungsnummer}}",
        letter_body:
          "Leistungen {{monat}}:\n{{positionen}}\nSumme {{gesamtbetrag}}, fällig {{faellig_am}}.",
        letter_footer: "IBAN DE12"
      },
      attrs
    )
  end

  test "builds a small business invoice with the § 19 note and no VAT rows" do
    letter = Letter.build(issued_invoice(%{}))

    assert letter.subject == "Rechnung Nr. 2026-007"
    assert letter.before_items == "Leistungen Oktober 2026:"
    assert letter.after_items == "Summe 170,00 €, fällig 16.11.2026."
    assert letter.sender_line == "Michael Beispiel · Hauptstraße 1 · 12345 Musterstadt"
    assert letter.tax_id == "Steuernummer: 12/345/67890"
    assert letter.tax_note =~ "§ 19 UStG"
    assert letter.totals == [{"Gesamtbetrag", "170,00 €"}]
    assert {"Leistungszeitraum", "01.10.2026 – 31.10.2026"} in letter.info
    assert letter.watermark == nil
    assert [%{hours: "2,00", rate: "85,00 €", amount: "170,00 €"}] = letter.items
  end

  test "builds VAT rows in standard tax mode" do
    letter =
      Letter.build(
        issued_invoice(%{
          tax_mode: "standard",
          vat_rate: Decimal.new("19"),
          vat_total: Decimal.new("32.30"),
          gross_total: Decimal.new("202.30")
        })
      )

    assert letter.tax_note == nil

    assert letter.totals == [
             {"Nettobetrag", "170,00 €"},
             {"Umsatzsteuer 19 %", "32,30 €"},
             {"Gesamtbetrag", "202,30 €"}
           ]
  end

  test "drafts use the current template and say ENTWURF" do
    template = %InvoiceTemplate{
      sender: "A",
      tax_id: "St.-Nr. 1",
      subject: "Rechnung {{rechnungsnummer}}",
      body: "x",
      footer: ""
    }

    letter = Letter.build(issued_invoice(%{status: "draft", number: nil, template: template}))

    assert letter.subject == "Rechnung ENTWURF"
    assert letter.watermark == "ENTWURF"
    assert letter.tax_id == "St.-Nr. 1"
  end

  test "the time sheet adds up the entries of a day and joins their notes" do
    entries = [
      %InvoiceEntry{
        date: ~D[2026-10-02],
        minutes: 90,
        description: "Website",
        user_name: "M",
        notes: "Layout"
      },
      %InvoiceEntry{
        date: ~D[2026-10-01],
        minutes: 30,
        description: "Website",
        user_name: "M",
        notes: nil
      },
      %InvoiceEntry{
        date: ~D[2026-10-02],
        minutes: 60,
        description: "Website",
        user_name: "M",
        notes: "Texte"
      }
    ]

    sheet = Letter.build(issued_invoice(%{}), entries).timesheet

    assert sheet.title == "Tätigkeitsnachweis zur Rechnung 2026-007"
    refute sheet.show_user
    refute sheet.show_project

    assert [
             %{date: "01.10.2026", duration: "0:30"},
             %{date: "02.10.2026", duration: "2:30", notes: "Layout; Texte"}
           ] =
             sheet.rows

    assert sheet.total == "3:00"
    assert Letter.build(issued_invoice(%{show_timesheet: false}), entries).timesheet == nil
  end

  test "the PDF file name names number and recipient without slashes" do
    assert Letter.document_title(issued_invoice(%{number: "RE/2026/7"})) ==
             "Rechnung RE-2026-7 Kunde GmbH"

    assert Letter.document_title(issued_invoice(%{status: "draft", number: nil})) ==
             "ENTWURF Rechnung Kunde GmbH Oktober 2026"
  end
end
