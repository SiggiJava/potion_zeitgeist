defmodule PotionZeitgeistWeb.DashboardLive do
  use PotionZeitgeistWeb, :live_view

  alias PotionZeitgeist.{Projects, Repo, TimeTracking}

  on_mount {PotionZeitgeistWeb.UserAuth, :ensure_authenticated}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if connected?(socket) do
      :timer.send_interval(1000, self(), :tick)
    end

    active_entry = TimeTracking.get_active_entry(user.id)
    today_seconds = TimeTracking.today_total_seconds(user.id)

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:active_entry, active_entry)
     |> assign(:today_seconds, today_seconds)
     |> assign(:projects, bookable_projects(active_entry))
     |> assign(:project_select_rev, 0)
     |> assign(:project_change, nil)
     |> assign(:now, NaiveDateTime.utc_now())}
  end

  @impl true
  def handle_info(:tick, socket) do
    user = socket.assigns.current_user
    today_seconds = TimeTracking.today_total_seconds(user.id)

    {:noreply,
     socket
     |> assign(:today_seconds, today_seconds)
     |> assign(:now, NaiveDateTime.utc_now())}
  end

  @impl true
  def handle_event("clock_in", params, socket) do
    user = socket.assigns.current_user

    case TimeTracking.clock_in(user.id, blank_to_nil(params["project_id"])) do
      {:ok, entry} ->
        entry = Repo.preload(entry, :project)

        {:noreply,
         socket
         |> assign(:active_entry, entry)
         |> assign(:projects, bookable_projects(entry))
         |> put_flash(:info, "Clocked in successfully.")}

      {:error, :already_clocked_in} ->
        {:noreply, put_flash(socket, :error, "You are already clocked in.")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:projects, bookable_projects(nil))
         |> put_flash(:error, booking_error(changeset, "Could not clock in. Please try again."))}
    end
  end

  @impl true
  def handle_event("clock_out", _params, socket) do
    case socket.assigns.active_entry do
      nil ->
        {:noreply, put_flash(socket, :error, "You are not clocked in.")}

      entry ->
        case TimeTracking.clock_out(entry) do
          {:ok, _} ->
            user = socket.assigns.current_user
            today_seconds = TimeTracking.today_total_seconds(user.id)

            {:noreply,
             socket
             |> assign(:active_entry, nil)
             |> assign(:today_seconds, today_seconds)
             |> assign(:projects, bookable_projects(nil))
             |> put_flash(:info, "Clocked out successfully.")}

          {:error, :not_clocked_in} ->
            {:noreply, reload_after_change_elsewhere(socket, "You were already clocked out.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not clock out. Please try again.")}
        end
    end
  end

  # Picking another project for the running entry asks whether to rebook the
  # whole session or to switch projects from now on (clock out and in again).
  @impl true
  def handle_event("change_project", %{"project_id" => project_id}, socket) do
    entry = socket.assigns.active_entry

    cond do
      is_nil(entry) ->
        {:noreply, put_flash(socket, :error, "You are not clocked in.")}

      project_id == "" ->
        {:noreply, ask_project_change(socket, entry, nil, "No project")}

      project = Enum.find(socket.assigns.projects, &(to_string(&1.id) == project_id)) ->
        {:noreply, ask_project_change(socket, entry, project.id, project.name)}

      true ->
        {:noreply, project_change_failed(socket, nil, "Could not change the project.")}
    end
  end

  @impl true
  def handle_event("rebook_project", _params, socket) do
    %{active_entry: entry, project_change: change} = socket.assigns

    case change && entry && TimeTracking.set_entry_project(entry, change.project_id) do
      {:ok, updated} ->
        updated = Repo.preload(updated, :project, force: true)

        {:noreply,
         socket
         |> assign(:active_entry, updated)
         |> assign(:projects, bookable_projects(updated))
         |> assign(:project_change, nil)
         |> put_flash(:info, "The whole session is now booked to #{change.name}.")}

      error ->
        {:noreply, project_change_failed(socket, error, "Could not rebook the session.")}
    end
  end

  @impl true
  def handle_event("switch_project", _params, socket) do
    %{active_entry: entry, project_change: change} = socket.assigns

    case change && entry && TimeTracking.switch_project(entry, change.project_id) do
      {:ok, new_entry} ->
        new_entry = Repo.preload(new_entry, :project)

        {:noreply,
         socket
         |> assign(:active_entry, new_entry)
         |> assign(:projects, bookable_projects(new_entry))
         |> assign(:project_change, nil)
         |> assign(
           :today_seconds,
           TimeTracking.today_total_seconds(socket.assigns.current_user.id)
         )
         |> put_flash(
           :info,
           "Switched to #{change.name}. The time so far stays on #{project_label(entry)}."
         )}

      error ->
        {:noreply, project_change_failed(socket, error, "Could not switch the project.")}
    end
  end

  @impl true
  def handle_event("cancel_project_change", _params, socket) do
    # Re-render the select so it shows the project the entry is still booked to.
    {:noreply,
     socket
     |> assign(:project_change, nil)
     |> update(:project_select_rev, &(&1 + 1))}
  end

  defp ask_project_change(socket, %{project_id: project_id}, project_id, _name), do: socket

  defp ask_project_change(socket, _entry, project_id, name) do
    assign(socket, :project_change, %{project_id: project_id, name: name})
  end

  # The running entry was clocked out in another tab or on the entries page.
  defp reload_after_change_elsewhere(socket, message) do
    user = socket.assigns.current_user
    active_entry = TimeTracking.get_active_entry(user.id)

    socket
    |> assign(:active_entry, active_entry)
    |> assign(:today_seconds, TimeTracking.today_total_seconds(user.id))
    |> assign(:projects, bookable_projects(active_entry))
    |> put_flash(:error, message)
  end

  # Reloads the running entry, which may have been clocked out or changed
  # elsewhere in the meantime, and re-renders the project select.
  defp project_change_failed(socket, error, fallback) do
    changeset =
      case error do
        {:error, %Ecto.Changeset{} = changeset} -> changeset
        _ -> nil
      end

    active_entry = TimeTracking.get_active_entry(socket.assigns.current_user.id)

    socket
    |> assign(:active_entry, active_entry)
    |> assign(:projects, bookable_projects(active_entry))
    |> assign(:project_change, nil)
    |> update(:project_select_rev, &(&1 + 1))
    |> put_flash(:error, booking_error(changeset, fallback))
  end

  defp project_label(%{project: %{name: name}}), do: name
  defp project_label(_entry), do: "No project"

  defp bookable_projects(nil), do: Projects.list_active_projects()
  defp bookable_projects(entry), do: Projects.list_bookable_projects(entry.project_id)

  defp booking_error(%Ecto.Changeset{errors: errors}, fallback) do
    if Keyword.has_key?(errors, :project_id),
      do: "This project is no longer available. Please pick another one.",
      else: fallback
  end

  defp booking_error(_error, fallback), do: fallback

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp current_session_seconds(nil, _now), do: 0

  defp current_session_seconds(entry, now) do
    NaiveDateTime.diff(now, entry.clock_in, :second) |> max(0)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Dashboard</h1>
        <div class="text-sm text-base-content/60">
          {Calendar.strftime(@now, "%A, %B %d, %Y")}
        </div>
      </div>

      <% # Clock In/Out Card %>
      <div class="card bg-base-100 shadow-lg">
        <div class="card-body items-center text-center">
          <div class={"w-4 h-4 rounded-full mb-2 #{if @active_entry, do: "bg-success animate-pulse", else: "bg-base-300"}"}>
          </div>

          <h2 class="card-title text-xl">
            {if @active_entry, do: "Currently Working", else: "Not Clocked In"}
          </h2>

          <%= if @active_entry do %>
            <p class="text-base-content/60 text-sm">
              Since {Calendar.strftime(@active_entry.clock_in, "%H:%M:%S")}
            </p>
            <div class="text-4xl font-mono font-bold text-success my-4">
              {TimeTracking.format_duration(current_session_seconds(@active_entry, @now))}
            </div>
            <%= if @projects != [] do %>
              <form
                id="active-project-form"
                phx-change="change_project"
                phx-auto-recover="ignore"
                class="w-full max-w-xs mb-4"
              >
                <label class="label justify-center" for={"active-project-#{@project_select_rev}"}>
                  <span class="label-text text-base-content/60">Booked to project</span>
                </label>
                <.project_select
                  id={"active-project-#{@project_select_rev}"}
                  name="project_id"
                  projects={@projects}
                  selected={@active_entry.project_id}
                  class="select select-bordered select-sm w-full"
                />
              </form>
            <% end %>
            <button phx-click="clock_out" class="btn btn-error btn-lg gap-2">
              <.icon name="hero-stop-circle" class="size-6" /> Clock Out
            </button>
          <% else %>
            <p class="text-base-content/60 text-sm mb-4">
              Press the button to start tracking your time
            </p>
            <form id="clock-in-form" phx-submit="clock_in" class="flex flex-col items-center gap-4">
              <%= if @projects != [] do %>
                <div class="w-full max-w-xs">
                  <label class="label justify-center" for="clock-in-project">
                    <span class="label-text text-base-content/60">Project (optional)</span>
                  </label>
                  <.project_select
                    id="clock-in-project"
                    name="project_id"
                    projects={@projects}
                    class="select select-bordered select-sm w-full"
                  />
                </div>
              <% end %>
              <button type="submit" class="btn btn-success btn-lg gap-2">
                <.icon name="hero-play-circle" class="size-6" /> Clock In
              </button>
            </form>
          <% end %>
        </div>
      </div>

      <% # Today's Summary Card %>
      <div class="card bg-base-100 shadow-lg">
        <div class="card-body">
          <h2 class="card-title">
            <.icon name="hero-clock" class="size-5" /> Today's Summary
          </h2>
          <div class="stats stats-vertical sm:stats-horizontal w-full shadow-none">
            <div class="stat">
              <div class="stat-title">Total Time Today</div>
              <div class="stat-value text-primary font-mono">
                {TimeTracking.format_duration(@today_seconds)}
              </div>
              <div class="stat-desc">{Date.utc_today() |> Date.to_string()}</div>
            </div>
            <div class="stat">
              <div class="stat-title">Status</div>
              <div class={"stat-value text-lg #{if @active_entry, do: "text-success", else: "text-base-content/60"}"}>
                {if @active_entry, do: "Active", else: "Inactive"}
              </div>
              <div class="stat-desc">
                {if @active_entry,
                  do: "Clock out to stop tracking",
                  else: "Clock in to start tracking"}
              </div>
            </div>
          </div>
        </div>
      </div>

      <% # Project change dialog %>
      <%= if @project_change && @active_entry do %>
        <div id="project-change-modal" class="modal modal-open">
          <div class="modal-box">
            <h3 class="font-bold text-lg">Change project</h3>
            <p class="text-sm text-base-content/70 mt-2">
              You have been working on
              <span class="font-semibold text-base-content">{project_label(@active_entry)}</span>
              since {Calendar.strftime(@active_entry.clock_in, "%H:%M")}. How should
              <span class="font-semibold text-base-content">{@project_change.name}</span>
              apply?
            </p>

            <div class="grid gap-3 mt-5">
              <button
                id="rebook-project"
                phx-click="rebook_project"
                class="btn btn-outline h-auto py-3 justify-start text-left gap-3"
              >
                <.icon name="hero-arrow-path" class="size-5 shrink-0" />
                <span>
                  <span class="block font-semibold">Rebook</span>
                  <span class="block text-xs font-normal opacity-70">
                    Book the whole session since {Calendar.strftime(@active_entry.clock_in, "%H:%M")} to {@project_change.name}.
                  </span>
                </span>
              </button>
              <button
                id="switch-project"
                phx-click="switch_project"
                class="btn btn-primary h-auto py-3 justify-start text-left gap-3"
              >
                <.icon name="hero-arrows-right-left" class="size-5 shrink-0" />
                <span>
                  <span class="block font-semibold">Switch project</span>
                  <span class="block text-xs font-normal opacity-80">
                    Keep the time until now on {project_label(@active_entry)} and continue on {@project_change.name} from now.
                  </span>
                </span>
              </button>
            </div>

            <div class="modal-action">
              <button
                id="cancel-project-change"
                type="button"
                phx-click="cancel_project_change"
                class="btn btn-ghost"
              >
                Cancel
              </button>
            </div>
          </div>
          <div class="modal-backdrop" phx-click="cancel_project_change"></div>
        </div>
      <% end %>

      <% # Quick Links %>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.link
          navigate={~p"/entries"}
          class="card bg-base-100 shadow hover:shadow-md transition-shadow"
        >
          <div class="card-body flex-row items-center gap-4">
            <div class="rounded-full bg-primary/10 p-3">
              <.icon name="hero-list-bullet" class="size-6 text-primary" />
            </div>
            <div>
              <h3 class="font-semibold">My Entries</h3>
              <p class="text-sm text-base-content/60">View and edit your time log</p>
            </div>
          </div>
        </.link>

        <a
          href={~p"/export/my-entries"}
          class="card bg-base-100 shadow hover:shadow-md transition-shadow"
        >
          <div class="card-body flex-row items-center gap-4">
            <div class="rounded-full bg-secondary/10 p-3">
              <.icon name="hero-arrow-down-tray" class="size-6 text-secondary" />
            </div>
            <div>
              <h3 class="font-semibold">Export My Data</h3>
              <p class="text-sm text-base-content/60">Download as CSV</p>
            </div>
          </div>
        </a>
      </div>
    </div>
    """
  end
end
