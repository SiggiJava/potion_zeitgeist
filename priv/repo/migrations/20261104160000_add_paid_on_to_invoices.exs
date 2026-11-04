defmodule PotionZeitgeist.Repo.Migrations.AddPaidOnToInvoices do
  use Ecto.Migration

  # The day the payment of an issued invoice came in. The annual report
  # counts invoices in the year they were paid, as the EÜR does (§ 11 EStG).
  # Drafts are not sent yet, so they cannot be paid. A cancelled invoice
  # keeps the date it had.
  def change do
    alter table(:invoices) do
      add :paid_on, :date
    end

    create constraint(:invoices, :invoices_paid_only_when_sent,
             check: "paid_on IS NULL OR status <> 'draft'"
           )
  end
end
