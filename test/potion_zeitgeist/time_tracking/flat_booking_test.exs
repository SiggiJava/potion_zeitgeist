defmodule PotionZeitgeist.TimeTracking.FlatBookingTest do
  use ExUnit.Case, async: true

  alias PotionZeitgeist.TimeTracking.FlatBooking

  test "hours are typed as a number or as hours and minutes" do
    for {text, minutes} <- [
          {"120", 7200},
          {"120,5", 7230},
          {"120.5", 7230},
          {"7,25", 435},
          {" 8 h", 480},
          {"7,5 Std.", 450},
          {"120:30", 7230},
          {"0:01", 1},
          {"8,33", 500},
          {"744", 44_640},
          # Pasted with an invisible character.
          {"1​20", 7200}
        ] do
      assert FlatBooking.parse_hours(text) == {:ok, minutes}, text
    end
  end

  test "hours the invoice cannot bill as typed are refused with the nearest ones" do
    assert FlatBooking.parse_hours("8,34") ==
             {:error, "cannot be billed in whole minutes, enter 8,33 (8:20) or 8,35 (8:21)"}

    assert FlatBooking.parse_hours("0,001") ==
             {:error, "cannot be billed in whole minutes, enter 0,02 (0:01)"}

    for text <- ["0", "-1", "0:00", "744,5", "745:00", "1.000"] do
      assert FlatBooking.parse_hours(text) == {:error, "must be above 0 and at most 744 hours"},
             text
    end

    for text <- ["", "zwölf", "7:60", "12:3", "1e2", "8 Stunden"] do
      assert FlatBooking.parse_hours(text) ==
               {:error, "enter the hours, such as 120, 120,5 or 120:30"},
             text
    end
  end

  test "the hours the form shows give the same minutes again" do
    for minutes <- Enum.concat(1..200, 44_440..44_640) do
      assert FlatBooking.parse_hours(FlatBooking.hours_text(minutes)) == {:ok, minutes}
    end

    assert FlatBooking.hours_text(7200) == "120"
    assert FlatBooking.hours_text(7230) == "120,5"
    assert FlatBooking.hours_text(500) == "8,33"
  end
end
