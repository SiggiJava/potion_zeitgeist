defmodule PotionZeitgeist.Repo.Migrations.AddManualInvoiceItems do
  use Ecto.Migration

  # Invoice items that are not billed from time entries, such as material or
  # a flat fee: a quantity with an optional unit and a price per unit.
  # Items billed from time entries keep their minutes, hours and hourly rate.
  def up do
    alter table(:invoice_items) do
      add :kind, :string, null: false, default: "time"
      add :quantity, :decimal, precision: 10, scale: 3
      add :unit, :string
      add :unit_price, :decimal, precision: 10, scale: 2

      modify :minutes, :integer, null: true
      modify :hours, :decimal, precision: 10, scale: 2, null: true
      modify :hourly_rate, :decimal, precision: 10, scale: 2, null: true
    end

    create constraint(:invoice_items, :invoice_items_kind_valid,
             check: """
             (kind = 'time'
               AND minutes IS NOT NULL AND hours IS NOT NULL AND hourly_rate IS NOT NULL
               AND quantity IS NULL AND unit IS NULL AND unit_price IS NULL)
             OR
             (kind = 'manual'
               AND project_id IS NULL
               AND minutes IS NULL AND hours IS NULL AND hourly_rate IS NULL
               AND quantity IS NOT NULL AND quantity > 0
               AND unit_price IS NOT NULL AND unit_price >= 0)
             """
           )
  end

  # Going back would drop items of issued invoices, whose totals include
  # them, so it is refused while there are any.
  def down do
    execute """
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM invoice_items WHERE kind <> 'time') THEN
        RAISE EXCEPTION 'invoices have items that are not billed from time entries';
      END IF;
    END
    $$;
    """

    drop constraint(:invoice_items, :invoice_items_kind_valid)

    alter table(:invoice_items) do
      remove :kind
      remove :quantity
      remove :unit
      remove :unit_price

      modify :minutes, :integer, null: false
      modify :hours, :decimal, precision: 10, scale: 2, null: false
      modify :hourly_rate, :decimal, precision: 10, scale: 2, null: false
    end
  end
end
