defmodule PotionZeitgeistWeb.ExportController do
  use PotionZeitgeistWeb, :controller

  alias PotionZeitgeist.{Accounts, TimeTracking}

  def my_entries(conn, _params) do
    user = conn.assigns.current_user
    entries = TimeTracking.list_entries(user.id)
    csv = TimeTracking.generate_csv(entries)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header(
      "content-disposition",
      "attachment; filename=\"entries_#{Date.utc_today()}.csv\""
    )
    |> send_resp(200, csv)
  end

  def user_entries(conn, %{"id" => user_id}) do
    user = Accounts.get_user!(user_id)
    entries = TimeTracking.list_entries(user.id)
    csv = TimeTracking.generate_csv(entries)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header(
      "content-disposition",
      "attachment; filename=\"entries_user_#{user_id}_#{Date.utc_today()}.csv\""
    )
    |> send_resp(200, csv)
  end
end
