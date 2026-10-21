defmodule PotionZeitgeistWeb.TimeEntriesLive do
  use PotionZeitgeistWeb, :live_view

  alias PotionZeitgeist.{Projects, TimeTracking}

  @invoiced_message "This entry is on an invoice and can no longer be changed. Ask an administrator if it needs a correction."

  on_mount {PotionZeitgeistWeb.UserAuth, :ensure_authenticated}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    entries = TimeTracking.list_entries(user.id)

    {:ok,
     socket
     |> assign(:page_title, "My Entries")
     |> assign(:entries, entries)
     |> assign(:editing_entry, nil)
     |> assign(:edit_changeset, nil)
     |> assign(:edit_projects, [])
     |> assign(:confirm_delete_id, nil)}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    entry = TimeTracking.get_entry!(id, user.id)
    changeset = TimeTracking.change_entry(entry)

    {:noreply,
     socket
     |> assign(:editing_entry, entry)
     |> assign(:edit_changeset, changeset)
     |> assign(:edit_projects, Projects.list_bookable_projects(entry.project_id))}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_entry, nil)
     |> assign(:edit_changeset, nil)}
  end

  @impl true
  def handle_event("save_edit", %{"time_entry" => params}, socket) do
    entry = socket.assigns.editing_entry
    params = sanitize_entry_params(params)

    case TimeTracking.update_entry(entry, params) do
      {:ok, _updated} ->
        user = socket.assigns.current_user
        entries = TimeTracking.list_entries(user.id)

        {:noreply,
         socket
         |> assign(:entries, entries)
         |> assign(:editing_entry, nil)
         |> assign(:edit_changeset, nil)
         |> put_flash(:info, "Entry updated.")}

      {:error, :invoiced} ->
        {:noreply,
         socket
         |> assign(:entries, TimeTracking.list_entries(socket.assigns.current_user.id))
         |> assign(:editing_entry, nil)
         |> assign(:edit_changeset, nil)
         |> put_flash(:error, @invoiced_message)}

      {:error, changeset} ->
        {:noreply, assign(socket, :edit_changeset, changeset)}
    end
  end

  @impl true
  def handle_event("confirm_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm_delete_id, String.to_integer(id))}
  end

  @impl true
  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :confirm_delete_id, nil)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    entry = TimeTracking.get_entry!(id, user.id)

    case TimeTracking.delete_entry(entry) do
      {:ok, _} ->
        entries = TimeTracking.list_entries(user.id)

        {:noreply,
         socket
         |> assign(:entries, entries)
         |> assign(:confirm_delete_id, nil)
         |> put_flash(:info, "Entry deleted.")}

      {:error, :invoiced} ->
        {:noreply,
         socket
         |> assign(:entries, TimeTracking.list_entries(user.id))
         |> assign(:confirm_delete_id, nil)
         |> put_flash(:error, @invoiced_message)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete entry.")}
    end
  end

  defp sanitize_entry_params(params) do
    params
    |> Map.update("clock_in", nil, &parse_datetime/1)
    |> Map.update("clock_out", nil, fn
      "" -> nil
      v -> parse_datetime(v)
    end)
  end

  defp parse_datetime(""), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(String.replace(value, "T", " ") <> ":00") do
      {:ok, dt} ->
        dt

      _ ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, dt} -> dt
          _ -> nil
        end
    end
  end

  defp duration_string(nil, _), do: "-"

  defp duration_string(entry, _) when is_nil(entry.clock_out), do: "In progress"

  defp duration_string(entry, _) do
    diff = NaiveDateTime.diff(entry.clock_out, entry.clock_in, :second)
    TimeTracking.format_duration(diff)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between flex-wrap gap-3">
        <h1 class="text-2xl font-bold">My Time Entries</h1>
        <div class="flex gap-2 flex-wrap">
          <a
            id="export-daily"
            href={~p"/export/my-entries"}
            class="btn btn-outline btn-sm gap-2"
            title="One total per day, split by project"
          >
            <.icon name="hero-arrow-down-tray" class="size-4" /> Export daily totals
          </a>
          <a
            id="export-entries"
            href={~p"/export/my-entries?type=entries"}
            class="btn btn-ghost btn-sm gap-2"
            title="Every clock-in/clock-out pair"
          >
            <.icon name="hero-table-cells" class="size-4" /> Export entries
          </a>
        </div>
      </div>

      <%= if @entries == [] do %>
        <div class="card bg-base-100 shadow">
          <div class="card-body items-center text-center py-16">
            <.icon name="hero-clock" class="size-12 text-base-content/30" />
            <p class="text-base-content/60 mt-2">No time entries yet.</p>
            <.link navigate={~p"/"} class="btn btn-primary btn-sm mt-4">
              Go to Dashboard to Clock In
            </.link>
          </div>
        </div>
      <% else %>
        <div class="card bg-base-100 shadow overflow-x-auto">
          <table class="table table-zebra w-full">
            <thead>
              <tr>
                <th>Date</th>
                <th>Clock In</th>
                <th>Clock Out</th>
                <th>Duration</th>
                <th>Project</th>
                <th>Notes</th>
                <th class="text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              <%= for entry <- @entries do %>
                <tr>
                  <td class="font-medium">
                    {NaiveDateTime.to_date(entry.clock_in) |> Date.to_string()}
                  </td>
                  <td class="font-mono text-sm">
                    {Calendar.strftime(entry.clock_in, "%H:%M:%S")}
                  </td>
                  <td class="font-mono text-sm">
                    <%= if entry.clock_out do %>
                      {Calendar.strftime(entry.clock_out, "%H:%M:%S")}
                    <% else %>
                      <span class="badge badge-success badge-sm">Active</span>
                    <% end %>
                  </td>
                  <td class="font-mono text-sm">{duration_string(entry, nil)}</td>
                  <td class="text-sm">
                    <%= if entry.project do %>
                      <span class="badge badge-ghost badge-sm">{entry.project.name}</span>
                    <% else %>
                      <span class="text-base-content/40">-</span>
                    <% end %>
                  </td>
                  <td class="text-sm text-base-content/70 max-w-xs truncate">
                    {entry.notes || ""}
                  </td>
                  <td class="text-right">
                    <div class="flex gap-2 justify-end">
                      <%= if entry.invoiced do %>
                        <span
                          class="badge badge-info badge-sm gap-1"
                          title="On an invoice, so it can no longer be changed"
                        >
                          <.icon name="hero-lock-closed" class="size-3" /> Invoiced
                        </span>
                      <% else %>
                        <%= if @confirm_delete_id == entry.id do %>
                          <span class="text-sm text-error font-medium self-center">Delete?</span>
                          <button
                            phx-click="delete"
                            phx-value-id={entry.id}
                            class="btn btn-error btn-xs"
                          >
                            Yes
                          </button>
                          <button phx-click="cancel_delete" class="btn btn-ghost btn-xs">
                            No
                          </button>
                        <% else %>
                          <button
                            phx-click="edit"
                            phx-value-id={entry.id}
                            class="btn btn-ghost btn-xs gap-1"
                          >
                            <.icon name="hero-pencil" class="size-3" /> Edit
                          </button>
                          <button
                            phx-click="confirm_delete"
                            phx-value-id={entry.id}
                            class="btn btn-ghost btn-xs text-error gap-1"
                          >
                            <.icon name="hero-trash" class="size-3" /> Delete
                          </button>
                        <% end %>
                      <% end %>
                    </div>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>

      <% # Edit Modal %>
      <%= if @editing_entry do %>
        <div class="modal modal-open">
          <div class="modal-box">
            <h3 class="font-bold text-lg mb-4">Edit Time Entry</h3>

            <.form :let={f} for={@edit_changeset} phx-submit="save_edit">
              <div class="form-control mb-4">
                <label class="label">
                  <span class="label-text font-medium">Clock In</span>
                </label>
                <input
                  type="datetime-local"
                  name={f[:clock_in].name}
                  value={format_dt_for_input(@editing_entry.clock_in)}
                  class="input input-bordered w-full"
                  required
                />
                <%= if error = List.first(f[:clock_in].errors) do %>
                  <label class="label">
                    <span class="label-text-alt text-error">{translate_error(error)}</span>
                  </label>
                <% end %>
              </div>

              <div class="form-control mb-4">
                <label class="label">
                  <span class="label-text font-medium">Clock Out</span>
                </label>
                <input
                  type="datetime-local"
                  name={f[:clock_out].name}
                  value={
                    if @editing_entry.clock_out,
                      do: format_dt_for_input(@editing_entry.clock_out),
                      else: ""
                  }
                  class="input input-bordered w-full"
                />
                <%= if error = List.first(f[:clock_out].errors) do %>
                  <label class="label">
                    <span class="label-text-alt text-error">{translate_error(error)}</span>
                  </label>
                <% end %>
              </div>

              <%= if @edit_projects != [] do %>
                <div class="form-control mb-4">
                  <label class="label" for="edit-entry-project">
                    <span class="label-text font-medium">Project</span>
                  </label>
                  <.project_select
                    id="edit-entry-project"
                    name={f[:project_id].name}
                    projects={@edit_projects}
                    selected={@editing_entry.project_id}
                  />
                  <%= if error = List.first(f[:project_id].errors) do %>
                    <label class="label">
                      <span class="label-text-alt text-error">{translate_error(error)}</span>
                    </label>
                  <% end %>
                </div>
              <% end %>

              <div class="form-control mb-6">
                <label class="label">
                  <span class="label-text font-medium">Notes</span>
                </label>
                <textarea
                  name={f[:notes].name}
                  class="textarea textarea-bordered w-full"
                  rows="3"
                  placeholder="Optional notes..."
                >{@editing_entry.notes}</textarea>
              </div>

              <div class="modal-action">
                <button type="button" phx-click="cancel_edit" class="btn btn-ghost">
                  Cancel
                </button>
                <button type="submit" class="btn btn-primary">Save Changes</button>
              </div>
            </.form>
          </div>
          <div class="modal-backdrop" phx-click="cancel_edit"></div>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_dt_for_input(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%dT%H:%M")
  end

  defp format_dt_for_input(_), do: ""
end
