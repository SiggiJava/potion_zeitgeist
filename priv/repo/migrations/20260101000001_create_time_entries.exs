defmodule PotionZeitgeist.Repo.Migrations.CreateTimeEntries do
  use Ecto.Migration

  def change do
    create table(:time_entries) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :clock_in, :naive_datetime, null: false
      add :clock_out, :naive_datetime
      add :encrypted_notes, :binary

      timestamps()
    end

    create index(:time_entries, [:user_id])
    create index(:time_entries, [:clock_in])
    create index(:time_entries, [:user_id, :clock_in])
  end
end
