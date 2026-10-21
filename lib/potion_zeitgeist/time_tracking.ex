defmodule PotionZeitgeist.TimeTracking do
  import Ecto.Query

  alias PotionZeitgeist.{Invoicing, Projects, Repo}
  alias PotionZeitgeist.Invoicing.InvoiceEntry
  alias PotionZeitgeist.TimeTracking.{Export, TimeEntry}

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
