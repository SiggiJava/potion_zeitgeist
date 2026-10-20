defmodule PotionZeitgeist.Projects do
  import Ecto.Query

  alias PotionZeitgeist.Repo
  alias PotionZeitgeist.Projects.Project

  def list_projects do
    Repo.all(from p in Project, order_by: [asc: p.name])
  end

  def list_active_projects do
    Repo.all(from p in Project, where: p.active == true, order_by: [asc: p.name])
  end

  @doc """
  Projects a time entry can be booked to: all active projects, plus the
  project the entry already has, even if it was archived since.
  """
  def list_bookable_projects(current_project_id \\ nil)

  def list_bookable_projects(nil), do: list_active_projects()

  def list_bookable_projects(current_project_id) do
    Repo.all(
      from p in Project,
        where: p.active == true or p.id == ^current_project_id,
        order_by: [asc: p.name]
    )
  end

  def get_project!(id), do: Repo.get!(Project, id)

  def get_active_project(id) do
    Repo.get_by(Project, id: id, active: true)
  end

  def create_project(attrs) do
    %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
  end

  def update_project(%Project{} = project, attrs) do
    project
    |> Project.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a project that has no booked time. Projects with bookings must be
  archived instead (`active: false`), so recorded working time keeps its project.
  """
  def delete_project(%Project{} = project) do
    project
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.no_assoc_constraint(:time_entries)
    |> Repo.delete()
    |> case do
      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        if Keyword.has_key?(errors, :time_entries),
          do: {:error, :has_entries},
          else: {:error, changeset}

      result ->
        result
    end
  end

  def change_project(%Project{} = project, attrs \\ %{}) do
    Project.changeset(project, attrs)
  end
end
