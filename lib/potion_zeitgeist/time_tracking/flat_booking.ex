defmodule PotionZeitgeist.TimeTracking.FlatBooking do
  @moduledoc """
  Flat hours: the hours of a whole month booked at once, such as 120 hours
  in October for a project, for time recorded elsewhere (for example with
  the time clock of a client one works at), so it is not clocked a second
  time.

  Flat hours belong to a user and, optionally, a project. Invoices bill them
  like the time entries of their project and month. Having no clock-in and
  clock-out, they are no working time record: the daily totals export and
  the dashboard leave them out.

  The hours are stored as minutes, as time entries count. They are typed as
  a number of hours ("120", "120,5") or as hours and minutes ("120:30"), see
  `parse_hours/1`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias PotionZeitgeist.Invoicing.{Calculation, Format, LetterLayout, ManualItem}

  # A month has at most 31 days of 24 hours.
  @max_minutes 31 * 24 * 60
  @max_notes 1000

  schema "flat_bookings" do
    # The first day of the month the hours are booked for.
    field :month, :date
    field :minutes, :integer
    field :notes, PotionZeitgeist.Encrypted.Binary, source: :encrypted_notes
    # The hours as the form shows and sends them, see `changeset/2`.
    field :hours, :string, virtual: true
    # Set by `PotionZeitgeist.TimeTracking.list_flat_bookings/1`.
    field :invoiced, :boolean, virtual: true, default: false

    belongs_to :user, PotionZeitgeist.Accounts.User
    belongs_to :project, PotionZeitgeist.Projects.Project

    timestamps()
  end

  @doc """
  Month, hours, notes and project of `attrs`. The month may be any day of
  it (the form sends its first day). The hours are kept as they are unless
  `attrs` has `hours`, so clearing them in the form is an error and not a
  change that is left out.
  """
  def changeset(booking, attrs) do
    %{booking | hours: booking.hours || (booking.minutes && hours_text(booking.minutes))}
    |> cast(attrs, [:month, :hours, :notes, :project_id])
    |> update_change(:month, &Date.beginning_of_month/1)
    |> validate_required([:month], message: "pick a month")
    |> cast_hours()
    |> validate_length(:notes, max: @max_notes)
    |> assoc_constraint(:project)
    |> check_constraint(:minutes,
      name: :flat_bookings_minutes_valid,
      message: "must be above 0 and at most 744 hours"
    )
  end

  defp cast_hours(changeset) do
    case fetch_change(changeset, :hours) do
      {:ok, text} when is_binary(text) ->
        case parse_hours(text) do
          {:ok, minutes} -> put_change(changeset, :minutes, minutes)
          {:error, message} -> add_error(changeset, :hours, message)
        end

      _cleared_or_unchanged ->
        if get_field(changeset, :hours) && get_field(changeset, :minutes),
          do: changeset,
          else: add_error(changeset, :hours, "enter the hours, such as 120 or 120:30")
    end
  end

  @doc """
  The minutes of hours typed as a number with a German comma or a decimal
  point ("120", "120,5", "7.25") or as hours and minutes ("120:30"), above
  0 and at most 744 hours (a month of 31 days). A trailing "h" or "Std." is
  allowed.

  A number of hours is taken only when the invoice bills it as typed: in
  whole minutes that give the same hours with two decimals. 8,33 hours are
  500 minutes, which bill as 8,33 hours; 8,34 hours lie between 500 and 501
  minutes, which bill as 8,33 and 8,35 hours, so the message suggests those.
  """
  def parse_hours(text) when is_binary(text) do
    text =
      text
      |> LetterLayout.clean()
      |> String.replace(~r/[\s\x{00A0}\x{202F}\p{Cf}]/u, "")
      |> String.replace(~r/(h|std\.?)$/iu, "")

    case Regex.run(~r/^(\d{1,3}):([0-5]\d)$/, text) do
      [_, hours, minutes] ->
        check_minutes(String.to_integer(hours) * 60 + String.to_integer(minutes))

      nil ->
        text |> ManualItem.parse_number_text() |> minutes_of_hours()
    end
  end

  def parse_hours(_text), do: {:error, "enter the hours, such as 120 or 120:30"}

  defp minutes_of_hours(nil), do: {:error, "enter the hours, such as 120, 120,5 or 120:30"}

  defp minutes_of_hours(hours) do
    exact = Decimal.mult(hours, 60)
    minutes = exact |> Decimal.round(0, :half_up) |> Decimal.to_integer()

    cond do
      not Decimal.gt?(hours, 0) or minutes > @max_minutes ->
        check_minutes(minutes)

      Decimal.eq?(Calculation.hours(minutes), hours) ->
        check_minutes(minutes)

      true ->
        lower = exact |> Decimal.round(0, :floor) |> Decimal.to_integer()
        upper = exact |> Decimal.round(0, :ceiling) |> Decimal.to_integer()

        choices =
          [lower, upper]
          |> Enum.filter(&(&1 > 0 and &1 <= @max_minutes))
          |> Enum.uniq()
          |> Enum.map_join(" or ", &"#{hours_text(&1)} (#{Format.duration(&1)})")

        {:error, "cannot be billed in whole minutes, enter #{choices}"}
    end
  end

  defp check_minutes(minutes) when minutes > 0 and minutes <= @max_minutes, do: {:ok, minutes}
  defp check_minutes(_minutes), do: {:error, "must be above 0 and at most 744 hours"}

  @doc """
  The hours of `minutes` as typed into the form: "120", "120,5", "8,33".
  They give the same minutes again.
  """
  def hours_text(minutes) do
    minutes
    |> Calculation.hours()
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
    |> String.replace(".", ",")
  end
end
