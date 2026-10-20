defmodule PotionZeitgeist.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects) do
      add :name, :string, null: false
      add :description, :text
      add :active, :boolean, null: false, default: true

      timestamps()
    end

    create unique_index(:projects, [:name])

    alter table(:time_entries) do
      add :project_id, references(:projects, on_delete: :nilify_all)
    end

    create index(:time_entries, [:project_id])
  end
end
