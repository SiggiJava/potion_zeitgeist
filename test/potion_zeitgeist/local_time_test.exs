defmodule PotionZeitgeist.LocalTimeTest do
  use ExUnit.Case, async: true

  alias PotionZeitgeist.LocalTime

  # Tests run in Europe/Berlin. In 2026 summer time (CEST, UTC+2) begins on
  # 29 March at 2:00 and ends on 25 October at 3:00; winter time is CET, UTC+1.

  test "the app runs in Europe/Berlin" do
    assert LocalTime.zone() == "Europe/Berlin"
    assert LocalTime.validate!() == :ok
  end

  test "an unknown time zone stops the app with a readable message" do
    assert_raise ArgumentError, ~r/TIME_ZONE "Europe\/Berln" is not a time zone/, fn ->
      LocalTime.validate!("Europe/Berln")
    end

    assert_raise ArgumentError, fn -> LocalTime.validate!(nil) end
    # Postgres would read CET as a fixed offset without summer time.
    assert_raise ArgumentError, ~r/Area\/City/, fn -> LocalTime.validate!("CET") end
    assert LocalTime.validate!("Europe/Vienna") == :ok
    assert LocalTime.validate!("UTC") == :ok
  end

  describe "stored UTC times as local time" do
    test "with winter and summer time" do
      # Clocked in at 21:17 in Berlin on a November evening.
      assert LocalTime.to_local(~N[2026-11-05 20:17:00]) == ~N[2026-11-05 21:17:00]
      assert LocalTime.to_local(~N[2026-07-01 10:00:00]) == ~N[2026-07-01 12:00:00]
      assert LocalTime.to_local(~U[2026-07-01 10:00:00Z]) == ~N[2026-07-01 12:00:00]
      assert LocalTime.to_local(nil) == nil
    end

    test "the day changes at local midnight" do
      assert LocalTime.to_date(~N[2026-10-19 21:59:59]) == ~D[2026-10-19]
      assert LocalTime.to_date(~N[2026-10-19 22:00:00]) == ~D[2026-10-20]
      assert LocalTime.to_date(~N[2026-12-31 23:30:00]) == ~D[2027-01-01]
      assert LocalTime.to_date(~U[2026-03-31 22:30:00Z]) == ~D[2026-04-01]
      assert LocalTime.to_date(nil) == nil
    end

    test "formatted, with the zone abbreviation on request" do
      assert LocalTime.strftime(~N[2026-11-05 20:17:42], "%Y-%m-%d %H:%M:%S %Z") ==
               "2026-11-05 21:17:42 CET"

      assert LocalTime.strftime(~N[2026-07-01 10:00:00], "%H:%M %Z") == "12:00 CEST"
    end

    test "the hour that happens twice shows the same wall-clock time twice" do
      assert LocalTime.strftime(~N[2026-10-25 00:30:00], "%H:%M %Z") == "02:30 CEST"
      assert LocalTime.strftime(~N[2026-10-25 01:30:00], "%H:%M %Z") == "02:30 CET"
    end
  end

  describe "local times as stored UTC times" do
    test "convert with the offset of that day" do
      assert LocalTime.to_utc(~N[2026-11-05 21:17:00]) == {:ok, ~N[2026-11-05 20:17:00]}
      assert LocalTime.to_utc(~N[2026-07-01 12:00:00]) == {:ok, ~N[2026-07-01 10:00:00]}
    end

    test "in the hour that happens twice give both moments" do
      assert LocalTime.to_utc(~N[2026-10-25 02:30:00]) ==
               {:ambiguous, ~N[2026-10-25 00:30:00], ~N[2026-10-25 01:30:00]}
    end

    test "in the skipped hour do not exist" do
      assert LocalTime.to_utc(~N[2026-03-29 02:30:00]) == {:error, :gap}
    end
  end

  describe "days" do
    test "begin at local midnight" do
      assert LocalTime.day_start(~D[2026-11-05]) == ~N[2026-11-04 23:00:00]
      assert LocalTime.day_start(~D[2026-07-01]) == ~N[2026-06-30 22:00:00]

      assert LocalTime.day_range(~D[2026-11-05]) ==
               {~N[2026-11-04 23:00:00], ~N[2026-11-05 23:00:00]}
    end

    test "are 25 hours long when summer time ends and 23 hours when it begins" do
      assert LocalTime.day_range(~D[2026-10-25]) ==
               {~N[2026-10-24 22:00:00], ~N[2026-10-25 23:00:00]}

      assert LocalTime.day_range(~D[2026-03-29]) ==
               {~N[2026-03-28 23:00:00], ~N[2026-03-29 22:00:00]}
    end

    test "of a month run from its first local midnight to the next month's" do
      assert LocalTime.day_range(~D[2026-10-01], ~D[2026-10-31]) ==
               {~N[2026-09-30 22:00:00], ~N[2026-10-31 23:00:00]}
    end

    test "today is the local date" do
      assert LocalTime.today() == LocalTime.to_date(NaiveDateTime.utc_now()) or
               LocalTime.today() == Date.add(LocalTime.to_date(NaiveDateTime.utc_now()), -1)
    end
  end

  describe "datetime-local inputs" do
    test "show the local time to the minute" do
      assert LocalTime.input_value(~N[2026-11-05 20:17:42]) == "2026-11-05T21:17"
      assert LocalTime.input_value(nil) == ""
    end

    test "are read as local time" do
      assert LocalTime.parse_input("2026-11-05T21:17") == {:ok, ~N[2026-11-05 20:17:00]}
      assert LocalTime.parse_input("2026-11-05T21:17:30") == {:ok, ~N[2026-11-05 20:17:30]}
      assert LocalTime.parse_input("2026-11-05 21:17") == {:ok, ~N[2026-11-05 20:17:00]}
      assert LocalTime.parse_input("2026-07-01T12:00") == {:ok, ~N[2026-07-01 10:00:00]}
    end

    test "empty or unreadable" do
      assert LocalTime.parse_input("") == {:ok, nil}
      assert LocalTime.parse_input(nil) == {:ok, nil}
      assert LocalTime.parse_input("  ") == {:ok, nil}
      assert LocalTime.parse_input("yesterday") == {:error, "is invalid"}
      assert LocalTime.parse_input("2026-13-01T10:00") == {:error, "is invalid"}
      assert LocalTime.parse_input(["2026-11-05T21:17"]) == {:error, "is invalid"}
    end

    test "keep the stored time while they still show it" do
      # The seconds, which the input does not show.
      assert LocalTime.parse_input("2026-11-05T21:17", ~N[2026-11-05 20:17:42]) ==
               {:ok, ~N[2026-11-05 20:17:42]}

      # The second 02:30 of the night summer time ends (winter time).
      assert LocalTime.parse_input("2026-10-25T02:30", ~N[2026-10-25 01:30:00]) ==
               {:ok, ~N[2026-10-25 01:30:00]}

      # A changed time is read anew.
      assert LocalTime.parse_input("2026-11-05T21:18", ~N[2026-11-05 20:17:42]) ==
               {:ok, ~N[2026-11-05 20:18:00]}
    end

    test "in the hour that happens twice take the earlier moment unless it is too early" do
      assert LocalTime.parse_input("2026-10-25T02:30") == {:ok, ~N[2026-10-25 00:30:00]}

      # A clock-out after a clock-in at 02:10 winter time (01:10 UTC).
      assert LocalTime.parse_input("2026-10-25T02:30", nil, not_before: ~N[2026-10-25 01:10:00]) ==
               {:ok, ~N[2026-10-25 01:30:00]}

      assert LocalTime.parse_input("2026-10-25T02:30", nil, not_before: ~N[2026-10-24 23:30:00]) ==
               {:ok, ~N[2026-10-25 00:30:00]}

      # A clock-in before a clock-out at 02:20 summer time (00:20 UTC).
      assert LocalTime.parse_input("2026-10-25T02:10", nil, not_after: ~N[2026-10-25 00:20:00]) ==
               {:ok, ~N[2026-10-25 00:10:00]}
    end

    test "in the hour that happens twice stay on the side of the change they were on" do
      # Was 02:05 winter time (01:05 UTC), changed to 02:10.
      assert LocalTime.parse_input("2026-10-25T02:10", ~N[2026-10-25 01:05:00]) ==
               {:ok, ~N[2026-10-25 01:10:00]}

      # Was 02:05 summer time (00:05 UTC).
      assert LocalTime.parse_input("2026-10-25T02:10", ~N[2026-10-25 00:05:00]) ==
               {:ok, ~N[2026-10-25 00:10:00]}

      # Unless the bounds rule that side out.
      assert LocalTime.parse_input("2026-10-25T02:10", ~N[2026-10-25 01:05:00],
               not_after: ~N[2026-10-25 00:40:00]
             ) == {:ok, ~N[2026-10-25 00:10:00]}
    end

    test "in the skipped hour are refused" do
      assert {:error, message} = LocalTime.parse_input("2026-03-29T02:30")
      assert message =~ "does not exist"
      assert message =~ "Europe/Berlin"

      assert LocalTime.parse_input("2026-03-29T03:00") == {:ok, ~N[2026-03-29 01:00:00]}
      assert LocalTime.parse_input("2026-03-29T01:59") == {:ok, ~N[2026-03-29 00:59:00]}
    end
  end
end
