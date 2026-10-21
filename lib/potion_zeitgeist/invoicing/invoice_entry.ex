defmodule PotionZeitgeist.Invoicing.InvoiceEntry do
  @moduledoc """
  A time entry billed on an invoice, with the time sheet row as it is printed:
  date, rounded minutes, the item description of its project, user name and
  notes. `active` turns false when the invoice is cancelled, so the entry can
  be billed again.
  """
  use Ecto.Schema

  schema "invoice_entries" do
    field :active, :boolean, default: true
    field :date, :date
    field :minutes, :integer
    field :description, :string
    field :user_name, PotionZeitgeist.Encrypted.Binary, source: :encrypted_user_name
    field :notes, PotionZeitgeist.Encrypted.Binary, source: :encrypted_notes

    belongs_to :invoice, PotionZeitgeist.Invoicing.Invoice
    belongs_to :time_entry, PotionZeitgeist.TimeTracking.TimeEntry

    timestamps()
  end
end
