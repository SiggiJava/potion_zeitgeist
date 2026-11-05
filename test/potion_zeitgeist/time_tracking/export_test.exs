defmodule PotionZeitgeist.TimeTracking.ExportTest do
  use ExUnit.Case, async: true

  alias PotionZeitgeist.TimeTracking.Export

  @anna %{name: "Anna"}
  @ben %{name: "Ben, Jr."}
  @alpha %{id: 1, name: "Alpha", active: true}
  @beta %{id: 2, name: "Beta", active: false}
  @gamma %{id: 3, name: "Gamma", active: false}

  defp entry(user_id, user, clock_in, clock_out, project \\ nil) do
    %{
      user_id: user_id,
      user: user,
      clock_in: NaiveDateTime.from_iso8601!(clock_in),
      clock_out: clock_out && NaiveDateTime.from_iso8601!(clock_out),
      project_id: project && project.id,
      project: project,
      notes: nil
    }
  end

  defp entries do
    [
      entry(1, @anna, "2026-10-19 08:00:00", "2026-10-19 12:00:00", @alpha),
      entry(1, @anna, "2026-10-19 12:30:00", "2026-10-19 14:00:00"),
      entry(1, @anna, "2026-10-19 14:00:00", "2026-10-19 17:15:30", @beta),
      entry(2, @ben, "2026-10-19 09:00:00", "2026-10-19 10:00:00", @alpha),
      entry(1, @anna, "2026-10-20 09:00:00", nil, @alpha)
    ]
  end

  describe "daily_totals/1" do
    test "sums several clock-in/clock-out pairs into one total per user and day" do
      assert [anna, ben] = Export.daily_totals(entries())

      assert anna.date == ~D[2026-10-19]
      assert anna.entry_count == 3
      assert anna.total_seconds == 4 * 3600 + 90 * 60 + 3 * 3600 + 15 * 60 + 30
      assert anna.by_project == %{1 => 4 * 3600, 2 => 3 * 3600 + 15 * 60 + 30, nil => 90 * 60}

      assert ben.total_seconds == 3600
    end

    test "leaves out entries that are still running" do
      refute Enum.any?(Export.daily_totals(entries()), &(&1.date == ~D[2026-10-20]))
    end
  end

  describe "daily_csv/2" do
    test "has no project columns when no projects exist" do
      assert Export.daily_csv(entries(), []) ==
               """
               Date,User,Entries,Total
               2026-10-19,Anna,3,08:45:30
               2026-10-19,"Ben, Jr.",1,01:00:00
               """
    end

    test "splits the daily total by project, with time without a project in its own column" do
      assert Export.daily_csv(entries(), [@alpha, @beta, @gamma]) ==
               """
               Date,User,Entries,Total,Alpha,Beta,No project
               2026-10-19,Anna,3,08:45:30,04:00:00,03:15:30,01:30:00
               2026-10-19,"Ben, Jr.",1,01:00:00,01:00:00,00:00:00,00:00:00
               """
    end
  end

  describe "entries_csv/1" do
    test "lists every entry with its project, in local time" do
      csv = Export.entries_csv(entries())

      assert csv =~ "Date,User,Clock In,Clock Out,Duration,Project,Notes\n"
      # Stored in UTC, shown in Berlin summer time (UTC+2).
      assert csv =~ "2026-10-19,Anna,2026-10-19 10:00:00,2026-10-19 14:00:00,04:00:00,Alpha,\n"
      assert csv =~ "2026-10-20,Anna,2026-10-20 11:00:00,,In progress,Alpha,\n"
    end
  end

  describe "local time" do
    test "days begin at midnight in Berlin, not in UTC" do
      # 00:30 to 01:30 on 20 October in Berlin, still the 19th in UTC.
      late = [entry(1, @anna, "2026-10-19 22:30:00", "2026-10-19 23:30:00")]

      assert [%{date: ~D[2026-10-20], total_seconds: 3600}] = Export.daily_totals(late)
      assert Export.daily_csv(late, []) =~ "2026-10-20,Anna,1,01:00:00\n"

      assert Export.entries_csv(late) =~
               "2026-10-20,Anna,2026-10-20 00:30:00,2026-10-20 01:30:00,01:00:00,,\n"
    end

    test "winter time: a November evening" do
      evening = [entry(1, @anna, "2026-11-05 20:17:00", "2026-11-05 22:00:00")]

      assert Export.entries_csv(evening) =~
               "2026-11-05,Anna,2026-11-05 21:17:00,2026-11-05 23:00:00,01:43:00,,\n"
    end

    test "a night shift across the end of summer time counts the hour that happens twice" do
      # 01:30 summer time to 03:30 winter time on 25 October: three hours.
      night = [entry(1, @anna, "2026-10-24 23:30:00", "2026-10-25 02:30:00")]

      assert [%{date: ~D[2026-10-25], total_seconds: 10_800}] = Export.daily_totals(night)

      assert Export.entries_csv(night) =~
               "2026-10-25,Anna,2026-10-25 01:30:00,2026-10-25 03:30:00,03:00:00,,\n"
    end
  end
end
