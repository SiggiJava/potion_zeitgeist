defmodule PotionZeitgeist.Repo.Migrations.CreateFlatBookings do
  use Ecto.Migration

  # Flat hours: the hours of a whole month booked at once, for time recorded
  # elsewhere (such as with a client's time clock), so it is not clocked a
  # second time. They are billed like time entries, but have no clock-in and
  # clock-out and are no working time record.
  def change do
    create table(:flat_bookings) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      # :restrict as for time entries, so booked time never loses its project.
      add :project_id, references(:projects, on_delete: :restrict)
      # The first day of the month the hours are booked for.
      add :month, :date, null: false
      add :minutes, :integer, null: false
      add :encrypted_notes, :binary

      timestamps()
    end

    create index(:flat_bookings, [:user_id, :month])
    create index(:flat_bookings, [:month])
    create index(:flat_bookings, [:project_id])

    create constraint(:flat_bookings, :flat_bookings_month_valid,
             check: "EXTRACT(DAY FROM month) = 1"
           )

    # A month has at most 31 days of 24 hours.
    create constraint(:flat_bookings, :flat_bookings_minutes_valid,
             check: "minutes > 0 AND minutes <= 44640"
           )

    # A row of the time sheet of an invoice comes from a time entry or from
    # flat hours. `flat` stays when the flat hours are deleted later (after
    # the invoice was cancelled), so the time sheet still shows them as such.
    alter table(:invoice_entries) do
      add :flat_booking_id, references(:flat_bookings, on_delete: :nilify_all)
      add :flat, :boolean, null: false, default: false
    end

    # Flat hours can be on at most one draft or issued invoice.
    create unique_index(:invoice_entries, [:flat_booking_id],
             where: "active",
             name: :invoice_entries_active_flat_booking_index
           )

    create constraint(:invoice_entries, :invoice_entries_source_valid,
             check: "(flat AND time_entry_id IS NULL) OR (NOT flat AND flat_booking_id IS NULL)"
           )
  end
end
