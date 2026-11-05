defmodule PotionZeitgeistWeb.TimeEntriesLiveTest do
  use PotionZeitgeistWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PotionZeitgeist.Fixtures

  alias PotionZeitgeist.Repo

  setup %{conn: conn} do
    admin = admin_fixture()
    user = user_fixture()
    # Clocked in at 21:17 on a November evening in Berlin (UTC+1).
    entry = entry_fixture(user, "2026-11-05 20:17:00", "2026-11-05 22:00:00")

    %{conn: conn, admin: admin, user: user, entry: entry}
  end

  defp log_in(conn, user), do: Plug.Test.init_test_session(conn, user_id: user.id)

  test "entries show local time", %{conn: conn, user: user} do
    {:ok, view, html} = conn |> log_in(user) |> live(~p"/entries")

    assert html =~ "21:17:00"
    assert html =~ "23:00:00"
    refute html =~ "20:17:00"
    assert has_element?(view, "#time-zone-note", "Europe/Berlin")
  end

  test "the edit form shows and reads local time", %{conn: conn, user: user, entry: entry} do
    {:ok, view, _html} = conn |> log_in(user) |> live(~p"/entries")
    view |> element("button[phx-click=edit][phx-value-id='#{entry.id}']") |> render_click()

    assert has_element?(view, "#edit-entry-clock-in[value='2026-11-05T21:17']")
    assert has_element?(view, "#edit-entry-clock-out[value='2026-11-05T23:00']")

    view
    |> form("#edit-entry-form",
      time_entry: %{clock_in: "2026-11-05T21:17", clock_out: "2026-11-05T23:30"}
    )
    |> render_submit()

    assert Repo.reload(entry).clock_in == ~N[2026-11-05 20:17:00]
    assert Repo.reload(entry).clock_out == ~N[2026-11-05 22:30:00]
    assert render(view) =~ "23:30:00"
  end

  test "a time that does not exist is refused and stays in the form", %{
    conn: conn,
    user: user,
    entry: entry
  } do
    {:ok, view, _html} = conn |> log_in(user) |> live(~p"/entries")
    view |> element("button[phx-click=edit][phx-value-id='#{entry.id}']") |> render_click()

    html =
      view
      |> form("#edit-entry-form",
        time_entry: %{clock_in: "2026-03-29T02:30", clock_out: "2026-03-29T04:00"}
      )
      |> render_submit()

    assert html =~ "does not exist"
    assert has_element?(view, "#edit-entry-clock-in[value='2026-03-29T02:30']")
    assert Repo.reload(entry).clock_in == ~N[2026-11-05 20:17:00]
  end

  test "administrators edit the entries of a user in local time", %{
    conn: conn,
    admin: admin,
    user: user,
    entry: entry
  } do
    {:ok, view, html} = conn |> log_in(admin) |> live(~p"/admin/users/#{user.id}/entries")
    assert html =~ "21:17:00"
    assert has_element?(view, "#time-zone-note", "Europe/Berlin")

    view |> element("button[phx-click=edit][phx-value-id='#{entry.id}']") |> render_click()
    assert has_element?(view, "#edit-entry-clock-in[value='2026-11-05T21:17']")

    view
    |> form("#edit-entry-form",
      time_entry: %{clock_in: "2026-11-05T20:45", clock_out: "2026-11-05T23:00"}
    )
    |> render_submit()

    assert Repo.reload(entry).clock_in == ~N[2026-11-05 19:45:00]
    assert Repo.reload(entry).clock_out == ~N[2026-11-05 22:00:00]
  end
end
