defmodule PotionZeitgeist.Invoicing.InvoiceItem do
  use Ecto.Schema

  schema "invoice_items" do
    field :position, :integer
    field :description, :string
    field :minutes, :integer
    field :hours, :decimal
    field :hourly_rate, :decimal
    field :amount, :decimal

    belongs_to :invoice, PotionZeitgeist.Invoicing.Invoice
    belongs_to :project, PotionZeitgeist.Projects.Project

    timestamps()
  end
end
