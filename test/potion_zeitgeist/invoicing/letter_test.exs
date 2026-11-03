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

  describe "blocks" do
    @with_due_date %{"faellig_am" => "16.11.2026", "gesamtbetrag" => "170,00 €", "ust" => ""}
    @without_due_date %{@with_due_date | "faellig_am" => ""}

    test "print their text only with a value, or only without one" do
      text =
        "Bitte zahlen Sie {{gesamtbetrag}}{{#faellig_am}} bis zum {{faellig_am}}{{/faellig_am}}." <>
          "{{^faellig_am}} Zahlbar sofort.{{/faellig_am}}"

      assert Letter.fill(text, @with_due_date) == "Bitte zahlen Sie 170,00 € bis zum 16.11.2026."
      assert Letter.fill(text, @without_due_date) == "Bitte zahlen Sie 170,00 €. Zahlbar sofort."
    end

    test "allow spaces in their tags and blocks of other names inside" do
      text = "{{ # faellig_am }}a{{#ust}}b{{/ust}}{{^ust}}c{{/ust}}{{ / faellig_am }}"

      assert Letter.fill(text, @with_due_date) == "ac"
      assert Letter.fill(text, @without_due_date) == ""
    end

    test "with unknown names or without their end stay visible" do
      for text <- ["{{#tippfehler}}a{{/tippfehler}}", "{{#faellig_am}}a", "a{{/faellig_am}}"] do
        assert Letter.fill(text, @with_due_date) == text
      end
    end

    test "leave out a line with nothing else, and the gap of its paragraph" do
      note = "{{^faellig_am}}Zahlbar sofort.{{/faellig_am}}"

      assert Letter.fill("A\n\n#{note}\n\nB", @with_due_date) == "A\n\nB"
      assert Letter.fill("A\n\n#{note}\n\nB", @without_due_date) == "A\n\nZahlbar sofort.\n\nB"
      assert Letter.fill("A\r\n\r\n#{note}\r\n\r\nB", @with_due_date) == "A\r\n\r\nB"
      # Inside a paragraph only the line goes.
      assert Letter.fill("A\n#{note}\nB", @with_due_date) == "A\nB"
      assert Letter.fill("A\n\n#{note}\nB\n\nC", @with_due_date) == "A\n\nB\n\nC"
      # At the start and the end of the text.
      assert Letter.fill("#{note}\n\nA", @with_due_date) == "A"
      assert Letter.fill("A\n\n#{note}", @with_due_date) == "A"
      assert Letter.fill("A\n\n#{note}\n#{note}\n\nB", @with_due_date) == "A\n\nB"
      # A line that was empty as typed stays.
      assert Letter.fill("A\n\n\nB", @with_due_date) == "A\n\n\nB"
    end

    test "fill_lines keeps the numbers of the typed lines" do
      text = "A\n{{^faellig_am}}Zahlbar sofort.{{/faellig_am}}\nB {{faellig_am}}"

      assert Letter.fill_lines(text, @with_due_date) == [{"A", 1}, {"B 16.11.2026", 3}]

      assert Letter.fill_lines(text, @without_due_date) ==
               [{"A", 1}, {"Zahlbar sofort.", 2}, {"B ", 3}]
    end

    test "are measured as typed once for each way they can print" do
      text =
        "A{{#faellig_am}} bis {{faellig_am}}{{/faellig_am}}\n{{^faellig_am}}Sofort.{{/faellig_am}}"

      assert Letter.typed_lines(text, @with_due_date) == [{"A bis {{faellig_am}}", 1}]
      assert Letter.typed_lines(text, @without_due_date) == [{"A", 1}, {"Sofort.", 2}]

      assert Letter.typed_variants(text) == [
               [{"A", 1}, {"Sofort.", 2}],
               [{"A bis {{faellig_am}}", 1}]
             ]

      assert Letter.typed_variants("{{#tippfehler}}a{{/tippfehler}} {{rechnungsnummer}}") ==
               [[{"{{#tippfehler}}a{{/tippfehler}} {{rechnungsnummer}}", 1}]]
    end

    test "must open and close on one line" do
      assert Letter.block_errors("A {{#faellig_am}}x{{/faellig_am}}\n{{^ust}}y{{/ust}}") == []
      # Unknown names stay visible as typed, like unknown placeholders.
      assert Letter.block_errors("{{#tippfehler}}") == []

      assert Letter.block_errors("Zahlbar\n{{#faellig_am}}bis\n{{faellig_am}}{{/faellig_am}}") ==
               [
                 "has {{#faellig_am}} in line 2 without {{/faellig_am}} on the same line",
                 "has {{/faellig_am}} without {{#faellig_am}} before it in line 3"
               ]

      assert Letter.block_errors("{{#faellig_am}}{{^ust}}x{{/faellig_am}}{{/ust}}") ==
               ["closes {{/faellig_am}} before {{/ust}} in line 1"]

      assert Letter.block_errors("{{#faellig_am}}{{^faellig_am}}x{{/faellig_am}}{{/faellig_am}}") ==
               ["has {{^faellig_am}} in a block of the same name in line 1"]
    end

    test "tell whether a placeholder prints outside its block" do
      assert Letter.bare_placeholder?("bis zum {{ faellig_am }}", "faellig_am")

      refute Letter.bare_placeholder?(
               "{{#faellig_am}}bis {{faellig_am}}{{/faellig_am}}",
               "faellig_am"
             )

      assert Letter.bare_placeholder?(
               "{{^faellig_am}}{{faellig_am}}{{/faellig_am}}",
               "faellig_am"
             )

      refute Letter.bare_placeholder?("Fällig {{rechnungsdatum}}", "faellig_am")
      refute Letter.bare_placeholder?(nil, "faellig_am")
    end
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

  test "an invoice of time only keeps its columns of hours and hourly rate" do
    letter = Letter.build(issued_invoice(%{}))

    assert letter.item_columns == :hours
    assert [%{position: 1, hours: "2,00", rate: "85,00 €"} = row] = letter.items
    refute Map.has_key?(row, :quantity)
  end

  test "other items print with quantity, unit and price per unit, time in hours" do
    invoice =
      issued_invoice(%{
        items: [
          %{
            kind: "time",
            position: 1,
            description: "Website",
            minutes: 120,
            hours: Decimal.new("2.00"),
            hourly_rate: Decimal.new("85.00"),
            amount: Decimal.new("170.00")
          },
          %{
            kind: "manual",
            position: 2,
            description: "Netzwerkkabel",
            quantity: Decimal.new("1250.500"),
            unit: "m",
            unit_price: Decimal.new("0.40"),
            amount: Decimal.new("500.20")
          },
          %{
            kind: "manual",
            position: 3,
            description: "Einrichtung",
            quantity: Decimal.new("1.000"),
            unit: nil,
            unit_price: Decimal.new("99.00"),
            amount: Decimal.new("99.00")
          }
        ],
        net_total: Decimal.new("769.20"),
        gross_total: Decimal.new("769.20"),
        letter_body: "{{positionen}}\n{{stunden}} Stunden, {{gesamtbetrag}}"
      })

    letter = Letter.build(invoice)
    assert letter.item_columns == :quantity

    assert [
             %{position: 1, quantity: "2,00", unit: "Std.", price: "85,00 €", amount: "170,00 €"},
             %{
               position: 2,
               description: "Netzwerkkabel",
               quantity: "1.250,5",
               unit: "m",
               price: "0,40 €",
               amount: "500,20 €"
             },
             %{position: 3, quantity: "1", unit: "", price: "99,00 €"}
           ] = letter.items

    # {{stunden}} are the hours of the time entries.
    assert letter.after_items == "2,00 Stunden, 769,20 €"
    assert letter.totals == [{"Gesamtbetrag", "769,20 €"}]
  end

  test "an invoice without a due date prints none" do
    body =
      "Leistungen {{monat}}:\n{{positionen}}\n\n" <>
        "Summe {{gesamtbetrag}}{{#faellig_am}}, fällig {{faellig_am}}{{/faellig_am}}.\n\n" <>
        "{{^faellig_am}}Zahlbar sofort ohne Abzug.{{/faellig_am}}\n\nMit freundlichen Grüßen"

    letter = Letter.build(issued_invoice(%{letter_body: body}))
    assert {"Fällig am", "16.11.2026"} in letter.info
    assert letter.after_items == "Summe 170,00 €, fällig 16.11.2026.\n\nMit freundlichen Grüßen"

    letter = Letter.build(issued_invoice(%{letter_body: body, due_date: nil}))
    refute List.keymember?(letter.info, "Fällig am", 0)

    assert letter.after_items ==
             "Summe 170,00 €.\n\nZahlbar sofort ohne Abzug.\n\nMit freundlichen Grüßen"
  end

  test "the tax number line prints its blocks also where {{steuernummer}} is used" do
    invoice =
      issued_invoice(%{
        letter_tax_id: "Steuernummer: 12/345/67890{{#ust}} · USt-IdNr.: DE123456789{{/ust}}",
        letter_footer: "IBAN DE12 · {{steuernummer}}"
      })

    letter = Letter.build(invoice)
    assert letter.tax_id == "Steuernummer: 12/345/67890"
    assert letter.footer == "IBAN DE12 · Steuernummer: 12/345/67890"

    letter =
      Letter.build(%{
        invoice
        | tax_mode: "standard",
          vat_rate: Decimal.new("19"),
          vat_total: Decimal.new("32.30"),
          gross_total: Decimal.new("202.30")
      })

    assert letter.tax_id == "Steuernummer: 12/345/67890 · USt-IdNr.: DE123456789"
    assert letter.footer == "IBAN DE12 · Steuernummer: 12/345/67890 · USt-IdNr.: DE123456789"
  end

  test "the sample template names the due date only when there is one" do
    template = PotionZeitgeist.Invoicing.sample_template()

    assert Letter.sample(template, ~D[2026-11-03]).after_items =~
             "Betrag von 3.102,50 € bis zum 17.11.2026 unter Angabe der Rechnungsnummer 2026-001"

    letter = Letter.sample(template, ~D[2026-11-03], due_date: false)
    assert letter.after_items =~ "Betrag von 3.102,50 € unter Angabe der Rechnungsnummer 2026-001"
    refute List.keymember?(letter.info, "Fällig am", 0)
  end

  test "texts that print line by line start and end without an empty line" do
    letter =
      Letter.build(
        issued_invoice(%{
          recipient: "\r\nKunde GmbH\r\nWeg 2\r\n10115 Berlin\r\n",
          letter_sender: "\nMichael Beispiel\nHauptstraße 1\n12345 Musterstadt\n\n",
          letter_footer: "IBAN DE12\n"
        })
      )

    assert letter.recipient == "Kunde GmbH\r\nWeg 2\r\n10115 Berlin"
    assert letter.sender == "Michael Beispiel\nHauptstraße 1\n12345 Musterstadt"
    assert letter.footer == "IBAN DE12"
  end

  test "boxed texts print without invisible characters and with composed umlauts" do
    sender = :unicode.characters_to_nfd_binary("Michael Bäcker\nHauptstraße 1\n12345 Musterstadt")

    letter =
      Letter.build(
        issued_invoice(%{
          recipient: "Kunden\u00ADservice GmbH\nWeg\u200B 2\n10115 Berlin",
          letter_sender: sender,
          letter_footer: "IBAN\u2060 DE12"
        })
      )

    assert letter.recipient == "Kundenservice GmbH\nWeg 2\n10115 Berlin"
    assert letter.sender == "Michael Bäcker\nHauptstraße 1\n12345 Musterstadt"
    assert letter.sender_line == "Michael Bäcker · Hauptstraße 1 · 12345 Musterstadt"
    assert letter.footer == "IBAN DE12"
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

  test "the return address keeps postcode and city" do
    assert Letter.build(issued_invoice(%{})).sender_line ==
             "Michael Beispiel · Hauptstraße 1 · 12345 Musterstadt"

    sender = "Michael Beispiel\nSoftwareentwicklung\nHauptstraße 1\n12345 Musterstadt\nTel. 0123"

    assert Letter.build(issued_invoice(%{letter_sender: sender})).sender_line ==
             "Michael Beispiel · Hauptstraße 1 · 12345 Musterstadt"

    assert Letter.build(issued_invoice(%{letter_sender: "Max\nPostfach 12\nWien"})).sender_line ==
             "Max · Postfach 12 · Wien"
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
