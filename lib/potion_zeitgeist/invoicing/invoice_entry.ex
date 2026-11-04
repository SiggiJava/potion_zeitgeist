defmodule PotionZeitgeist.Invoicing.InvoiceEntry do
  @moduledoc """
  A time entry or flat hours (see `PotionZeitgeist.TimeTracking.FlatBooking`)
  billed on an invoice, with the time sheet row as it is printed: date
  (for flat hours the first day of their month), rounded minutes, the item
  description of its project, user name and notes. `flat` tells rows of flat
  hours apart, also once the flat hours are deleted. `active` turns false
  when the invoice is cancelled, so the entry or flat hours can be billed
  again.
  """
  use Ecto.Schema

  schema "invoice_entries" do
    field :active, :boolean, default: true
    field :flat, :boolean, default: false
    field :date, :date
    field :minutes, :integer
    field :description, :string
    field :user_name, PotionZeitgeist.Encrypted.Binary, source: :encrypted_user_name
    field :notes, PotionZeitgeist.Encrypted.Binary, source: :encrypted_notes

    belongs_to :invoice, PotionZeitgeist.Invoicing.Invoice
    belongs_to :time_entry, PotionZeitgeist.TimeTracking.TimeEntry
    belongs_to :flat_booking, PotionZeitgeist.TimeTracking.FlatBooking

    timestamps()
  end
end
