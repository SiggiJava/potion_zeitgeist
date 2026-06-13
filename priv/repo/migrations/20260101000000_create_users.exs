defmodule PotionZeitgeist.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email_hash, :binary, null: false
      add :encrypted_email, :binary, null: false
      add :encrypted_name, :binary, null: false
      add :password_hash, :string, null: false
      add :role, :string, null: false, default: "user"
      add :active, :boolean, null: false, default: true

      timestamps()
    end

    create unique_index(:users, [:email_hash])
    create index(:users, [:role])
  end
end
