defmodule PotionZeitgeistWeb.DashboardLive do
  use PotionZeitgeistWeb, :live_view

  alias PotionZeitgeist.TimeTracking

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
  def handle_event("clock_in", _params, socket) do
    user = socket.assigns.current_user

    case TimeTracking.clock_in(user.id) do
      {:ok, entry} ->
        {:noreply,
         socket
         |> assign(:active_entry, entry)
         |> put_flash(:info, "Clocked in successfully.")}

      {:error, :already_clocked_in} ->
        {:noreply, put_flash(socket, :error, "You are already clocked in.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not clock in. Please try again.")}
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
             |> put_flash(:info, "Clocked out successfully.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not clock out. Please try again.")}
        end
    end
  end

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
            <button phx-click="clock_out" class="btn btn-error btn-lg gap-2">
              <.icon name="hero-stop-circle" class="size-6" />
              Clock Out
            </button>
          <% else %>
            <p class="text-base-content/60 text-sm mb-4">
              Press the button to start tracking your time
            </p>
            <button phx-click="clock_in" class="btn btn-success btn-lg gap-2">
              <.icon name="hero-play-circle" class="size-6" />
              Clock In
            </button>
          <% end %>
        </div>
      </div>

      <% # Today's Summary Card %>
      <div class="card bg-base-100 shadow-lg">
        <div class="card-body">
          <h2 class="card-title">
            <.icon name="hero-clock" class="size-5" />
            Today's Summary
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
                {if @active_entry, do: "Clock out to stop tracking", else: "Clock in to start tracking"}
              </div>
            </div>
          </div>
        </div>
      </div>

      <% # Quick Links %>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.link navigate={~p"/entries"} class="card bg-base-100 shadow hover:shadow-md transition-shadow">
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

        <a href={~p"/export/my-entries"} class="card bg-base-100 shadow hover:shadow-md transition-shadow">
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
