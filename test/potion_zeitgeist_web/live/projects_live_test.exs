defmodule PotionZeitgeistWeb.Admin.ProjectsLiveTest do
  use PotionZeitgeistWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PotionZeitgeist.Fixtures

  alias PotionZeitgeist.Projects

  test "admins can create projects", %{conn: conn} do
    admin = admin_fixture()
    {:ok, view, _html} = conn |> Plug.Test.init_test_session(user_id: admin.id) |> live(~p"/admin/projects")

    view |> element("#new-project") |> render_click()

    view
    |> form("#project-form", project: %{name: "Website", description: "Relaunch"})
    |> render_submit()

    assert [%{name: "Website", active: true}] = Projects.list_projects()
    assert has_element?(view, "#projects")
  end

  test "regular users cannot open the project admin", %{conn: conn} do
    admin_fixture()
    user = user_fixture()
    conn = conn |> Plug.Test.init_test_session(user_id: user.id) |> get(~p"/admin/projects")
    assert redirected_to(conn) == ~p"/"
  end
end
