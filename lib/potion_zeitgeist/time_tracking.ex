defmodule PotionZeitgeist.TimeTracking do
  import Ecto.Query

  alias PotionZeitgeist.{Invoicing, LocalTime, Projects, Repo}
  alias PotionZeitgeist.Invoicing.InvoiceEntry
  alias PotionZeitgeist.TimeTracking.{Export, FlatBooking, TimeEntry}

  def get_active_entry(user_id) do
    Repo.one(
      from e in TimeEntry,
        where: e.user_id == ^user_id and is_nil(e.clock_out),
        order_by: [desc: e.clock_in],
        limit: 1,
        preload: [:project]
    )
  end

  @doc """
  Entries of a user, newest first, with `invoiced` set for entries on a draft
  or issued invoice.
  """
  def list_entries(user_id) do
    Repo.all(
      from e in TimeEntry,
        left_join: ie in InvoiceEntry,
        on: ie.time_entry_id == e.id and ie.active,
        where: e.user_id == ^user_id,
        order_by: [desc: e.clock_in],
        select_merge: %{invoiced: not is_nil(ie.id)},
        preload: [:project]
    )
  end

  @doc """
  Lists entries of one user, or of all users when `user_id` is `:all`,
  with user and project preloaded for the export.
  """
  def list_entries_for_export(:all) do
    Repo.all(from e in TimeEntry, order_by: [asc: e.clock_in], preload: [:user, :project])
  end

  def list_entries_for_export(user_id) do
    Repo.all(
      from e in TimeEntry,
        where: e.user_id == ^user_id,
        order_by: [asc: e.clock_in],
        preload: [:user, :project]
    )
  end

  @doc """
  Entries of a user clocked in on `date`, a day in the app's time zone (see
  `PotionZeitgeist.LocalTime`).
  """
  def list_entries_for_date(user_id, date) do
    {start_of_day, next_day} = LocalTime.day_range(date)

    Repo.all(
      from e in TimeEntry,
        where:
          e.user_id == ^user_id and
            e.clock_in >= ^start_of_day and
            e.clock_in < ^next_day,
        order_by: [asc: e.clock_in]
    )
  end

  def get_entry!(id), do: TimeEntry |> Repo.get!(id) |> Repo.preload(:project)

  def get_entry!(id, user_id) do
    TimeEntry |> Repo.get_by!(id: id, user_id: user_id) |> Repo.preload(:project)
  end

  def clock_in(user_id, project_id \\ nil) do
    case get_active_entry(user_id) do
      nil ->
        %TimeEntry{}
        |> TimeEntry.changeset(%{
          user_id: user_id,
          project_id: project_id,
          clock_in: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        })
        |> validate_bookable_project()
        |> Repo.insert()

      _existing ->
        {:error, :already_clocked_in}
    end
  end

  @doc """
  Books a running or finished entry to another project (or to none with `nil`).
  """
  def set_entry_project(%TimeEntry{} = entry, project_id) do
    unless_invoiced(entry, fn ->
      entry
      |> TimeEntry.edit_changeset(%{project_id: project_id})
      |> validate_bookable_project()
      |> Repo.update()
    end)
  end

  @doc """
  Books the whole running entry to another project (or to none with `nil`).
  Fails with `{:error, :not_clocked_in}` when it was clocked out elsewhere in
  the meantime.
  """
  def rebook_running(%TimeEntry{} = entry, project_id) do
    while_running(entry, fn running ->
      running
      |> TimeEntry.edit_changeset(%{project_id: project_id})
      |> validate_bookable_project()
      |> Repo.update()
    end)
  end

  @doc """
  Clocks the running entry out now and clocks in again on `project_id` (or on
  no project with `nil`), so the time worked so far stays on the old project.
  Returns the new running entry.
  """
  def switch_project(%TimeEntry{} = entry, project_id) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    new_entry =
      %TimeEntry{}
      |> TimeEntry.changeset(%{user_id: entry.user_id, project_id: project_id, clock_in: now})
      |> validate_bookable_project()

    while_running(entry, fn running ->
      with {:ok, _previous} <-
             running |> TimeEntry.clock_out_changeset(%{clock_out: now}) |> Repo.update() do
        Repo.insert(new_entry)
      end
    end)
  end

  @doc """
  Clocks the entry out now. Fails with `{:error, :not_clocked_in}` when it was
  clocked out elsewhere in the meantime.
  """
  def clock_out(%TimeEntry{} = entry) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    while_running(entry, fn running ->
      running |> TimeEntry.clock_out_changeset(%{clock_out: now}) |> Repo.update()
    end)
  end

  # Re-reads the entry under a row lock and runs `change` only while it is
  # still running, so a stale page can never overwrite a clock-out made
  # elsewhere. A running entry is never on an invoice.
  defp while_running(%TimeEntry{id: id}, change) do
    Repo.transaction(fn ->
      running =
        Repo.one(
          from e in TimeEntry, where: e.id == ^id and is_nil(e.clock_out), lock: "FOR UPDATE"
        )

      if running do
        case change.(running) do
          {:ok, result} -> result
          {:error, reason} -> Repo.rollback(reason)
        end
      else
        Repo.rollback(:not_clocked_in)
      end
    end)
  end

  @doc """
  Updates an entry from its edit form. `"clock_in"` and `"clock_out"` are
  wall-clock times in the app's time zone as `datetime-local` inputs send
  them (see `PotionZeitgeist.LocalTime.parse_input/3`); an empty clock-out
  leaves the entry running. Returns what `update_entry/2` returns, or
  `{:error, changeset}` for a time that cannot be read or does not exist.
  """
  def update_entry_from_form(%TimeEntry{} = entry, params) do
    clock_in = LocalTime.parse_input(params["clock_in"], entry.clock_in)

    not_before =
      case clock_in do
        {:ok, %NaiveDateTime{} = time} -> time
        _ -> entry.clock_in
      end

    clock_out =
      LocalTime.parse_input(params["clock_out"], entry.clock_out, not_before: not_before)

    case {clock_in, clock_out} do
      {{:ok, clock_in}, {:ok, clock_out}} ->
        update_entry(
          entry,
          Map.merge(params, %{"clock_in" => clock_in, "clock_out" => clock_out})
        )

      _ ->
        changeset =
          entry
          |> change_entry(Map.drop(params, ["clock_in", "clock_out"]))
          |> add_time_error(:clock_in, clock_in)
          |> add_time_error(:clock_out, clock_out)

        {:error, %{changeset | action: :update}}
    end
  end

  defp add_time_error(changeset, field, {:error, message}),
    do: Ecto.Changeset.add_error(changeset, field, message)

  defp add_time_error(changeset, _field, _result), do: changeset

  @doc """
  Updates an entry. Entries on a draft or issued invoice cannot be changed and
  return `{:error, :invoiced}`.
  """
  def update_entry(%TimeEntry{} = entry, attrs) do
    unless_invoiced(entry, fn ->
      entry
      |> TimeEntry.edit_changeset(attrs)
      |> validate_bookable_project()
      |> Repo.update()
    end)
  end

  # New bookings may only go to active projects. Keeping the project an entry
  # already has is allowed even after that project was archived.
  defp validate_bookable_project(changeset) do
    case Ecto.Changeset.get_change(changeset, :project_id) do
      nil ->
        changeset

      project_id ->
        if Projects.get_active_project(project_id) do
          changeset
        else
          Ecto.Changeset.add_error(changeset, :project_id, "is not an active project")
        end
    end
  end

  @doc """
  Deletes an entry, unless it is on a draft or issued invoice
  (`{:error, :invoiced}`).
  """
  def delete_entry(%TimeEntry{} = entry) do
    unless_invoiced(entry, fn -> Repo.delete(entry) end)
  end

  # Billed time must keep matching its invoice. Cancelling the invoice (or
  # deleting the draft) unlocks the entry again. The row lock waits for an
  # invoice that is being saved with this entry right now.
  defp unless_invoiced(%TimeEntry{id: id}, change) do
    Repo.transaction(fn ->
      Repo.one(from e in TimeEntry, where: e.id == ^id, lock: "FOR UPDATE", select: e.id)

      if Invoicing.entry_invoiced?(id) do
        Repo.rollback(:invoiced)
      else
        case change.() do
          {:ok, result} -> result
          {:error, reason} -> Repo.rollback(reason)
        end
      end
    end)
  end

  def change_entry(%TimeEntry{} = entry, attrs \\ %{}) do
    TimeEntry.edit_changeset(entry, attrs)
  end

  ## Flat hours

  @doc """
  Flat hours of a user (see `PotionZeitgeist.TimeTracking.FlatBooking`),
  newest month first, with `invoiced` set for those on a draft or issued
  invoice.
  """
  def list_flat_bookings(user_id) do
    Repo.all(
      from b in FlatBooking,
        left_join: ie in InvoiceEntry,
        on: ie.flat_booking_id == b.id and ie.active,
        where: b.user_id == ^user_id,
        order_by: [desc: b.month, desc: b.id],
        select_merge: %{invoiced: not is_nil(ie.id)},
        preload: [:project]
    )
  end

  @doc "Flat hours of the user, or `nil` when they do not exist (any more)."
  def get_flat_booking(id, user_id) do
    case Repo.get_by(FlatBooking, id: id, user_id: user_id) do
      nil -> nil
      booking -> Repo.preload(booking, :project)
    end
  end

  @doc "Books flat hours for the user, to an active project or to none."
  def create_flat_booking(user_id, attrs) do
    %FlatBooking{user_id: user_id}
    |> FlatBooking.changeset(attrs)
    |> validate_bookable_project()
    |> Repo.insert()
  end

  @doc """
  Updates flat hours. Those on a draft or issued invoice cannot be changed
  and return `{:error, :invoiced}`, those deleted in the meantime
  `{:error, :not_found}`.
  """
  def update_flat_booking(%FlatBooking{} = booking, attrs) do
    unless_booking_invoiced(booking, fn current ->
      current
      |> FlatBooking.changeset(attrs)
      |> validate_bookable_project()
      |> Repo.update()
    end)
  end

  @doc """
  Deletes flat hours, unless they are on a draft or issued invoice
  (`{:error, :invoiced}`). Returns `{:error, :not_found}` when they were
  deleted already.
  """
  def delete_flat_booking(%FlatBooking{} = booking) do
    unless_booking_invoiced(booking, &Repo.delete/1)
  end

  def change_flat_booking(%FlatBooking{} = booking, attrs \\ %{}) do
    FlatBooking.changeset(booking, attrs)
  end

  # As `unless_invoiced/2` for time entries: the row lock waits for an
  # invoice that is being saved with these flat hours right now. `change`
  # gets the flat hours as they are now.
  defp unless_booking_invoiced(%FlatBooking{id: id}, change) do
    Repo.transaction(fn ->
      current = Repo.one(from b in FlatBooking, where: b.id == ^id, lock: "FOR UPDATE")

      cond do
        is_nil(current) ->
          Repo.rollback(:not_found)

        Invoicing.booking_invoiced?(id) ->
          Repo.rollback(:invoiced)

        true ->
          case change.(current) do
            {:ok, result} -> result
            {:error, reason} -> Repo.rollback(reason)
          end
      end
    end)
  end

  @doc """
  Seconds worked today (in the app's time zone) by the user, including the
  running entry so far.
  """
  def today_total_seconds(user_id) do
    entries = list_entries_for_date(user_id, LocalTime.today())
    now = NaiveDateTime.utc_now()

    Enum.reduce(entries, 0, fn entry, acc ->
      finish = entry.clock_out || now
      diff = NaiveDateTime.diff(finish, entry.clock_in, :second)
      acc + max(diff, 0)
    end)
  end

  defdelegate format_duration(total_seconds), to: Export

  @doc """
  Daily totals per user and day, split by project when projects exist.
  """
  def generate_daily_csv(entries) do
    Export.daily_csv(entries, Projects.list_projects())
  end

  @doc """
  One row per clock-in/clock-out pair.
  """
  def generate_entries_csv(entries) do
    Export.entries_csv(entries)
  end
end
