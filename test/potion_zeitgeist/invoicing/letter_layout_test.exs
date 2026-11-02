defmodule PotionZeitgeist.Invoicing.LetterLayoutTest do
  use ExUnit.Case, async: true

  alias PotionZeitgeist.Invoicing.LetterLayout

  test "counts every line, blank lines between text included" do
    assert LetterLayout.printed_lines(nil, :recipient) == 0
    assert LetterLayout.printed_lines(" \n ", :recipient) == 0
    assert LetterLayout.printed_lines("\nA\r\n\r\nB\n", :recipient) == 3
    assert LetterLayout.max_lines(:recipient) == 6
  end

  test "counts the width of the letters, not how many there are" do
    assert LetterLayout.printed_lines(String.duplicate("i", 60), :recipient) == 1
    assert LetterLayout.printed_lines(String.duplicate("W", 30), :recipient) == 2
    # A word wider than the box is split.
    assert LetterLayout.printed_lines(String.duplicate("x", 200), :recipient) == 5
  end

  # Line counts of Chromium for the same texts in the boxes of invoice.css.
  @browser [
    {:recipient, "Musterfirma Beratungsgesellschaft für Informationstechnologie mbH & Co. KG", 2},
    {:recipient, "Müller & Söhne Maschinenbau GmbH & Co. KG", 1},
    {:recipient, "z. Hd. Frau Dr. Erika Musterfrau-Schmidtbauer", 1},
    {:recipient, "Abteilung Einkauf, Rechnungsprüfung und Kreditorenbuchhaltung", 2},
    {:recipient, "Hans-Böckler-Straße 123, Hinterhaus links, Aufgang C", 2},
    # Breaks after the dashes and hyphens, which leaves the lines short.
    {:recipient, "Wasserversorgungsverband–Abwasserzweckverband–Kreditorenbuchhaltung", 3},
    {:recipient, "BE-973277-WARTUNG-883348-RECHNUNGSEINGANG-INSTANDHALTUNG-105477", 3},
    # No break after a dash that starts a word, before a letter other than a to z.
    {:recipient,
     "Abnahme und Einkauf Süd Schmidt und -Übergabe und Schulung Weber Lieferung Werk", 3},
    {:recipient,
     "Prüfung Montage Prüfung Süd Abnahme und –Änderung Weber Halle Dokumentation Wartung", 3},
    {:sender, "E-Mail: max.mustermann@beispiel-domain-mit-langem-namen.de", 2},
    {:sender, "Telefon 0123 456789 · Fax 0123 456780 · Mobil 0170 1234567", 2},
    {:footer,
     "Kontoinhaber: Max Mustermann · Musterbank Musterstadt eG · " <>
       "IBAN: DE00 0000 0000 0000 0000 00 · BIC: XXXXXXXXXXX", 1},
    {:footer,
     "Max Mustermann Softwareentwicklung und IT-Beratung GmbH & Co. KG · Sitz Musterstadt · " <>
       "Amtsgericht Musterstadt HRA 12345 · Komplementärin: Max Mustermann Verwaltungs GmbH, " <>
       "Amtsgericht Musterstadt HRB 67890", 2},
    {:return,
     "Dr. rer. nat. Maximilian Alexander Mustermann-Schmidtbauer, öffentlich bestellter " <>
       "und vereidigter Sachverständiger für Informationstechnologie · Ingenieurbüro für " <>
       "Informationstechnologie, Datenschutz und IT-Sicherheit, Musterstraße 123, " <>
       "Hinterhaus · 12345 Musterstadt", 5}
  ]

  test "breaks lines where the browser does" do
    for {box, text, lines} <- @browser do
      assert {text, LetterLayout.printed_lines(text, box)} == {text, lines}
    end
  end

  test "measures text as the letter prints it" do
    composed = "Bäckerei Müller & Söhne Großhandel GmbH"
    decomposed = :unicode.characters_to_nfd_binary(composed)

    assert decomposed != composed
    assert LetterLayout.clean(decomposed) == composed
    assert LetterLayout.printed_lines(decomposed, :recipient) == 1

    # Soft hyphens, zero width spaces and other invisible characters are
    # left out, so they cannot add places to break a line.
    assert LetterLayout.clean("Donau\u00ADdampf\u200Bschiff\u2060fahrt\uFEFF") ==
             "Donaudampfschifffahrt"

    assert LetterLayout.clean(nil) == ""

    # Bytes that are not UTF-8 become the replacement character.
    assert LetterLayout.clean(<<"Kunde ", 0xFF>>) == "Kunde \uFFFD"
    assert LetterLayout.printed_lines(<<"Kunde ", 0xFF, " GmbH">>, :recipient) == 1
  end

  test "refuses characters the invoice font does not have" do
    # A browser prints them with a font of the computer, of unknown width.
    assert LetterLayout.check(
             "☎ 0123 456789 · 📱 0170 1234567 · 📧 max@beispiel.de · 🌐 www.beispiel.de",
             :footer
           ) == {:error, "has characters the invoice font does not have: ☎ 📱 📧 🌐"}

    assert LetterLayout.check("Steuernummer: 12/345/67890 ✅", :tax_id) ==
             {:error, "has characters the invoice font does not have: ✅"}

    # Characters that do not show on their own are named by their code.
    assert LetterLayout.check("Hotline 1\uFE0F\u20E3", :sender) ==
             {:error, "has characters the invoice font does not have: U+FE0F U+20E3"}

    assert LetterLayout.check("Hans-Böckler-Straße 1 – Hinterhaus\nŁódź", :recipient) == :ok

    assert LetterLayout.check(<<"Kunde ", 0xFF>>, :recipient) ==
             {:error, "has characters the invoice font does not have: \uFFFD"}

    assert LetterLayout.check_characters("2026-001 ✓") ==
             {:error, "has characters the invoice font does not have: ✓"}

    assert LetterLayout.check_characters("RE-2026-001") == :ok
    assert LetterLayout.check_characters(nil) == :ok
  end

  test "names the lines that are too long" do
    assert LetterLayout.check("Kunde GmbH\nWeg 2\n10115 Berlin", :recipient) == :ok

    assert LetterLayout.check(Enum.map_join(1..8, "\n", &"Zeile #{&1}"), :sender) ==
             {:error, "has 8 lines, the letterhead has room for 7"}

    long = "Musterfirma Beratungsgesellschaft für Informationstechnologie mbH"

    assert LetterLayout.check(Enum.join([long, "A", long, "B", "C"], "\n"), :recipient) ==
             {:error,
              "takes 7 lines in the address field, which has room for 6: " <>
                "lines 1 and 3 are too long for one line"}

    # Line numbers as typed, blank lines at the start included.
    assert LetterLayout.check(Enum.join(["", long, "A", "B", "C", "D", "E"], "\n"), :recipient) ==
             {:error,
              "takes 7 lines in the address field, which has room for 6: " <>
                "line 2 is too long for one line"}

    # Line numbers of the text as typed, also when its lines are filled in.
    fill = &String.replace(&1, "{{firma}}", long)

    typed = Enum.join(["A", "{{firma}}", "B", "C", "D", "E", "F"], "\n")

    assert LetterLayout.check(typed, :sender) == :ok

    # A line break at the end of a filled in value does not print, as the
    # letter prints its texts trimmed.
    address = &String.replace(&1, "{{empfaenger}}", "B\r\nC\r\nD\r\nE\r\nF\r\nG\r\n")
    assert LetterLayout.check("A\n{{empfaenger}}", :sender, address) == :ok

    assert LetterLayout.check(typed, :sender, fill) ==
             {:error,
              "takes 8 lines in the letterhead, which has room for 7: " <>
                "line 2 is too long for one line"}

    assert LetterLayout.check(String.duplicate("Steuernummer 12/345/67890 ", 8), :tax_id) ==
             {:error, "is too long for one line of the footer"}

    assert LetterLayout.check(String.duplicate("Musterstraße 1 · ", 18), :return) ==
             {:error,
              "gives a return address of 5 lines above the recipient, which has room for 4: " <>
                "shorten the lines with name, street, postcode and city"}
  end
end
