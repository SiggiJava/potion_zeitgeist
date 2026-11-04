defmodule PotionZeitgeistWeb.AnnualReportLiveTest do
  use PotionZeitgeistWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PotionZeitgeist.Fixtures

  alias PotionZeitgeist.Invoicing

  setup %{conn: conn} do
    admin = admin_fixture(%{"name" => "Michael"})
    project = project_fixture(%{"name" => "Website"})
    template = template_fixture()
    entry = entry_fixture(admin, "2026-10-01 08:00:00", "2026-10-01 12:00:00", project)

    paid =
      issued_fixture(template, [entry], "2026-001", "2026-11-02", %{"paid_on" => "2026-11-03"})

    open =
      issued_fixture(template, [], "2026-002", "2026-11-03", %{
        "manual_items" => manual_items([{"Lizenz", "1", "", "100"}])
      })

    %{
      conn: Plug.Test.init_test_session(conn, user_id: admin.id),
      template: template,
      paid: paid,
      open: open
    }
  end

  test "the invoices page links to the annual report and shows payments", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/admin/invoices")

    assert has_element?(view, "#invoice-#{ctx.paid.id}", "Paid")
    assert has_element?(view, "#invoice-#{ctx.paid.id}", "03.11.2026")
    assert has_element?(view, "#invoice-#{ctx.open.id}", "Issued")

    assert {:ok, _report, html} =
             view |> element("#annual-report") |> render_click() |> follow_redirect(ctx.conn)

    assert html =~ "Annual report"
  end

  test "the annual report counts by payment date and lists open invoices", ctx do
    old =
      issued_fixture(ctx.template, [], "2024-009", "2024-12-30", %{
        "manual_items" => manual_items([{"Material", "2", "Stk.", "25"}])
      })

    {:ok, view, _html} = live(ctx.conn, ~p"/admin/invoices/annual?#{[year: 2026]}")

    assert has_element?(view, "#report-invoices-#{ctx.paid.id}")
    refute has_element?(view, "#report-invoices-#{ctx.open.id}")
    assert has_element?(view, "#report-total", "320,00 €")
    assert has_element?(view, "#unpaid-#{ctx.open.id}", "100,00 €")

    assert has_element?(
             view,
             ~s(#csv-items[href="/admin/invoices/annual/2026/csv?basis=paid&type=items"])
           )

    assert has_element?(
             view,
             ~s(#print-report[href="/admin/invoices/annual/2026/print?basis=paid"])
           )

    view |> element("#basis-invoice") |> render_click()
    assert_patch(view, ~p"/admin/invoices/annual?#{[year: 2026, basis: "invoice"]}")
    assert has_element?(view, "#report-invoices-#{ctx.open.id}")
    assert has_element?(view, "#report-total", "420,00 €")
    refute has_element?(view, "#report-unpaid")

    view |> form("#year-form", %{year: "2024"}) |> render_change()
    assert_patch(view, ~p"/admin/invoices/annual?#{[year: 2024, basis: "invoice"]}")
    assert has_element?(view, "#report-invoices-#{old.id}")
    assert has_element?(view, "#report-total", "50,00 €")

    view |> element("#basis-paid") |> render_click()
    assert_patch(view, ~p"/admin/invoices/annual?#{[year: 2024, basis: "paid"]}")
    assert has_element?(view, "#report-empty", "No payments recorded in 2024.")
    assert has_element?(view, "#unpaid-#{old.id}")
    refute has_element?(view, "#unpaid-#{ctx.open.id}")
  end

  test "a payment can be recorded from the list of open invoices", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/admin/invoices/annual?#{[year: 2026]}")

    tomorrow = Invoicing.today() |> Date.add(1) |> Date.to_iso8601()

    html =
      view
      |> form("#pay-#{ctx.open.id}", %{payment: %{paid_on: tomorrow}})
      |> render_submit()

    assert html =~ "must not be in the future"
    assert has_element?(view, ~s(#pay-#{ctx.open.id} input[value="#{tomorrow}"]))
    assert Invoicing.get_invoice!(ctx.open.id).paid_on == nil

    view
    |> form("#pay-#{ctx.open.id}", %{payment: %{paid_on: "2026-11-04"}})
    |> render_submit()

    assert Invoicing.get_invoice!(ctx.open.id).paid_on == ~D[2026-11-04]
    refute has_element?(view, "#report-unpaid")
    assert has_element?(view, "#report-invoices-#{ctx.open.id}")
    assert has_element?(view, "#report-total", "420,00 €")
  end

  test "an issued invoice records, changes and removes its payment date", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/admin/invoices/#{ctx.open}")

    assert has_element?(view, "#payment", "Not paid yet")

    view
    |> form("#payment-form", payment: %{paid_on: "2026-11-03"})
    |> render_submit()

    assert has_element?(view, "#paid-on", "03.11.2026")
    assert has_element?(view, "h1 .badge", "Paid")
    assert Invoicing.get_invoice!(ctx.open.id).paid_on == ~D[2026-11-03]

    view |> element("#change-payment") |> render_click()
    html = view |> form("#payment-form", payment: %{paid_on: ""}) |> render_submit()
    assert html =~ "enter the day the payment came in"
    assert Invoicing.get_invoice!(ctx.open.id).paid_on == ~D[2026-11-03]

    view |> form("#payment-form", payment: %{paid_on: "2026-11-04"}) |> render_submit()
    assert has_element?(view, "#paid-on", "04.11.2026")

    view |> element("#mark-unpaid") |> render_click()
    assert has_element?(view, "#payment", "Not paid yet")
    assert Invoicing.get_invoice!(ctx.open.id).paid_on == nil
  end

  test "cancelling a paid invoice says it no longer counts", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/admin/invoices/#{ctx.paid}")

    view |> element("#cancel-invoice") |> render_click()
    assert has_element?(view, "#cancel-paid-note", "03.11.2026")

    view |> element("#confirm-cancel") |> render_click()
    refute has_element?(view, "#payment")
    assert render(view) =~ "no longer counts in the annual report"
  end

  test "a stale invoice page cannot record a payment once cancelled", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/admin/invoices/#{ctx.open}")
    {:ok, _} = Invoicing.cancel_invoice(ctx.open)

    view
    |> form("#payment-form", payment: %{paid_on: "2026-11-03"})
    |> render_submit()

    assert render(view) =~ "Only issued invoices can be marked as paid."
    assert Invoicing.get_invoice!(ctx.open.id).paid_on == nil
  end

  test "regular users cannot open the annual report" do
    user = user_fixture()
    conn = build_conn() |> Plug.Test.init_test_session(user_id: user.id)

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/invoices/annual")
  end
end
