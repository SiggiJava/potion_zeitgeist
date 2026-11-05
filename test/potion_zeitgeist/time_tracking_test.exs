defmodule PotionZeitgeist.TimeTrackingTest do
  use PotionZeitgeist.DataCase, async: true

  import PotionZeitgeist.Fixtures

  alias PotionZeitgeist.{Repo, TimeTracking}

  # Times are stored in UTC; the app runs in Europe/Berlin in tests.

  setup do
    %{user: user_fixture()}
  end

  describe "entries of a day" do
    test "are those clocked in between two local midnights", %{user: user} do
      # 00:30 on 20 October in Berlin (summer time), still the 19th in UTC.
      early = entry_fixture(user, "2026-10-19 22:30:00", "2026-10-19 23:00:00")
      day = entry_fixture(user, "2026-10-20 08:00:00", "2026-10-20 12:00:00")
      # 00:30 on 21 October in Berlin.
      entry_fixture(user, "2026-10-20 22:30:00", "2026-10-20 23:00:00")
      # 23:30 on 19 October in Berlin.
      entry_fixture(user, "2026-10-19 21:30:00", "2026-10-19 21:45:00")

      assert Enum.map(TimeTracking.list_entries_for_date(user.id, ~D[2026-10-20]), & &1.id) ==
               [early.id, day.id]
    end
  end

  describe "the edit form" do
    test "takes the times it shows as local time", %{user: user} do
      entry = entry_fixture(user, "2026-11-05 20:17:00", "2026-11-05 22:00:00")

      assert {:ok, updated} =
               TimeTracking.update_entry_from_form(entry, %{
                 "clock_in" => "2026-11-05T21:00",
                 "clock_out" => "2026-11-05T23:30",
                 "notes" => "Abends"
               })

      assert updated.clock_in == ~N[2026-11-05 20:00:00]
      assert updated.clock_out == ~N[2026-11-05 22:30:00]
      assert updated.notes == "Abends"
    end

    test "keeps unchanged times to the second", %{user: user} do
      entry = entry_fixture(user, "2026-11-05 20:17:42", "2026-11-05 22:00:09")

      assert {:ok, updated} =
               TimeTracking.update_entry_from_form(entry, %{
                 "clock_in" => "2026-11-05T21:17",
                 "clock_out" => "2026-11-05T23:00",
                 "notes" => "Nur die Notiz"
               })

      assert updated.clock_in == ~N[2026-11-05 20:17:42]
      assert updated.clock_out == ~N[2026-11-05 22:00:09]
    end

    test "an empty clock-out keeps the entry running", %{user: user} do
      entry = entry_fixture(user, "2026-11-05 20:17:00", "2026-11-05 22:00:00")

      assert {:ok, updated} =
               TimeTracking.update_entry_from_form(entry, %{
                 "clock_in" => "2026-11-05T21:17",
                 "clock_out" => ""
               })

      assert updated.clock_out == nil
    end

    test "refuses a time in the hour skipped when summer time begins", %{user: user} do
      entry = entry_fixture(user, "2026-03-28 23:30:00", "2026-03-29 03:00:00")

      assert {:error, changeset} =
               TimeTracking.update_entry_from_form(entry, %{
                 "clock_in" => "2026-03-29T02:30",
                 "clock_out" => "2026-03-29T05:00"
               })

      assert changeset.action == :update
      assert [{message, _}] = Keyword.get_values(changeset.errors, :clock_in)
      assert message =~ "does not exist"
      assert Repo.reload(entry).clock_in == ~N[2026-03-28 23:30:00]
    end

    test "places a clock-out in the hour that happens twice after the clock-in", %{user: user} do
      # 02:10 winter time (01:10 UTC) on 25 October, the second 02:10 that night.
      entry = entry_fixture(user, "2026-10-25 01:10:00", "2026-10-25 01:20:00")

      assert {:ok, updated} =
               TimeTracking.update_entry_from_form(entry, %{
                 "clock_in" => "2026-10-25T02:10",
                 "clock_out" => "2026-10-25T02:40"
               })

      assert updated.clock_in == ~N[2026-10-25 01:10:00]
      assert updated.clock_out == ~N[2026-10-25 01:40:00]
    end

    test "still refuses a clock-out before the clock-in", %{user: user} do
      entry = entry_fixture(user, "2026-11-05 20:17:00", "2026-11-05 22:00:00")

      assert {:error, changeset} =
               TimeTracking.update_entry_from_form(entry, %{
                 "clock_in" => "2026-11-05T21:17",
                 "clock_out" => "2026-11-05T20:00"
               })

      assert Keyword.has_key?(changeset.errors, :clock_out)
    end
  end
end
