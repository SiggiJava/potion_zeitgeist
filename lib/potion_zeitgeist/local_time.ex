defmodule PotionZeitgeist.LocalTime do
  @moduledoc """
  The time zone the app works in, and conversions between it and UTC.

  Clock-in and clock-out times are stored in UTC (as naive datetimes), so
  durations stay exact when the clocks change between summer and winter
  time. Everything people read or type uses the wall-clock time of the
  app's time zone instead: the pages, the edit forms, the CSV exports and
  the invoices. Days and months begin at midnight in that zone, so a daily
  total holds the entries clocked in on that local day.

  The zone is an IANA name such as `"Europe/Berlin"` (the default), set with
  the `TIME_ZONE` environment variable (see `config/runtime.exs`). The time
  zone data comes with the `tz` package.
  """

  @default_zone "Europe/Berlin"

  @doc "The app's time zone, e.g. `\"Europe/Berlin\"`."
  def zone, do: Application.get_env(:potion_zeitgeist, :time_zone, @default_zone)

  @doc """
  Raises with a readable message when `zone` is not a time zone the app
  accepts. Runs when the app starts, so a mistyped `TIME_ZONE` stops it
  instead of showing wrong times.

  Only IANA names of the form Area/Location (and `"UTC"`) are accepted:
  Postgres, which sorts entries into months for the invoice form, reads
  short names such as CET as a fixed offset without summer time.
  """
  def validate!(zone \\ zone()) do
    if known_zone?(zone) do
      :ok
    else
      raise ArgumentError,
            "TIME_ZONE #{inspect(zone)} is not a time zone the app accepts. " <>
              "Use an IANA name of the form Area/City, such as Europe/Berlin or Europe/Vienna."
    end
  end

  defp known_zone?(zone) when is_binary(zone) do
    (zone == "UTC" or String.contains?(zone, "/")) and
      match?({:ok, _}, DateTime.shift_zone(DateTime.utc_now(), zone))
  end

  defp known_zone?(_zone), do: false

  @doc "Today's date in the app's time zone."
  def today, do: NaiveDateTime.utc_now() |> to_date()

  @doc """
  The wall-clock time in the app's time zone of `datetime`: a stored UTC
  time (naive datetime) or a `DateTime`. `nil` stays `nil`.
  """
  def to_local(nil), do: nil
  def to_local(datetime), do: datetime |> in_zone() |> DateTime.to_naive()

  @doc "The day of `datetime` in the app's time zone (see `to_local/1`)."
  def to_date(nil), do: nil
  def to_date(datetime), do: datetime |> in_zone() |> DateTime.to_date()

  @doc """
  Formats `datetime` (see `to_local/1`) in the app's time zone with
  `Calendar.strftime/2`; `%Z` gives the zone abbreviation, such as CEST.
  """
  def strftime(datetime, format), do: datetime |> in_zone() |> Calendar.strftime(format)

  defp in_zone(%NaiveDateTime{} = utc), do: utc |> DateTime.from_naive!("Etc/UTC") |> in_zone()
  defp in_zone(%DateTime{} = datetime), do: DateTime.shift_zone!(datetime, zone())

  @doc """
  The UTC time (naive, as stored) of the wall-clock time `local` in the
  app's time zone:

    * `{:ok, utc}`,
    * `{:ambiguous, earlier, later}` for a time in the hour that happens
      twice when summer time ends (`earlier` is still summer time),
    * `{:error, :gap}` for a time in the hour that is skipped when summer
      time begins.
  """
  def to_utc(%NaiveDateTime{} = local) do
    case DateTime.from_naive(local, zone()) do
      {:ok, datetime} -> {:ok, utc(datetime)}
      {:ambiguous, earlier, later} -> {:ambiguous, utc(earlier), utc(later)}
      {:gap, _before, _after} -> {:error, :gap}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  The UTC time (naive, as stored) at which `date` begins in the app's time
  zone. Where a zone changes its clocks at midnight, the day begins with
  its first moment.
  """
  def day_start(%Date{} = date) do
    case DateTime.new(date, ~T[00:00:00], zone()) do
      {:ok, datetime} -> utc(datetime)
      {:ambiguous, earlier, _later} -> utc(earlier)
      {:gap, _before, first_moment} -> utc(first_moment)
    end
  end

  @doc """
  The UTC times (naive) between which the days `first` to `last` lie in the
  app's time zone: from the start of `first` (included) to the start of the
  day after `last` (excluded). A day can be 23 or 25 hours long.
  """
  def day_range(%Date{} = first, %Date{} = last) do
    {day_start(first), day_start(Date.add(last, 1))}
  end

  @doc "The UTC times (naive) between which `date` lies, see `day_range/2`."
  def day_range(%Date{} = date), do: day_range(date, date)

  defp utc(%DateTime{} = datetime) do
    datetime
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.to_naive()
    |> NaiveDateTime.truncate(:second)
  end

  ## datetime-local inputs

  @doc """
  The value of a `datetime-local` input for a stored UTC time: its
  wall-clock time in the app's time zone, to the minute, such as
  `"2026-11-05T21:17"`. `nil` gives an empty input.
  """
  def input_value(nil), do: ""
  def input_value(utc), do: strftime(utc, "%Y-%m-%dT%H:%M")

  @doc """
  The stored UTC time of a `datetime-local` input value, which is a
  wall-clock time in the app's time zone. Returns `{:ok, utc}`, `{:ok, nil}`
  for an empty input, or `{:error, message}`.

  `current` is the time the field holds so far. While the input still shows
  it (see `input_value/1`), it is kept as it is: with its seconds, which the
  input does not show, and in the hour that happens twice when summer time
  ends, where the same wall-clock time stands for two moments.

  A new time in that hour is one of its two moments: one that is neither
  before `opts[:not_before]` nor after `opts[:not_after]` (for a clock-out
  the clock-in, for a clock-in the clock-out), and of those the one on the
  same side of the change as `current` (same UTC offset), else the earlier
  one (still summer time). A time in the hour skipped when summer time
  begins does not exist and is refused.
  """
  def parse_input(value, current \\ nil, opts \\ [])

  def parse_input(nil, _current, _opts), do: {:ok, nil}

  def parse_input(value, current, opts) when is_binary(value) do
    value = value |> String.trim() |> String.replace(" ", "T")

    cond do
      value == "" ->
        {:ok, nil}

      current && value == input_value(current) ->
        {:ok, current}

      true ->
        case parse_local(value) do
          {:ok, local} ->
            if current && local == to_local(current),
              do: {:ok, current},
              else: from_local(local, current, opts)

          :error ->
            {:error, "is invalid"}
        end
    end
  end

  def parse_input(_value, _current, _opts), do: {:error, "is invalid"}

  # "2026-11-05T21:17" as the input sends it, or with seconds.
  defp parse_local(value) do
    value = if String.length(value) == 16, do: value <> ":00", else: value

    case NaiveDateTime.from_iso8601(value) do
      {:ok, local} -> {:ok, NaiveDateTime.truncate(local, :second)}
      {:error, _} -> :error
    end
  end

  defp from_local(local, current, opts) do
    case to_utc(local) do
      {:ok, utc} ->
        {:ok, utc}

      {:ambiguous, earlier, later} ->
        {:ok, pick_moment(local, [earlier, later], current, opts)}

      {:error, :gap} ->
        {:error, "does not exist: the clocks in #{zone()} skip this hour when summer time begins"}

      {:error, _reason} ->
        {:error, "is invalid"}
    end
  end

  # Of the two moments of `local` in the hour that happens twice: those
  # within the bounds (both when neither is), then the one with the UTC
  # offset of `current`, else the earlier one.
  defp pick_moment(local, moments, current, opts) do
    within =
      Enum.filter(moments, fn moment ->
        not_before?(moment, opts[:not_before]) and not_after?(moment, opts[:not_after])
      end)

    choices = if within == [], do: moments, else: within
    offset = current && NaiveDateTime.diff(to_local(current), current)

    Enum.find(choices, hd(choices), &(offset == NaiveDateTime.diff(local, &1)))
  end

  defp not_before?(_moment, nil), do: true
  defp not_before?(moment, bound), do: NaiveDateTime.compare(moment, bound) != :lt

  defp not_after?(_moment, nil), do: true
  defp not_after?(moment, bound), do: NaiveDateTime.compare(moment, bound) != :gt
end
