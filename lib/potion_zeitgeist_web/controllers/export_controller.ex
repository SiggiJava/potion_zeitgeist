defmodule PotionZeitgeistWeb.ExportController do
  use PotionZeitgeistWeb, :controller

  alias PotionZeitgeist.{Accounts, TimeTracking}

  # `?type=entries` exports every clock-in/clock-out pair. Without it the
  # export holds one total per user and day, split by project.

  def my_entries(conn, params) do
    user = conn.assigns.current_user
    send_export(conn, params, user.id, "entries")
  end

  def user_entries(conn, %{"id" => user_id} = params) do
    user = Accounts.get_user!(user_id)
    send_export(conn, params, user.id, "entries_user_#{user.id}")
  end

  def all_entries(conn, params) do
    send_export(conn, params, :all, "entries_all_users")
  end

  defp send_export(conn, params, user_id, filename_prefix) do
    entries = TimeTracking.list_entries_for_export(user_id)

    {csv, kind} =
      case params["type"] do
        "entries" -> {TimeTracking.generate_entries_csv(entries), "details"}
        _ -> {TimeTracking.generate_daily_csv(entries), "daily"}
      end

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header(
      "content-disposition",
      "attachment; filename=\"#{filename_prefix}_#{kind}_#{Date.utc_today()}.csv\""
    )
    |> send_resp(200, csv)
  end
end
