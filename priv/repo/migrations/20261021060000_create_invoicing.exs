defmodule PotionZeitgeist.Repo.Migrations.CreateInvoicing do
  use Ecto.Migration

  def change do
    create table(:invoice_templates) do
      add :name, :string, null: false
      add :sender, :text, null: false
      add :tax_id, :string, null: false
      add :subject, :string, null: false, default: ""
      add :body, :text, null: false
      add :footer, :text, null: false, default: ""

      timestamps()
    end

    create unique_index(:invoice_templates, [:name])

    create table(:invoices) do
      # Assigned when the invoice is issued; drafts have no number yet.
      add :number, :string
      add :status, :string, null: false, default: "draft"
      add :invoice_date, :date, null: false
      add :due_date, :date
      add :period_start, :date, null: false
      add :period_end, :date, null: false
      add :recipient, :text, null: false
      add :template_id, references(:invoice_templates, on_delete: :nilify_all)
      add :rate_mode, :string, null: false, default: "single"
      add :hourly_rate, :decimal, precision: 10, scale: 2
      add :tax_mode, :string, null: false, default: "small_business"
      add :vat_rate, :decimal, precision: 5, scale: 2, null: false, default: 0
      add :net_total, :decimal, precision: 12, scale: 2, null: false, default: 0
      add :vat_total, :decimal, precision: 12, scale: 2, null: false, default: 0
      add :gross_total, :decimal, precision: 12, scale: 2, null: false, default: 0
      add :show_timesheet, :boolean, null: false, default: true

      # The letter as it was issued, so later template edits never change it.
      add :letter_sender, :text
      add :letter_tax_id, :string
      add :letter_subject, :string
      add :letter_body, :text
      add :letter_footer, :text

      add :issued_at, :utc_datetime
      add :cancelled_at, :utc_datetime

      timestamps()
    end

    create unique_index(:invoices, [:number])
    create index(:invoices, [:status])

    create constraint(:invoices, :invoices_status_valid,
             check: "status IN ('draft', 'issued', 'cancelled')"
           )

    create constraint(:invoices, :invoices_number_iff_issued,
             check: "(status = 'draft') = (number IS NULL)"
           )

    create constraint(:invoices, :invoices_tax_valid,
             check:
               "(tax_mode = 'small_business' AND vat_rate = 0) OR " <>
                 "(tax_mode = 'standard' AND vat_rate > 0 AND vat_rate < 100)"
           )

    create table(:invoice_items) do
      add :invoice_id, references(:invoices, on_delete: :delete_all), null: false
      add :position, :integer, null: false
      add :project_id, references(:projects, on_delete: :nilify_all)
      add :description, :text, null: false
      add :minutes, :integer, null: false
      add :hours, :decimal, precision: 10, scale: 2, null: false
      add :hourly_rate, :decimal, precision: 10, scale: 2, null: false
      add :amount, :decimal, precision: 12, scale: 2, null: false

      timestamps()
    end

    create index(:invoice_items, [:invoice_id])
    create index(:invoice_items, [:project_id])

    # One row per billed time entry. It keeps what the time sheet prints, so
    # the invoice stays the same when the entry or its user is deleted later.
    create table(:invoice_entries) do
      add :invoice_id, references(:invoices, on_delete: :delete_all), null: false
      add :time_entry_id, references(:time_entries, on_delete: :nilify_all)
      # False once the invoice is cancelled, which frees the entry for a new invoice.
      add :active, :boolean, null: false, default: true
      add :date, :date, null: false
      add :minutes, :integer, null: false
      add :description, :text, null: false
      add :encrypted_user_name, :binary
      add :encrypted_notes, :binary

      timestamps()
    end

    create index(:invoice_entries, [:invoice_id])

    # A time entry can be on at most one draft or issued invoice.
    create unique_index(:invoice_entries, [:time_entry_id],
             where: "active",
             name: :invoice_entries_active_time_entry_index
           )
  end
end
