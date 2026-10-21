defmodule PotionZeitgeist.ProjectsTest do
  use PotionZeitgeist.DataCase, async: true

  import PotionZeitgeist.Fixtures

  alias PotionZeitgeist.{Projects, TimeTracking}

  test "project names are unique" do
    project_fixture(%{"name" => "Website"})
    assert {:error, changeset} = Projects.create_project(%{"name" => "Website"})
    assert %{name: ["already exists"]} = errors_on(changeset)
  end

  test "blank names are rejected when updating a project" do
    project = project_fixture()
    assert {:error, changeset} = Projects.update_project(project, %{"name" => "  "})
    assert %{name: ["can't be blank"]} = errors_on(changeset)
  end

  test "users can clock in with or without an active project" do
    user = user_fixture()
    project = project_fixture()

    assert {:ok, entry} = TimeTracking.clock_in(user.id, project.id)
    assert entry.project_id == project.id

    other = user_fixture()
    assert {:ok, entry} = TimeTracking.clock_in(other.id)
    assert entry.project_id == nil
  end

  test "archived projects cannot get new bookings but keep existing ones" do
    user = user_fixture()
    project = project_fixture()
    entry = entry_fixture(user, "2026-10-19 08:00:00", "2026-10-19 12:00:00", project)
    {:ok, project} = Projects.update_project(project, %{active: false})

    assert {:error, changeset} = TimeTracking.clock_in(user.id, project.id)
    assert %{project_id: ["is not an active project"]} = errors_on(changeset)

    assert {:ok, _} = TimeTracking.update_entry(entry, %{"notes" => "kept"})
    assert [%{id: id}] = Projects.list_bookable_projects(project.id)
    assert id == project.id
  end

  test "projects with booked time cannot be deleted" do
    user = user_fixture()
    project = project_fixture()
    entry_fixture(user, "2026-10-19 08:00:00", "2026-10-19 12:00:00", project)

    assert {:error, :has_entries} = Projects.delete_project(project)
    assert {:ok, _} = Projects.delete_project(project_fixture())
  end
end
