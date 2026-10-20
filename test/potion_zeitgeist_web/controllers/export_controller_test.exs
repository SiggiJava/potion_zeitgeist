defmodule PotionZeitgeistWeb.ExportControllerTest do
  use PotionZeitgeistWeb.ConnCase, async: true

  import PotionZeitgeist.Fixtures

  setup %{conn: conn} do
    admin = admin_fixture()
    user = user_fixture(%{"name" => "Anna"})
    project = project_fixture(%{"name" => "Website"})

    entry_fixture(user, "2026-10-19 08:00:00", "2026-10-19 12:00:00", project)
    entry_fixture(user, "2026-10-19 13:00:00", "2026-10-19 14:30:00")
    entry_fixture(user, "2026-10-19 15:00:00", "2026-10-19 16:00:00", project)

    %{conn: conn, admin: admin, user: user}
  end

  defp log_in(conn, user), do: Plug.Test.init_test_session(conn, user_id: user.id)

  test "my export holds one total per day, split by project", %{conn: conn, user: user} do
    conn = conn |> log_in(user) |> get(~p"/export/my-entries")

    assert response_content_type(conn, :csv)

    assert response(conn, 200) ==
             """
             Date,User,Entries,Total,Website,No project
             2026-10-19,Anna,3,06:30:00,05:00:00,01:30:00
             """
  end

  test "my export with type=entries lists every entry", %{conn: conn, user: user} do
    csv = conn |> log_in(user) |> get(~p"/export/my-entries?type=entries") |> response(200)

    assert csv =~ "Date,User,Clock In,Clock Out,Duration,Project,Notes\n"
    assert length(String.split(csv, "\n", trim: true)) == 4
  end

  test "admins can export the daily totals of all users", %{conn: conn, admin: admin} do
    csv = conn |> log_in(admin) |> get(~p"/export/all") |> response(200)
    assert csv =~ "2026-10-19,Anna,3,06:30:00,05:00:00,01:30:00\n"
  end

  test "regular users cannot export all users", %{conn: conn, user: user} do
    conn = conn |> log_in(user) |> get(~p"/export/all")
    assert redirected_to(conn) == ~p"/"
  end
end
