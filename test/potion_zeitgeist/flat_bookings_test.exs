defmodule PotionZeitgeist.FlatBookingsTest do
  use PotionZeitgeist.DataCase, async: true

  import PotionZeitgeist.Fixtures

  alias PotionZeitgeist.{Accounts, Invoicing, Projects, TimeTracking}
  alias PotionZeitgeist.Invoicing.InvoiceItem

  setup do
    user = user_fixture(%{"name" => "Michael"})
    website = project_fixture(%{"name" => "Website"})
    %{user: user, website: website, template: template_fixture()}
  end

  describe "booking" do
    test "takes a month, hours, a project and notes", ctx do
      assert {:ok, booking} =
               TimeTracking.create_flat_booking(ctx.user.id, %{
                 "month" => "2026-10-15",
                 "hours" => "120,5",
                 "project_id" => to_string(ctx.website.id),
                 "notes" => "laut Zeiterfassung des Kunden"
               })

      assert booking.month == ~D[2026-10-01]
      assert booking.minutes == 7230

      assert [%{invoiced: false, project: %{name: "Website"}} = listed] =
               TimeTracking.list_flat_bookings(ctx.user.id)

      assert listed.id == booking.id
      assert listed.notes == "laut Zeiterfassung des Kunden"
      assert TimeTracking.list_flat_bookings(user_fixture().id) == []

      # The form shows the hours as they were booked.
      assert booking |> TimeTracking.change_flat_booking() |> Ecto.Changeset.get_field(:hours) ==
               "120,5"

      assert {:ok, booking} = TimeTracking.update_flat_booking(booking, %{"hours" => "7:45"})
      assert booking.minutes == 465

      # Other fields leave the hours as they are, and the user stays.
      other = user_fixture()

      assert {:ok, booking} =
               TimeTracking.update_flat_booking(booking, %{
                 "month" => "2026-09-01",
                 "user_id" => to_string(other.id)
               })

      assert booking.minutes == 465
      assert booking.month == ~D[2026-09-01]
      assert booking.user_id == ctx.user.id

      assert {:ok, _deleted} = TimeTracking.delete_flat_booking(booking)
      assert TimeTracking.list_flat_bookings(ctx.user.id) == []
      assert {:error, :not_found} = TimeTracking.delete_flat_booking(booking)
      assert {:error, :not_found} = TimeTracking.update_flat_booking(booking, %{"hours" => "1"})
    end

    test "need a month and hours the invoice bills as typed", ctx do
      assert {:error, changeset} =
               TimeTracking.create_flat_booking(ctx.user.id, %{"month" => "", "hours" => ""})

      assert %{month: ["pick a month"], hours: ["enter the hours, such as 120 or 120:30"]} =
               errors_on(changeset)

      for {hours, message} <- [
            {"0", "must be above 0 and at most 744 hours"},
            {"745", "must be above 0 and at most 744 hours"},
            {"8,34", "cannot be billed in whole minutes, enter 8,33 (8:20) or 8,35 (8:21)"},
            {"zwölf", "enter the hours, such as 120, 120,5 or 120:30"}
          ] do
        assert {:error, changeset} =
                 TimeTracking.create_flat_booking(ctx.user.id, %{
                   "month" => "2026-10-01",
                   "hours" => hours
                 })

        assert %{hours: [^message]} = errors_on(changeset)
      end

      # Clearing the hours of booked flat hours is an error, not left out.
      booking = flat_booking_fixture(ctx.user, "2026-10-01", "120")
      assert {:error, changeset} = TimeTracking.update_flat_booking(booking, %{"hours" => ""})
      assert %{hours: ["enter the hours, such as 120 or 120:30"]} = errors_on(changeset)
    end

    test "go to active projects, and keep a project archived since", ctx do
      booking = flat_booking_fixture(ctx.user, "2026-10-01", "10", ctx.website)
      {:ok, archived} = Projects.update_project(ctx.website, %{active: false})

      assert {:error, changeset} =
               TimeTracking.create_flat_booking(ctx.user.id, %{
                 "month" => "2026-10-01",
                 "hours" => "10",
                 "project_id" => to_string(archived.id)
               })

      assert %{project_id: ["is not an active project"]} = errors_on(changeset)

      assert {:ok, %{project_id: project_id}} =
               TimeTracking.update_flat_booking(booking, %{"hours" => "12"})

      assert project_id == archived.id
    end

    test "keep their project from being deleted", ctx do
      flat_booking_fixture(ctx.user, "2026-10-01", "10", ctx.website)
      assert {:error, :has_entries} = Projects.delete_project(ctx.website)
    end
  end

  describe "on invoices" do
    test "bill with the time entries of their project and month", ctx do
      entry = entry_fixture(ctx.user, "2026-10-01 08:00:00", "2026-10-01 09:30:00", ctx.website)

      flat =
        flat_booking_fixture(
          ctx.user,
          "2026-10-01",
          "120",
          ctx.website,
          "laut Zeiterfassung des Kunden"
        )

      no_project = flat_booking_fixture(ctx.user, "2026-10-01", "2,5")
      flat_booking_fixture(ctx.user, "2026-09-01", "8")

      assert ids(Invoicing.billable_bookings(~D[2026-10-20])) == [flat.id, no_project.id]

      choices = Invoicing.month_choices(~D[2026-11-05])
      assert {~D[2026-10-01], 90 + 7200 + 150} in choices
      assert {~D[2026-09-01], 480} in choices

      draft =
        draft_fixture(ctx.template, [entry], %{
          "booking_ids" => [to_string(flat.id), to_string(no_project.id)]
        })

      # One item per project, with the hours of entries and flat hours.
      assert [
               %{description: "Website", minutes: 7290} = website,
               %{description: "Dienstleistungen", minutes: 150} = none
             ] = draft.items

      assert InvoiceItem.time?(website)
      assert Decimal.equal?(website.hours, Decimal.new("121.50"))
      assert Decimal.equal?(website.amount, Decimal.new("9720.00"))
      assert Decimal.equal?(none.hours, Decimal.new("2.50"))
      assert Decimal.equal?(draft.gross_total, Decimal.new("9920.00"))

      assert Enum.sort(Invoicing.booking_ids(draft)) == Enum.sort([flat.id, no_project.id])
      assert Invoicing.entry_ids(draft) == [entry.id]
      assert Invoicing.billable_bookings(~D[2026-10-01]) == []
      assert {~D[2026-10-01], 0} in Invoicing.month_choices(~D[2026-11-05])
      # The draft being edited still sees its own flat hours.
      assert ids(Invoicing.billable_bookings(~D[2026-10-01], draft)) == [flat.id, no_project.id]

      params = Invoicing.edit_invoice_params(draft)

      assert Enum.sort(params["booking_ids"]) ==
               Enum.sort([to_string(flat.id), to_string(no_project.id)])

      assert {:ok, again} = Invoicing.update_draft(draft, params)
      assert Enum.map(again.items, & &1.minutes) == [7290, 150]

      # The time sheet shows flat hours as rows of their own, before the
      # days of their month, also next to an entry of the first day.
      sheet = Invoicing.letter(again).timesheet

      assert [
               %{
                 date: "Okt. 2026",
                 project: "Dienstleistungen",
                 duration: "2:30",
                 notes: "Pauschal gebucht"
               },
               %{
                 date: "Okt. 2026",
                 project: "Website",
                 duration: "120:00",
                 notes: "Pauschal gebucht: laut Zeiterfassung des Kunden"
               },
               %{date: "01.10.2026", project: "Website", duration: "1:30"}
             ] = sheet.rows

      assert sheet.total == "124:00"
    end

    test "need an hourly rate and can be billed only once", ctx do
      flat = flat_booking_fixture(ctx.user, "2026-10-01", "120", ctx.website)
      booking_ids = [to_string(flat.id)]

      assert {:error, changeset} =
               Invoicing.create_draft(
                 draft_params(ctx.template, [], %{
                   "hourly_rate" => "",
                   "booking_ids" => booking_ids
                 })
               )

      assert errors_on(changeset).hourly_rate == ["is needed for one rate for all"]

      draft = draft_fixture(ctx.template, [], %{"booking_ids" => booking_ids})
      assert [%{minutes: 7200}] = draft.items

      assert {:error, changeset} =
               Invoicing.create_draft(
                 draft_params(ctx.template, [], %{"booking_ids" => booking_ids})
               )

      assert %{entries: [message]} = errors_on(changeset)
      assert message =~ "no longer available"

      assert :ok = Invoicing.delete_draft(draft)
      assert ids(Invoicing.billable_bookings(~D[2026-10-01])) == [flat.id]
    end

    test "moved to another month are no longer billed in this one", ctx do
      flat = flat_booking_fixture(ctx.user, "2026-10-01", "10")
      {:ok, _moved} = TimeTracking.update_flat_booking(flat, %{"month" => "2026-09-01"})

      assert {:error, changeset} =
               Invoicing.create_draft(
                 draft_params(ctx.template, [], %{"booking_ids" => [to_string(flat.id)]})
               )

      assert %{entries: [message]} = errors_on(changeset)
      assert message =~ "no longer available"
    end

    test "are locked until the invoice is cancelled, and its time sheet keeps them", ctx do
      flat = flat_booking_fixture(ctx.user, "2026-10-01", "120", ctx.website)
      draft = draft_fixture(ctx.template, [], %{"booking_ids" => [to_string(flat.id)]})

      assert {:error, :invoiced} = TimeTracking.update_flat_booking(flat, %{"hours" => "100"})
      assert {:error, :invoiced} = TimeTracking.delete_flat_booking(flat)
      assert [%{invoiced: true}] = TimeTracking.list_flat_bookings(ctx.user.id)

      {:ok, issued} =
        Invoicing.issue_invoice(draft, %{"number" => "2026-001", "invoice_date" => "2026-11-02"})

      assert {:error, :invoiced} = TimeTracking.delete_flat_booking(flat)

      {:ok, cancelled} = Invoicing.cancel_invoice(issued)
      assert ids(Invoicing.billable_bookings(~D[2026-10-01])) == [flat.id]
      assert [%{invoiced: false}] = TimeTracking.list_flat_bookings(ctx.user.id)
      # A corrected invoice bills them again.
      assert Invoicing.booking_ids(cancelled) == [flat.id]

      assert {:ok, %{minutes: 6000}} = TimeTracking.update_flat_booking(flat, %{"hours" => "100"})
      assert {:ok, _deleted} = TimeTracking.delete_flat_booking(flat)

      assert [%{date: "Okt. 2026", duration: "120:00", notes: "Pauschal gebucht"}] =
               Invoicing.letter(Invoicing.get_invoice!(cancelled.id)).timesheet.rows
    end

    test "the time sheet survives deleting the user", ctx do
      flat = flat_booking_fixture(ctx.user, "2026-10-01", "120", ctx.website)
      draft = draft_fixture(ctx.template, [], %{"booking_ids" => [to_string(flat.id)]})

      {:ok, invoice} =
        Invoicing.issue_invoice(draft, %{"number" => "1", "invoice_date" => "2026-11-02"})

      {:ok, _} = Accounts.delete_user(ctx.user)

      assert [%{date: "Okt. 2026", duration: "120:00", project: "Website"}] =
               Invoicing.letter(Invoicing.get_invoice!(invoice.id)).timesheet.rows
    end
  end

  defp ids(records), do: Enum.map(records, & &1.id)
end
