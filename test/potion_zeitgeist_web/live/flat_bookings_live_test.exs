defmodule PotionZeitgeistWeb.FlatBookingsLiveTest do
  use PotionZeitgeistWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PotionZeitgeist.Fixtures

  alias PotionZeitgeist.{Invoicing, TimeTracking}

  setup %{conn: conn} do
    user = user_fixture(%{"name" => "Michael"})
    project = project_fixture(%{"name" => "Website"})
    %{conn: Plug.Test.init_test_session(conn, user_id: user.id), user: user, project: project}
  end

  test "users book, change and delete their flat hours", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/entries")
    refute has_element?(view, "#flat-bookings")

    view |> element("#new-flat-booking") |> render_click()
    assert has_element?(view, "#flat-booking-form")

    # The month before this one is suggested.
    month =
      Invoicing.today() |> Date.beginning_of_month() |> Date.add(-1) |> Date.beginning_of_month()

    assert has_element?(
             view,
             "#flat-booking-month option[selected][value='#{Date.to_iso8601(month)}']"
           )

    html = view |> form("#flat-booking-form", flat_booking: %{hours: "8,34"}) |> render_change()
    assert html =~ "cannot be billed in whole minutes, enter 8,33 (8:20) or 8,35 (8:21)"

    view
    |> form("#flat-booking-form",
      flat_booking: %{
        project_id: to_string(ctx.project.id),
        hours: "120",
        notes: "laut Zeiterfassung des Kunden"
      }
    )
    |> render_submit()

    assert render(view) =~ "Flat hours booked."
    refute has_element?(view, "#flat-booking-form")

    assert [booking] = TimeTracking.list_flat_bookings(ctx.user.id)
    assert booking.month == month
    assert booking.minutes == 7200
    assert booking.project_id == ctx.project.id

    assert has_element?(view, "#flat-booking-#{booking.id}", Calendar.strftime(month, "%B %Y"))
    assert has_element?(view, "#flat-booking-#{booking.id}", "120:00 h")
    assert has_element?(view, "#flat-booking-#{booking.id}", "Website")

    view |> element("#edit-flat-booking-#{booking.id}") |> render_click()
    assert has_element?(view, "#flat-booking-hours[value='120']")
    view |> form("#flat-booking-form", flat_booking: %{hours: "7:30"}) |> render_submit()

    assert render(view) =~ "Flat hours updated."
    assert has_element?(view, "#flat-booking-#{booking.id}", "7:30 h")

    view |> element("#confirm-delete-flat-booking-#{booking.id}") |> render_click()
    view |> element("#delete-flat-booking-#{booking.id}") |> render_click()

    assert render(view) =~ "Flat hours deleted."
    assert TimeTracking.list_flat_bookings(ctx.user.id) == []
    refute has_element?(view, "#flat-bookings")
  end

  test "invoiced flat hours are locked, also on a page opened before", ctx do
    booking = flat_booking_fixture(ctx.user, "2026-10-01", "120", ctx.project)
    {:ok, stale, _html} = live(ctx.conn, ~p"/entries")

    draft_fixture(template_fixture(), [], %{"booking_ids" => [to_string(booking.id)]})

    {:ok, view, _html} = live(ctx.conn, ~p"/entries")
    assert has_element?(view, "#flat-booking-#{booking.id}", "Invoiced")
    refute has_element?(view, "#edit-flat-booking-#{booking.id}")

    stale |> element("#edit-flat-booking-#{booking.id}") |> render_click()
    assert render(stale) =~ "These flat hours are on an invoice"
    assert has_element?(stale, "#flat-booking-#{booking.id}", "Invoiced")
    refute has_element?(stale, "#flat-booking-form")
  end

  test "users cannot change the flat hours of others", ctx do
    other = user_fixture()
    booking = flat_booking_fixture(other, "2026-10-01", "120")
    {:ok, view, _html} = live(ctx.conn, ~p"/entries")

    view |> with_target("#flat-hours") |> render_click("edit", %{"id" => booking.id})
    refute has_element?(view, "#flat-booking-form")

    view |> with_target("#flat-hours") |> render_click("delete", %{"id" => booking.id})
    assert [_booking] = TimeTracking.list_flat_bookings(other.id)
  end

  test "administrators book flat hours for a user", ctx do
    admin = admin_fixture()
    conn = Plug.Test.init_test_session(build_conn(), user_id: admin.id)
    {:ok, view, _html} = live(conn, ~p"/admin/users/#{ctx.user.id}/entries")

    view |> element("#new-flat-booking") |> render_click()
    view |> form("#flat-booking-form", flat_booking: %{hours: "40"}) |> render_submit()

    assert render(view) =~ "Flat hours booked."
    assert [%{minutes: 2400, project_id: nil}] = TimeTracking.list_flat_bookings(ctx.user.id)
    assert TimeTracking.list_flat_bookings(admin.id) == []
  end

  test "the invoice form bills flat hours with the time of their project", ctx do
    admin = admin_fixture()
    conn = Plug.Test.init_test_session(build_conn(), user_id: admin.id)
    template_fixture()
    entry = entry_fixture(ctx.user, "2026-10-02 08:00:00", "2026-10-02 09:30:00", ctx.project)
    booking = flat_booking_fixture(ctx.user, "2026-10-01", "120", ctx.project, "laut Kunde")

    {:ok, view, _html} = live(conn, ~p"/admin/invoices/new")
    assert has_element?(view, "#invoice-month option[value='2026-10']", "121:30 h unbilled")

    view |> form("#invoice-form", invoice: %{month: "2026-10"}) |> render_change()
    assert has_element?(view, "#booking-row-#{booking.id}", "laut Kunde")
    assert has_element?(view, "#booking-row-#{booking.id}", "120:00 h")
    assert has_element?(view, "#group-#{ctx.project.id}", ~r/0\s+of\s+2\s+selected/)

    view |> element("#toggle-group-#{ctx.project.id}") |> render_click()
    assert has_element?(view, "#group-#{ctx.project.id}", ~r/2\s+of\s+2\s+selected/)
    assert has_element?(view, "#group-#{ctx.project.id}", "121:30 h")

    html = view |> form("#invoice-form", invoice: %{hourly_rate: "80"}) |> render_change()
    assert html =~ "9.720,00 €"

    {:ok, show, _html} =
      view
      |> form("#invoice-form", invoice: %{recipient: "Kunde GmbH\nWeg 2\n10115 Berlin"})
      |> render_submit()
      |> follow_redirect(conn)

    [invoice] = Invoicing.list_invoices()
    assert Invoicing.booking_ids(invoice) == [booking.id]
    assert Invoicing.entry_ids(invoice) == [entry.id]
    assert has_element?(show, "#invoice-letter", "Pauschal gebucht: laut Kunde")

    # Editing the draft keeps the flat hours selected; deselected, they are
    # billable again.
    {:ok, edit, _html} = live(conn, ~p"/admin/invoices/#{invoice}/edit")
    assert has_element?(edit, "#booking-#{booking.id}[checked]")

    # The browser sends the selected entries and flat hours with the form.
    assert {:error, {:live_redirect, _}} =
             render_submit(edit, "save", %{
               "invoice" => %{"entry_ids" => ["", to_string(entry.id)], "booking_ids" => [""]}
             })

    assert Invoicing.booking_ids(invoice) == []
    assert Invoicing.entry_ids(invoice) == [entry.id]
    assert [_booking] = Invoicing.billable_bookings(~D[2026-10-01])
  end
end
