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

  test "the template preview shows the letter with and without a due date", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/invoice-templates/new")

    assert has_element?(view, "#template-preview", "Fällig am")
    assert has_element?(view, "#template-preview", "bis zum")
    assert has_element?(view, "#blocks-help", "{{#faellig_am}}")

    view |> element("#preview-due-date") |> render_click()
    refute has_element?(view, "#template-preview", "Fällig am")
    refute has_element?(view, "#template-preview", "bis zum")

    html =
      view
      |> form("#template-form", invoice_template: %{body: "Bitte zahlen Sie{{#faellig_am}} bis"})
      |> render_change()

    assert html =~ "has {{#faellig_am}} in line 1 without {{/faellig_am}} on the same line"
  end

  test "an invoice can leave out the due date", ctx do
    template = template_fixture(%{"body" => "{{positionen}}\n\nZahlbar bis zum {{faellig_am}}."})
    {:ok, view, _html} = live(ctx.conn, ~p"/admin/invoices/new")
    # A date field emptied only in part (Safari) is invalid to the browser,
    # which would not send the form, so only the server checks the fields.
    assert has_element?(view, "#invoice-form[novalidate]")

    view |> form("#invoice-form", invoice: %{month: "2026-10"}) |> render_change()
    view |> element("#toggle-group-#{ctx.project.id}") |> render_click()
    refute has_element?(view, "#no-due-date")
    refute has_element?(view, "#due-date-gap")

    # The date field is hard to empty in some browsers, so there is a button.
    view |> element("#remove-due-date") |> render_click()
    assert has_element?(view, "#no-due-date")
    refute has_element?(view, "#remove-due-date")
    # The template names the due date outside a block, which leaves a gap.
    assert has_element?(view, "#due-date-gap", "{{#faellig_am}}")

    view |> form("#invoice-form", invoice: %{due_date: "2026-11-30"}) |> render_change()
    assert has_element?(view, "#remove-due-date")
    refute has_element?(view, "#due-date-gap")
    # Emptied with the keyboard, the field sends an empty value.
    view |> form("#invoice-form", invoice: %{due_date: ""}) |> render_change()
    assert has_element?(view, "#no-due-date")
    assert has_element?(view, "#due-date-gap")

    # Fixed in another tab, the template no longer leaves a gap.
    body = "{{positionen}}\n\nZahlbar{{#faellig_am}} bis zum {{faellig_am}}{{/faellig_am}}."
    {:ok, _template} = Invoicing.update_template(template, %{"body" => body})
    view |> form("#invoice-form", invoice: %{hourly_rate: "80"}) |> render_change()
    refute has_element?(view, "#due-date-gap")

    {:ok, show, _html} =
      view
      |> form("#invoice-form",
        invoice: %{hourly_rate: "80", recipient: "Kunde GmbH\nWeg 2\n10115 Berlin"}
      )
      |> render_submit()
      |> follow_redirect(ctx.conn)

    assert [%{due_date: nil}] = Invoicing.list_invoices()
    assert has_element?(show, "#invoice-letter", "Rechnungsdatum")
    refute has_element?(show, "#invoice-letter", "Fällig am")
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
    assert has_element?(show, "#invoice-letter .inv-watermark", "ENTWURF")
    # The letter is styled only by its own invoice.css, so no utility class
    # of app.css (outdated or not) can move or cover anything on it.
    assert letter_classes(show) |> Enum.reject(&String.starts_with?(&1, "inv-")) == []
    # Printed from this page, the letter gives way to a hint to use the print page.
    assert has_element?(show, "#invoice-letter .inv-print-hint", "Print / PDF")
    # The pages without margins belong to the print page only.
    refute render(show) =~ ~r/@page\s*\{/

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

    # The print page brings its own styles and fonts and none of the asset
    # build, so an outdated app.css or app.js cannot change the invoice.
    assert html =~ ".inv-sheet {"
    assert html =~ ~s(href="/fonts/inter/inter-latin-400-normal.woff2")
    refute html =~ "/assets/"
    refute html =~ "stylesheet-outdated"
    # Footer and watermark are repeated in <body> for every printed page.
    assert [_, _] = Regex.scan(~r/<footer class="inv-footer/, html)
    # The pages keep room for the footer's two lines (tax number, bank).
    assert html =~ ~s(style="--inv-footer-lines: 2")
    assert html =~ "body:not(.inv-print-page) .inv-sheet"
    # A4 pages without margins, and WebKit (Safari) marked before the page is
    # laid out, as it prints footer and watermark from the sheets.
    assert html =~ ~r/@page \{\s+size: A4;\s+margin: 0;\s+\}/
    assert html =~ ~s[classList.add("inv-webkit")]
    assert html =~ ".inv-webkit .inv-print-page .inv-sheet .inv-footer"
    # The print page checks the lines the browser prints: the boxes carry
    # their limits, and the toolbar has a warning for a wider layout.
    assert html =~ ~s(data-footer-lines="2")
    assert html =~ ~r/class="inv-sender inv-pre"\s+data-lines="7"/
    assert html =~ ~r/class="inv-recipient inv-pre"\s+data-lines="6"/
    assert html =~ ~r/class="inv-return"\s+data-lines="4"/
    assert html =~ ~s(id="inv-layout-warning")
  end

  test "an invoice can bill other items, such as material, next to time or alone", ctx do
    template = template_fixture()
    {:ok, view, _html} = live(ctx.conn, ~p"/admin/invoices/new")

    view |> form("#invoice-form", invoice: %{month: "2026-10"}) |> render_change()
    view |> element("#add-manual-item") |> render_click()
    view |> element("#add-manual-item") |> render_click()
    assert [router, cable] = manual_row_ids(view)

    html =
      view
      |> form("#invoice-form",
        invoice: %{
          template_id: template.id,
          recipient: "Kunde GmbH\nWeg 2\n10115 Berlin",
          manual_items: %{
            "0" => %{description: "Router", quantity: "2", unit: "Stk.", unit_price: "49,95"},
            "1" => %{description: "Kabel", quantity: "", unit: "", unit_price: ""}
          }
        }
      )
      |> render_change()

    assert has_element?(view, "##{router}-amount", "99,90 €")
    assert has_element?(view, "#summary-total", "99,90 €")
    assert has_element?(view, "#invoice-summary", "2 Stk. × 49,95 €")
    assert has_element?(view, "#incomplete-items-hint", "1 other item is not complete")
    # A field left blank is not reported while the row is being filled in.
    refute html =~ "enter a quantity"

    html = view |> form("#invoice-form") |> render_submit()
    assert html =~ "complete or remove the items marked below"
    assert html =~ "enter a quantity"
    assert Invoicing.list_invoices() == []

    view |> element("##{cable}-remove") |> render_click()
    refute has_element?(view, "##{cable}")

    # The browser may still send the removed row once; it stays removed.
    render_change(view, "validate", %{
      "invoice" => %{
        "manual_items" => %{
          "0" => %{"id" => router, "description" => "Router", "quantity" => "3"},
          "1" => %{"id" => cable, "description" => "Kabel", "quantity" => "1"}
        }
      }
    })

    refute has_element?(view, "##{cable}")
    assert has_element?(view, "##{router}-amount", "149,85 €")

    {:ok, show, _html} =
      view
      |> form("#invoice-form")
      |> render_submit()
      |> follow_redirect(ctx.conn)

    [invoice] = Invoicing.list_invoices()
    assert Invoicing.entry_ids(invoice) == []
    assert Decimal.equal?(invoice.gross_total, Decimal.new("149.85"))
    assert has_element?(show, "#invoice-letter", "Einzelpreis")
    assert has_element?(show, "#invoice-letter td", "Router")
    assert has_element?(show, "#invoice-letter td", "Stk.")

    # The edit page shows the item again, and time can be added to it.
    {:ok, edit, _html} = live(ctx.conn, ~p"/admin/invoices/#{invoice}/edit")
    assert [row] = manual_row_ids(edit)
    assert has_element?(edit, "##{row}-description[value='Router']")
    assert has_element?(edit, "##{row}-quantity[value='3']")
    assert has_element?(edit, "##{row}-unit-price[value='49,95']")

    edit |> element("#toggle-group-#{ctx.project.id}") |> render_click()

    {:ok, show, _html} =
      edit
      |> form("#invoice-form", invoice: %{hourly_rate: "80"})
      |> render_submit()
      |> follow_redirect(ctx.conn)

    assert [%{kind: "time", position: 1}, %{kind: "manual", position: 2}] =
             Invoicing.get_invoice!(invoice.id).items

    assert has_element?(show, "#invoice-letter td", "Std.")

    html = ctx.conn |> get(~p"/admin/invoices/#{invoice}/print") |> html_response(200)
    assert html =~ "Bezeichnung"
    assert html =~ "469,85 €"
  end

  test "after a reconnect the other items come back as the browser sends them", ctx do
    template_fixture()
    {:ok, view, _html} = live(ctx.conn, ~p"/admin/invoices/new")
    assert manual_row_ids(view) == []

    render_change(view, "recover", %{
      "invoice" => %{
        "month" => "2026-10",
        "recipient" => "Neu GmbH\nStraße 1\n12345 Ort",
        "manual_items" => %{
          "0" => %{"id" => "item-7", "description" => "Router", "quantity" => "1"},
          "1" => %{"id" => "item-9", "description" => "Kabel", "_unused_quantity" => ""}
        }
      }
    })

    assert manual_row_ids(view) == ["item-7", "item-9"]
    assert has_element?(view, "#item-9-description[value='Kabel']")
    assert has_element?(view, "#invoice-recipient", "Neu GmbH")

    # A repeated id (a row added after a server restart could get one) gets
    # an id of its own, so the rows stay apart.
    render_change(view, "recover", %{
      "invoice" => %{
        "manual_items" => %{
          "0" => %{"id" => "item-7", "description" => "Router"},
          "1" => %{"id" => "item-7", "description" => "Stecker"}
        }
      }
    })

    assert ["item-7", other] = manual_row_ids(view)
    assert other =~ ~r/^item-[0-9a-f]{16}$/
    assert has_element?(view, "#item-7-description[value='Router']")
    assert has_element?(view, "##{other}-description[value='Stecker']")

    view |> element("#item-7-remove") |> render_click()
    assert manual_row_ids(view) == [other]
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

  test "save errors show on fields the browser marked as untouched", ctx do
    template_fixture()
    {:ok, view, _html} = live(ctx.conn, ~p"/admin/invoices/new")

    # A browser marks fields the user has not touched yet with "_unused_" keys.
    render_change(view, "validate", %{
      "_target" => ["invoice", "month"],
      "invoice" => %{
        "month" => "2026-10",
        "recipient" => "",
        "_unused_recipient" => "",
        "hourly_rate" => "",
        "_unused_hourly_rate" => ""
      }
    })

    view |> element("#toggle-group-#{ctx.project.id}") |> render_click()

    # The browser sends the selected entries with the form; with time to
    # bill, the hourly rate is needed.
    html =
      render_submit(view, "save", %{
        "invoice" => %{
          "recipient" => "Kunde GmbH",
          "hourly_rate" => "",
          "entry_ids" => ["", to_string(hd(ctx.entries).id)]
        }
      })

    assert html =~ "needs the name and the full address"
    assert html =~ "is needed for one rate for all"
  end

  test "values left in hidden rate fields do not block saving", ctx do
    template = template_fixture()
    {:ok, view, _html} = live(ctx.conn, ~p"/admin/invoices/new")

    view |> form("#invoice-form", invoice: %{month: "2026-10"}) |> render_change()
    view |> element("#toggle-group-#{ctx.project.id}") |> render_click()
    view |> form("#invoice-form", invoice: %{tax_mode: "standard"}) |> render_change()
    view |> form("#invoice-form", invoice: %{vat_rate: "19 %"}) |> render_change()
    view |> form("#invoice-form", invoice: %{tax_mode: "small_business"}) |> render_change()

    {:ok, _show, _html} =
      view
      |> form("#invoice-form",
        invoice: %{
          hourly_rate: "80",
          template_id: template.id,
          recipient: "Kunde GmbH\nWeg 2\n10115 Berlin"
        }
      )
      |> render_submit()
      |> follow_redirect(ctx.conn)

    assert [%{tax_mode: "small_business"}] = Invoicing.list_invoices()
  end

  test "a reconnect keeps what was typed after picking a base invoice", ctx do
    template = template_fixture()
    [first, second] = ctx.entries
    base = draft_fixture(template, [first])
    draft_fixture(template, [second], %{"recipient" => "Andere AG\nAllee 1\n20095 Hamburg"})
    march = entry_fixture(ctx.admin, "2026-03-02 08:00:00", "2026-03-02 10:00:00", ctx.project)

    {:ok, view, _html} = live(ctx.conn, ~p"/admin/invoices/new")

    view
    |> form("#invoice-form", invoice: %{base_id: base.id})
    |> render_change(%{"_target" => ["invoice", "base_id"]})

    assert has_element?(view, "#invoice-recipient", "Kunde GmbH")

    # After a reconnect the browser sends the whole form again, with the first
    # field as target, to a freshly mounted page.
    {:ok, view, _html} = live(ctx.conn, ~p"/admin/invoices/new")

    render_change(view, "validate", %{
      "_target" => ["invoice", "month"],
      "invoice" => %{
        "month" => "2026-03",
        "base_id" => to_string(base.id),
        "hourly_rate" => "90",
        "recipient" => "Neu GmbH\nStraße 1\n12345 Ort",
        "entry_ids" => ["", to_string(march.id)]
      }
    })

    assert has_element?(view, "#hourly-rate[value='90']")
    assert has_element?(view, "#invoice-recipient", "Neu GmbH")
    assert has_element?(view, "#entry-#{march.id}[checked]")
  end

  test "the month after a base invoice is offered even without unbilled time", ctx do
    march = entry_fixture(ctx.admin, "2026-03-02 08:00:00", "2026-03-02 10:00:00", ctx.project)
    base = draft_fixture(template_fixture(), [march], %{"month" => "2026-03"})

    {:ok, view, _html} = live(ctx.conn, ~p"/admin/invoices/new?#{[from: base.id]}")

    assert has_element?(view, "#invoice-month option[selected][value='2026-04']")
  end

  test "a draft deleted in another tab leaves its pages", ctx do
    invoice = draft_fixture(template_fixture(), ctx.entries)
    {:ok, show, _html} = live(ctx.conn, ~p"/admin/invoices/#{invoice}")
    {:ok, edit, _html} = live(ctx.conn, ~p"/admin/invoices/#{invoice}/edit")
    :ok = Invoicing.delete_draft(invoice)

    show |> element("#delete-invoice") |> render_click()

    assert {:error, {:live_redirect, %{to: "/admin/invoices"}}} =
             show |> element("#confirm-delete") |> render_click()

    assert {:error, {:live_redirect, %{to: "/admin/invoices"}}} =
             edit |> form("#invoice-form") |> render_submit()
  end

  test "a link to start from a deleted invoice opens an empty form", ctx do
    invoice = draft_fixture(template_fixture(), ctx.entries)
    :ok = Invoicing.delete_draft(invoice)

    {:ok, _view, html} = live(ctx.conn, ~p"/admin/invoices/new?#{[from: invoice.id]}")

    assert html =~ "That invoice was deleted in the meantime."
  end

  test "a base invoice deleted in another tab is dropped from the select", ctx do
    template = template_fixture()
    [first, second] = ctx.entries
    base = draft_fixture(template, [first])
    draft_fixture(template, [second], %{"recipient" => "Andere AG\nAllee 1\n20095 Hamburg"})

    {:ok, view, _html} = live(ctx.conn, ~p"/admin/invoices/new")
    :ok = Invoicing.delete_draft(base)

    html =
      view
      |> form("#invoice-form", invoice: %{base_id: base.id})
      |> render_change(%{"_target" => ["invoice", "base_id"]})

    assert html =~ "That invoice was deleted in the meantime."
    refute has_element?(view, "#invoice-base option[value='#{base.id}']")
  end

  test "a template deleted in another tab is reported when saving", ctx do
    template = template_fixture()
    {:ok, view, _html} = live(ctx.conn, ~p"/admin/invoices/new")

    view |> form("#invoice-form", invoice: %{month: "2026-10"}) |> render_change()
    view |> element("#toggle-group-#{ctx.project.id}") |> render_click()
    {:ok, _} = Invoicing.delete_template(template)

    html =
      view
      |> form("#invoice-form",
        invoice: %{
          hourly_rate: "80",
          template_id: template.id,
          recipient: "Kunde GmbH\nWeg 2\n10115 Berlin"
        }
      )
      |> render_submit()

    assert html =~ "was deleted, pick another one"
    refute has_element?(view, "#invoice-template option[value='#{template.id}']")
  end

  test "an entry invoiced while the entries page is open shows the lock on delete" do
    user = user_fixture()
    entry = entry_fixture(user, "2026-10-05 08:00:00", "2026-10-05 09:00:00")

    {:ok, view, _html} =
      build_conn() |> Plug.Test.init_test_session(user_id: user.id) |> live(~p"/entries")

    assert has_element?(view, "button[phx-click=edit][phx-value-id='#{entry.id}']")

    draft_fixture(template_fixture(), [entry])

    assert render_click(view, "delete", %{"id" => to_string(entry.id)}) =~ "is on an invoice"
    refute has_element?(view, "button[phx-click=edit][phx-value-id='#{entry.id}']")
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

  defp manual_row_ids(view) do
    ~r/id="([^"]+)-description"/
    |> Regex.scan(render(view), capture: :all_but_first)
    |> Enum.map(&hd/1)
    |> Enum.filter(&String.starts_with?(&1, "item-"))
  end

  defp letter_classes(view) do
    html = view |> element("#invoice-letter") |> render()

    ~r/class="([^"]*)"/
    |> Regex.scan(html, capture: :all_but_first)
    |> Enum.flat_map(fn [classes] -> String.split(classes) end)
    |> Enum.uniq()
  end
end
