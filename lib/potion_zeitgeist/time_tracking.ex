defmodule PotionZeitgeist.TimeTracking do
  import Ecto.Query

  alias PotionZeitgeist.Repo
  alias PotionZeitgeist.TimeTracking.TimeEntry

  def get_active_entry(user_id) do
    Repo.one(
      from e in TimeEntry,
        where: e.user_id == ^user_id and is_nil(e.clock_out),
        order_by: [desc: e.clock_in],
        limit: 1
    )
  end

  def list_entries(user_id) do
    Repo.all(
      from e in TimeEntry,
        where: e.user_id == ^user_id,
        order_by: [desc: e.clock_in]
    )
  end

  def list_entries_for_date(user_id, date) do
    start_of_day = NaiveDateTime.new!(date, ~T[00:00:00])
    end_of_day = NaiveDateTime.new!(date, ~T[23:59:59])

    Repo.all(
      from e in TimeEntry,
        where:
          e.user_id == ^user_id and
            e.clock_in >= ^start_of_day and
            e.clock_in <= ^end_of_day,
        order_by: [asc: e.clock_in]
    )
  end

  def get_entry!(id), do: Repo.get!(TimeEntry, id)

  def get_entry!(id, user_id) do
    Repo.get_by!(TimeEntry, id: id, user_id: user_id)
  end

  def clock_in(user_id) do
    case get_active_entry(user_id) do
      nil ->
        %TimeEntry{}
        |> TimeEntry.changeset(%{
          user_id: user_id,
          clock_in: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        })
        |> Repo.insert()

      _existing ->
        {:error, :already_clocked_in}
    end
  end

  def clock_out(%TimeEntry{} = entry) do
    entry
    |> TimeEntry.clock_out_changeset(%{
      clock_out: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    })
    |> Repo.update()
  end

  def update_entry(%TimeEntry{} = entry, attrs) do
    entry
    |> TimeEntry.edit_changeset(attrs)
    |> Repo.update()
  end

  def delete_entry(%TimeEntry{} = entry) do
    Repo.delete(entry)
  end

  def change_entry(%TimeEntry{} = entry, attrs \\ %{}) do
    TimeEntry.edit_changeset(entry, attrs)
  end

  def today_total_seconds(user_id) do
    today = Date.utc_today()
    entries = list_entries_for_date(user_id, today)
    now = NaiveDateTime.utc_now()

    Enum.reduce(entries, 0, fn entry, acc ->
      finish = entry.clock_out || now
      diff = NaiveDateTime.diff(finish, entry.clock_in, :second)
      acc + max(diff, 0)
    end)
  end

  def format_duration(total_seconds) do
    hours = div(total_seconds, 3600)
    minutes = div(rem(total_seconds, 3600), 60)
    seconds = rem(total_seconds, 60)
    :io_lib.format("~2..0B:~2..0B:~2..0B", [hours, minutes, seconds]) |> to_string()
  end

  def generate_csv(entries) do
    header = "Date,Clock In,Clock Out,Duration,Notes\n"

    rows =
      Enum.map(entries, fn entry ->
        date = NaiveDateTime.to_date(entry.clock_in) |> Date.to_string()
        clock_in = format_naive_dt(entry.clock_in)
        clock_out = if entry.clock_out, do: format_naive_dt(entry.clock_out), else: ""

        duration =
          if entry.clock_out do
            diff = NaiveDateTime.diff(entry.clock_out, entry.clock_in, :second)
            format_duration(diff)
          else
            "In progress"
          end

        notes = csv_escape(entry.notes || "")

        "#{date},#{clock_in},#{clock_out},#{duration},#{notes}\n"
      end)

    header <> Enum.join(rows)
  end

  defp format_naive_dt(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end

  defp csv_escape(value) do
    str = to_string(value)

    if String.contains?(str, [",", "\"", "\n"]) do
      "\"#{String.replace(str, "\"", "\"\"")}\""
    else
      str
    end
  end
end
