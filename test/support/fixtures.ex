defmodule PotionZeitgeist.Fixtures do
  @moduledoc """
  Test helpers for creating users, projects and time entries.
  """

  alias PotionZeitgeist.{Accounts, Projects, Repo}
  alias PotionZeitgeist.TimeTracking.TimeEntry

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        "email" => "user#{System.unique_integer([:positive])}@example.com",
        "name" => "Test User",
        "password" => "password1234",
        "role" => "user"
      })
      |> Accounts.create_user()

    user
  end

  def admin_fixture(attrs \\ %{}) do
    attrs |> Enum.into(%{"role" => "admin", "name" => "Admin"}) |> user_fixture()
  end

  def project_fixture(attrs \\ %{}) do
    {:ok, project} =
      attrs
      |> Enum.into(%{"name" => "Project #{System.unique_integer([:positive])}"})
      |> Projects.create_project()

    project
  end

  def entry_fixture(user, clock_in, clock_out, project \\ nil) do
    Repo.insert!(%TimeEntry{
      user_id: user.id,
      project_id: project && project.id,
      clock_in: NaiveDateTime.from_iso8601!(clock_in),
      clock_out: clock_out && NaiveDateTime.from_iso8601!(clock_out)
    })
  end
end
