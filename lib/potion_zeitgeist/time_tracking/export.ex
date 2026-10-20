defmodule PotionZeitgeist.TimeTracking.Export do
  @moduledoc """
  Builds the CSV exports for time entries.

  Expects entries with `:user` and `:project` preloaded. Entries are assigned to
  the date of their clock-in. Entries that are still running (no clock-out) are
  not part of the daily totals.
  """

  @no_project "No project"

  @doc """
  Sums the completed entries per user and day, across any number of
  clock-in/clock-out pairs, and splits each daily total by project.

  Returns a list of maps sorted by date and user name.
  """
  def daily_totals(entries) do
    entries
    |> Enum.filter(& &1.clock_out)
    |> Enum.group_by(fn entry -> {entry.user_id, NaiveDateTime.to_date(entry.clock_in)} end)
    |> Enum.map(fn {{user_id, date}, day_entries} ->
      by_project =
        Enum.reduce(day_entries, %{}, fn entry, acc ->
          Map.update(acc, entry.project_id, entry_seconds(entry), &(&1 + entry_seconds(entry)))
        end)

      %{
        user_id: user_id,
        user_name: user_name(hd(day_entries)),
        date: date,
        entry_count: length(day_entries),
        total_seconds: by_project |> Map.values() |> Enum.sum(),
        by_project: by_project
      }
    end)
    |> Enum.sort_by(fn day -> {Date.to_iso8601(day.date), to_string(day.user_name), day.user_id} end)
  end

  @doc """
  CSV with one row per user and day holding the daily total.

  When projects exist, one column per project follows, plus a "No project"
  column, so the project columns of a row add up to its daily total. Archived
  projects only get a column when the export contains time booked to them.
  """
  def daily_csv(entries, projects) do
    days = daily_totals(entries)
    columns = project_columns(days, projects)

    header =
      ["Date", "User", "Entries", "Total"] ++
        Enum.map(columns, fn
          nil -> @no_project
          project -> project.name
        end)

    rows =
      Enum.map(days, fn day ->
        [
          Date.to_string(day.date),
          day.user_name,
          day.entry_count,
          format_duration(day.total_seconds)
        ] ++
          Enum.map(columns, fn column ->
            key = if column, do: column.id, else: nil
            day.by_project |> Map.get(key, 0) |> format_duration()
          end)
      end)

    to_csv([header | rows])
  end

  @doc """
  CSV with one row per clock-in/clock-out pair.
  """
  def entries_csv(entries) do
    header = ["Date", "User", "Clock In", "Clock Out", "Duration", "Project", "Notes"]

    rows =
      Enum.map(entries, fn entry ->
        [
          entry.clock_in |> NaiveDateTime.to_date() |> Date.to_string(),
          user_name(entry),
          format_naive_dt(entry.clock_in),
          if(entry.clock_out, do: format_naive_dt(entry.clock_out), else: ""),
          if(entry.clock_out, do: format_duration(entry_seconds(entry)), else: "In progress"),
          project_name(entry),
          entry.notes || ""
        ]
      end)

    to_csv([header | rows])
  end

  def format_duration(total_seconds) do
    hours = div(total_seconds, 3600)
    minutes = div(rem(total_seconds, 3600), 60)
    seconds = rem(total_seconds, 60)
    :io_lib.format("~2..0B:~2..0B:~2..0B", [hours, minutes, seconds]) |> to_string()
  end

  # No project columns at all when no projects exist. Otherwise every active
  # project, every project with time in this export, and "No project" (nil).
  defp project_columns(_days, []), do: []

  defp project_columns(days, projects) do
    booked_ids =
      days
      |> Enum.flat_map(&Map.keys(&1.by_project))
      |> MapSet.new()

    projects
    |> Enum.filter(&(&1.active || MapSet.member?(booked_ids, &1.id)))
    |> Enum.sort_by(&String.downcase(&1.name))
    |> Kernel.++([nil])
  end

  defp entry_seconds(%{clock_out: nil}), do: 0

  defp entry_seconds(entry) do
    entry.clock_out |> NaiveDateTime.diff(entry.clock_in, :second) |> max(0)
  end

  defp user_name(%{user: %{name: name}}), do: name
  defp user_name(_entry), do: ""

  defp project_name(%{project: %{name: name}}), do: name
  defp project_name(_entry), do: ""

  defp format_naive_dt(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end

  defp to_csv(rows) do
    Enum.map_join(rows, fn row ->
      Enum.map_join(row, ",", &csv_escape/1) <> "\n"
    end)
  end

  defp csv_escape(value) do
    str = to_string(value)

    if String.contains?(str, [",", "\"", "\n", "\r"]) do
      "\"#{String.replace(str, "\"", "\"\"")}\""
    else
      str
    end
  end
end
