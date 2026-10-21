defmodule PotionZeitgeistWeb.DashboardLiveTest do
  use PotionZeitgeistWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PotionZeitgeist.Fixtures

  alias PotionZeitgeist.TimeTracking

  setup %{conn: conn} do
    admin_fixture()
    user = user_fixture()
    alpha = project_fixture(%{"name" => "Alpha"})
    beta = project_fixture(%{"name" => "Beta"})

    one_hour_ago =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.add(-3600)
      |> NaiveDateTime.truncate(:second)
      |> NaiveDateTime.to_iso8601()

    running = entry_fixture(user, one_hour_ago, nil, alpha)
    conn = Plug.Test.init_test_session(conn, user_id: user.id)

    %{conn: conn, user: user, alpha: alpha, beta: beta, running: running}
  end

  defp pick_project(view, project) do
    view |> form("#active-project-form", %{project_id: project.id}) |> render_change()
  end

  test "picking another project asks whether to rebook or switch", %{conn: conn, beta: beta} do
    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "#project-change-modal")

    pick_project(view, beta)

    assert has_element?(view, "#project-change-modal")
    assert has_element?(view, "#rebook-project")
    assert has_element?(view, "#switch-project")
  end

  test "rebook moves the whole running entry to the new project", %{
    conn: conn,
    user: user,
    beta: beta,
    running: running
  } do
    {:ok, view, _html} = live(conn, ~p"/")
    pick_project(view, beta)
    view |> element("#rebook-project") |> render_click()

    assert [entry] = TimeTracking.list_entries(user.id)
    assert entry.id == running.id
    assert entry.project_id == beta.id
    assert entry.clock_out == nil
    refute has_element?(view, "#project-change-modal")
  end

  test "switch clocks out on the old project and clocks in on the new one", %{
    conn: conn,
    user: user,
    alpha: alpha,
    beta: beta,
    running: running
  } do
    {:ok, view, _html} = live(conn, ~p"/")
    pick_project(view, beta)
    view |> element("#switch-project") |> render_click()

    assert [current, previous] = TimeTracking.list_entries(user.id)

    assert previous.id == running.id
    assert previous.project_id == alpha.id
    assert previous.clock_out

    assert current.project_id == beta.id
    assert current.clock_out == nil
    assert current.clock_in == previous.clock_out
    refute has_element?(view, "#project-change-modal")
  end

  test "cancel keeps the entry unchanged", %{conn: conn, user: user, alpha: alpha, beta: beta} do
    {:ok, view, _html} = live(conn, ~p"/")
    pick_project(view, beta)
    view |> element("#cancel-project-change") |> render_click()

    assert [entry] = TimeTracking.list_entries(user.id)
    assert entry.project_id == alpha.id
    refute has_element?(view, "#project-change-modal")
  end
end
