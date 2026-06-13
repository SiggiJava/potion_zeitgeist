defmodule PotionZeitgeist.TimeTracking.TimeEntry do
  use Ecto.Schema
  import Ecto.Changeset

  schema "time_entries" do
    field :clock_in, :naive_datetime
    field :clock_out, :naive_datetime
    field :notes, PotionZeitgeist.Encrypted.Binary, source: :encrypted_notes

    belongs_to :user, PotionZeitgeist.Accounts.User

    timestamps()
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:clock_in, :clock_out, :notes, :user_id])
    |> validate_required([:clock_in, :user_id])
    |> validate_clock_order()
  end

  def clock_out_changeset(entry, attrs) do
    entry
    |> cast(attrs, [:clock_out, :notes])
    |> validate_required([:clock_out])
    |> validate_clock_order()
  end

  def edit_changeset(entry, attrs) do
    entry
    |> cast(attrs, [:clock_in, :clock_out, :notes])
    |> validate_required([:clock_in])
    |> validate_clock_order()
  end

  defp validate_clock_order(changeset) do
    clock_in = get_field(changeset, :clock_in)
    clock_out = get_field(changeset, :clock_out)

    if clock_in && clock_out && NaiveDateTime.compare(clock_out, clock_in) == :lt do
      add_error(changeset, :clock_out, "must be after clock-in time")
    else
      changeset
    end
  end
end
