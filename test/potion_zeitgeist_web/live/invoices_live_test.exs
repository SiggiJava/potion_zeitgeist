defmodule PotionZeitgeistWeb.InvoicesLiveTest do
  use PotionZeitgeistWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PotionZeitgeist.Fixtures

  alias PotionZeitgeist.Invoicing

  setup %{conn: conn} do
    admin = admin_fixture(%{"name" => "Michael"})
    project = project_fixture(%{"name" => "Website"})
    first = entry_fixture(admin, "2026-10-01 08:00:00", "2026-10-01 12:00:00", project)
    second = entry_fixture(admin, "2026-10-02 08:00:00", "2026-10-02 08:30:00")

    %{
      conn: Plug.Test.init_test_session(conn, user_id: admin.id),
      admin: admin,
      project: project,
      entries: [first, second]
    }
  end

  test "a new letter template starts from the sample letter", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/admin/invoice-templates/new")

    assert html =~ "Max Mustermann"
    assert has_element?(view, "#template-preview", "Rechnung Nr. #{Invoicing.today().year}-001")

    view
    |> form("#template-form",
      invoice_template: %{
        name: "Standard",
        sender: "Michael Beispiel\nHauptstraße 1\n12345 Musterstadt",
        tax_id: "Steuernummer: 12/345/67890"
      }
    )
    |> render_submit()

    assert_redirect(view, ~p"/admin/invoice-templates")

    assert [%{name: "Standard", tax_id: "Steuernummer: 12/345/67890"}] =
             Invoicing.list_templates()
  end

  test "an invoice bills the selected time of a month and can be issued and printed", ctx do
    template = template_fixture()
    {:ok, view, _html} = live(ctx.conn, ~p"/admin/invoices/new")

    view |> form("#invoice-form", invoice: %{month: "2026-10"}) |> render_change()
    assert has_element?(view, "#group-#{ctx.project.id}")
    assert has_element?(view, "#group-none")

    view |> element("#toggle-group-#{ctx.project.id}") |> render_click()

    html =
      view
      |> form("#invoice-form", invoice: %{hourly_rate: "80", template_id: template.id})
      |> render_change()

    assert html =~ "320,00 €"
    assert has_element?(view, "#unselected-hint", "1 entry")

    {:ok, show, _html} =
      view
      |> form("#invoice-form", invoice: %{recipient: "Kunde GmbH\nWeg 2\n10115 Berlin"})
      |> render_submit()
      |> follow_redirect(ctx.conn)

    [invoice] = Invoicing.list_invoices()
    assert invoice.status == "draft"
    assert Invoicing.entry_ids(invoice) == [hd(ctx.entries).id]
    assert has_element?(show, "#invoice-letter", "ENTWURF")

    show |> element("#issue-invoice") |> render_click()
    assert has_element?(show, "#last-issued", "first invoice")

    show
    |> form("#issue-form", issue: %{number: "2026-017", invoice_date: "2026-11-02"})
    |> render_submit()

    invoice = Invoicing.get_invoice!(invoice.id)
    assert invoice.status == "issued"
    assert invoice.number == "2026-017"

    html = ctx.conn |> get(~p"/admin/invoices/#{invoice}/print") |> html_response(200)
    assert html =~ "<title>Rechnung 2026-017 Kunde GmbH</title>"
    assert html =~ "Rechnung Nr. 2026-017"
    assert html =~ "320,00 €"
    assert html =~ "Gemäß § 19 UStG"
    assert html =~ "Steuernummer: 12/345/67890"
    assert html =~ "Tätigkeitsnachweis"
  end

  test "a draft can be edited and a stale edit page cannot change an issued invoice", ctx do
    template = template_fixture()
    invoice = draft_fixture(template, ctx.entries)

    {:ok, edit, _html} = live(ctx.conn, ~p"/admin/invoices/#{invoice}/edit")
    assert has_element?(edit, "#entry-#{hd(ctx.entries).id}[checked]")

    {:ok, _} =
      Invoicing.issue_invoice(invoice, %{"number" => "1", "invoice_date" => "2026-11-02"})

    {:error, {:live_redirect, %{to: path}}} =
      edit |> form("#invoice-form", invoice: %{hourly_rate: "90"}) |> render_submit()

    assert path == ~p"/admin/invoices/#{invoice}"
    assert Decimal.equal?(Invoicing.get_invoice!(invoice.id).hourly_rate, Decimal.new(80))
  end

  test "a cancelled invoice can be corrected with the same entries", ctx do
    template = template_fixture()
    invoice = draft_fixture(template, ctx.entries)

    {:ok, invoice} =
      Invoicing.issue_invoice(invoice, %{"number" => "1", "invoice_date" => "2026-11-02"})

    {:ok, show, _html} = live(ctx.conn, ~p"/admin/invoices/#{invoice}")
    show |> element("#cancel-invoice") |> render_click()
    show |> element("#confirm-cancel") |> render_click()
    assert Invoicing.get_invoice!(invoice.id).status == "cancelled"

    {:ok, form, _html} = live(ctx.conn, ~p"/admin/invoices/new?#{[from: invoice.id]}")

    for entry <- ctx.entries do
      assert has_element?(form, "#entry-#{entry.id}[checked]")
    end

    assert has_element?(form, "#invoice-recipient", "Kunde GmbH")
  end

  test "invoiced entries are locked on the entries page" do
    user = user_fixture()
    entry = entry_fixture(user, "2026-10-05 08:00:00", "2026-10-05 09:00:00")
    draft_fixture(template_fixture(), [entry])

    {:ok, view, _html} =
      build_conn() |> Plug.Test.init_test_session(user_id: user.id) |> live(~p"/entries")

    assert render(view) =~ "Invoiced"
    refute has_element?(view, "button[phx-click=edit][phx-value-id='#{entry.id}']")
    assert render_click(view, "delete", %{"id" => to_string(entry.id)}) =~ "is on an invoice"
  end

  test "regular users cannot open invoices" do
    user = user_fixture()
    conn = build_conn() |> Plug.Test.init_test_session(user_id: user.id)

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/invoices")
    assert conn |> get(~p"/admin/invoices/1/print") |> redirected_to() == ~p"/"
  end
end
