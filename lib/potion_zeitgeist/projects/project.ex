defmodule PotionZeitgeist.Projects.Project do
  use Ecto.Schema
  import Ecto.Changeset

  schema "projects" do
    field :name, :string
    field :description, :string
    field :active, :boolean, default: true

    has_many :time_entries, PotionZeitgeist.TimeTracking.TimeEntry

    timestamps()
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :description, :active])
    |> update_change(:name, &(&1 && String.trim(&1)))
    |> validate_required([:name])
    |> validate_length(:name, max: 120)
    |> unique_constraint(:name, message: "already exists")
  end
end
