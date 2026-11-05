defmodule PotionZeitgeistWeb.AnnualReportControllerTest do
  use PotionZeitgeistWeb.ConnCase, async: true

  import PotionZeitgeist.Fixtures

  setup %{conn: conn} do
    admin = admin_fixture()
    project = project_fixture(%{"name" => "Website"})
    template = template_fixture()
    entry = entry_fixture(admin, "2026-10-01 08:00:00", "2026-10-01 12:00:00", project)

    issued_fixture(template, [entry], "2026-001", "2026-11-02", %{
      "manual_items" => manual_items([{"Netzwerkkabel", "3", "Stk.", "4,50"}]),
      "paid_on" => "2026-11-03"
    })

    issued_fixture(template, [], "2026-002", "2026-11-03", %{
      "manual_items" => manual_items([{"Lizenz", "1", "", "100"}])
    })

    %{conn: Plug.Test.init_test_session(conn, user_id: admin.id)}
  end

  test "the invoices CSV counts the invoices paid in the year", %{conn: conn} do
    conn = get(conn, ~p"/admin/invoices/annual/2026/csv")

    assert response_content_type(conn, :csv)

    assert get_resp_header(conn, "content-disposition") ==
             [~s(attachment; filename="rechnungen_2026_nach_zahlungseingang.csv")]

    assert response(conn, 200) ==
             "﻿Rechnungsnummer;Rechnungsdatum;Bezahlt am;Empfänger;Leistungszeitraum;" <>
               "Stunden;Netto;USt-Satz;USt;Brutto\r\n" <>
               "2026-001;02.11.2026;03.11.2026;Kunde GmbH;01.10.2026 – 31.10.2026;" <>
               "4,00;333,50;0;0,00;333,50\r\n" <>
               "Summe (1 Rechnung);;;;;4,00;333,50;;0,00;333,50\r\n"
  end

  test "the items CSV by invoice date lists the time and other items", %{conn: conn} do
    conn = get(conn, ~p"/admin/invoices/annual/2026/csv?#{[basis: "invoice", type: "items"]}")

    assert get_resp_header(conn, "content-disposition") ==
             [~s(attachment; filename="positionen_2026_nach_rechnungsdatum.csv")]

    csv = response(conn, 200)

    assert csv =~
             "\r\n2026-001;02.11.2026;03.11.2026;Kunde GmbH;1;Zeit;Website;Website;" <>
               "4,00;Std.;80,00;320,00\r\n"

    assert csv =~
             "\r\n2026-001;02.11.2026;03.11.2026;Kunde GmbH;2;Einzelposten;Netzwerkkabel;;" <>
               "3;Stk.;4,50;13,50\r\n"

    assert csv =~
             "\r\n2026-002;03.11.2026;;Kunde GmbH;1;Einzelposten;Lizenz;;1;;100,00;100,00\r\n"

    assert csv =~ "\r\nSumme Zeit;;;;;;;;4,00;Std.;;320,00\r\n"
    assert csv =~ "\r\nSumme Einzelposten;;;;;;;;;;;113,50\r\n"
    assert String.ends_with?(csv, "\r\nSumme (2 Rechnungen);;;;;;;;;;;433,50\r\n")
  end

  test "the print page shows the year in German with its own styles", %{conn: conn} do
    html = conn |> get(~p"/admin/invoices/annual/2026/print") |> html_response(200)

    assert html =~ "<title>Einnahmenübersicht 2026 nach Zahlungseingang</title>"
    assert html =~ "Einnahmenübersicht 2026"
    assert html =~ "Zuflussprinzip, § 11 EStG"
    assert html =~ "Rechnung 2026-001 vom 02.11.2026"
    assert html =~ "bezahlt am 03.11.2026"
    assert html =~ "Netzwerkkabel"
    assert html =~ "333,50 €"
    assert html =~ "Summe 2026 (1 Rechnung)"
    # The invoice without payment is listed apart and not counted.
    assert html =~ "Noch nicht bezahlt"
    assert html =~ ~r/id="report-unpaid".*2026-002/s
    refute html =~ "433,50 €"
    assert html =~ "Kleinunternehmer nach"

    # Like the invoice print page: own styles, none of the asset build, and
    # A4 pages with margins.
    assert html =~ ".rpt-paper {"
    assert html =~ ~r/@page \{\s+size: A4;\s+margin: 15mm/
    refute html =~ "/assets/"
    assert html =~ ~s(id="print-report")
  end

  test "the print page by invoice date counts both invoices", %{conn: conn} do
    html =
      conn
      |> get(~p"/admin/invoices/annual/2026/print?#{[basis: "invoice"]}")
      |> html_response(200)

    assert html =~ "Rechnungsdatum im Jahr 2026"
    assert html =~ "433,50 €"
    assert html =~ "Diese Übersicht zählt nach Rechnungsdatum."

    refute html =~ "Noch nicht bezahlt"
  end

  test "a year without invoices", %{conn: conn} do
    html = conn |> get(~p"/admin/invoices/annual/2024/print") |> html_response(200)
    assert html =~ "Im Jahr 2024 ist keine Zahlung für eine Rechnung eingegangen."

    csv = conn |> get(~p"/admin/invoices/annual/2024/csv") |> response(200)
    assert csv =~ "\r\nSumme (0 Rechnungen);;;;;;0,00;;0,00;0,00\r\n"
  end

  test "an unknown year is not found", %{conn: conn} do
    assert conn |> get(~p"/admin/invoices/annual/next/csv") |> response(404)
    assert conn |> get(~p"/admin/invoices/annual/0/print") |> response(404)
  end

  test "regular users cannot export the annual report" do
    user = user_fixture()
    conn = build_conn() |> Plug.Test.init_test_session(user_id: user.id)

    assert conn |> get(~p"/admin/invoices/annual/2026/csv") |> redirected_to() == ~p"/"
    assert conn |> get(~p"/admin/invoices/annual/2026/print") |> redirected_to() == ~p"/"
  end
end
