defmodule PotionZeitgeist.Invoicing.InvoiceItem do
  @moduledoc """
  A line of the table of items on an invoice.

  Kind `"time"`: the time entries of one project, with minutes, hours and
  hourly rate. Kind `"manual"`: an item entered on the invoice form, such as
  material or a flat fee (see `PotionZeitgeist.Invoicing.ManualItem`), with
  a quantity, an optional unit and a price per unit.
  """
  use Ecto.Schema

  schema "invoice_items" do
    field :kind, :string, default: "time"
    field :position, :integer
    field :description, :string
    field :minutes, :integer
    field :hours, :decimal
    field :hourly_rate, :decimal
    field :quantity, :decimal
    field :unit, :string
    field :unit_price, :decimal
    field :amount, :decimal

    belongs_to :invoice, PotionZeitgeist.Invoicing.Invoice
    belongs_to :project, PotionZeitgeist.Projects.Project

    timestamps()
  end

  @doc "Whether `item` bills time entries (as opposed to an item entered on the form)."
  def time?(%{kind: "manual"}), do: false
  def time?(_item), do: true
end
