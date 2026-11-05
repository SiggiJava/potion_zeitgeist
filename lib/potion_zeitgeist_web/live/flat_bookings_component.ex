defmodule PotionZeitgeistWeb.FlatBookingsComponent do
  @moduledoc """
  The flat hours of one user (see `PotionZeitgeist.TimeTracking.FlatBooking`)
  on an entries page: a list, and a form to book, change and delete them.
  Users book their own flat hours under My Entries, administrators those of
  any user on that user's entries page. Flat hours on a draft or issued
  invoice are locked like time entries.

  A component's flash only shows after navigating, so messages for the
  page's flash are sent to the parent LiveView as
  `{PotionZeitgeistWeb.FlatBookingsComponent, {:flash, kind, message}}`.
  """
  use PotionZeitgeistWeb, :live_component

  alias PotionZeitgeist.{Invoicing, Projects, TimeTracking}
  alias PotionZeitgeist.Invoicing.Format
  alias PotionZeitgeist.TimeTracking.FlatBooking

  # Months the form offers before the current one.
  @past_months 24

  @impl true
  def update(assigns, socket) do
    reload? = socket.assigns[:user_id] != assigns.user_id

    socket =
      socket
      |> assign(assigns)
      |> assign_new(:form, fn -> nil end)
      |> assign_new(:editing, fn -> nil end)
      |> assign_new(:projects, fn -> [] end)
      |> assign_new(:month_options, fn -> [] end)
      |> assign_new(:confirm_delete_id, fn -> nil end)

    {:ok, if(reload?, do: load(socket), else: socket)}
  end

  @impl true
  def handle_event("new", _params, socket) do
    today = Invoicing.today()
    month = today |> Date.beginning_of_month() |> Date.add(-1) |> Date.beginning_of_month()

    {:noreply,
     socket
     |> assign(:editing, nil)
     |> assign(:confirm_delete_id, nil)
     |> assign(:projects, Projects.list_bookable_projects())
     |> assign(:month_options, month_options(today, nil))
     |> assign_form(TimeTracking.change_flat_booking(%FlatBooking{month: month}))}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    case TimeTracking.get_flat_booking(id, socket.assigns.user_id) do
      nil ->
        {:noreply, socket |> load() |> flash(:error, "These flat hours were deleted.")}

      booking ->
        if Invoicing.booking_invoiced?(booking.id) do
          {:noreply, socket |> load() |> flash(:error, socket.assigns.invoiced_message)}
        else
          {:noreply,
           socket
           |> assign(:editing, booking)
           |> assign(:confirm_delete_id, nil)
           |> assign(:projects, Projects.list_bookable_projects(booking.project_id))
           |> assign(:month_options, month_options(Invoicing.today(), booking.month))
           |> assign_form(TimeTracking.change_flat_booking(booking))}
        end
    end
  end

  def handle_event("validate", %{"flat_booking" => params}, socket) do
    changeset =
      (socket.assigns.editing || %FlatBooking{})
      |> TimeTracking.change_flat_booking(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"flat_booking" => params}, socket) do
    result =
      case socket.assigns.editing do
        nil -> TimeTracking.create_flat_booking(socket.assigns.user_id, params)
        booking -> TimeTracking.update_flat_booking(booking, params)
      end

    case result do
      {:ok, _booking} ->
        message = if socket.assigns.editing, do: "Flat hours updated.", else: "Flat hours booked."
        {:noreply, socket |> close_form() |> load() |> flash(:info, message)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, :invoiced} ->
        {:noreply,
         socket |> close_form() |> load() |> flash(:error, socket.assigns.invoiced_message)}

      {:error, :not_found} ->
        {:noreply,
         socket |> close_form() |> load() |> flash(:error, "These flat hours were deleted.")}
    end
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, close_form(socket)}
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm_delete_id, id)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :confirm_delete_id, nil)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    result =
      case TimeTracking.get_flat_booking(id, socket.assigns.user_id) do
        nil -> {:error, :not_found}
        booking -> TimeTracking.delete_flat_booking(booking)
      end

    socket = socket |> assign(:confirm_delete_id, nil) |> load()

    case result do
      {:ok, _booking} -> {:noreply, flash(socket, :info, "Flat hours deleted.")}
      {:error, :invoiced} -> {:noreply, flash(socket, :error, socket.assigns.invoiced_message)}
      {:error, _reason} -> {:noreply, flash(socket, :error, "These flat hours were deleted.")}
    end
  end

  defp load(socket) do
    assign(socket, :bookings, TimeTracking.list_flat_bookings(socket.assigns.user_id))
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: :flat_booking))
  end

  defp close_form(socket) do
    socket |> assign(:form, nil) |> assign(:editing, nil)
  end

  defp flash(socket, kind, message) do
    send(self(), {__MODULE__, {:flash, kind, message}})
    socket
  end

  # The next month, the current one and the `@past_months` before it,
  # newest first, plus the month of the flat hours being changed.
  defp month_options(today, current) do
    next = add_months(Date.beginning_of_month(today), 1)
    months = for n <- 0..(@past_months + 1), do: add_months(next, -n)

    months =
      if current && current not in months,
        do: Enum.sort([current | months], {:desc, Date}),
        else: months

    Enum.map(months, &{Calendar.strftime(&1, "%B %Y"), Date.to_iso8601(&1)})
  end

  defp add_months(%Date{year: year, month: month}, count) do
    index = year * 12 + month - 1 + count
    Date.new!(div(index, 12), rem(index, 12) + 1, 1)
  end

  # The project select compares project ids, which the form sends as text.
  defp selected_project(form) do
    case form[:project_id].value do
      id when is_integer(id) ->
        id

      id when is_binary(id) ->
        case Integer.parse(id) do
          {id, ""} -> id
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp project_errors(form) do
    if Phoenix.Component.used_input?(form[:project_id]),
      do: Enum.map(form[:project_id].errors, &translate_error/1),
      else: []
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="card bg-base-100 shadow">
      <div class="card-body gap-3">
        <div class="flex items-start justify-between flex-wrap gap-3">
          <div class="min-w-0 max-w-2xl">
            <h2 class="card-title text-base">Flat hours</h2>
            <p class="text-sm text-base-content/60">
              For time recorded elsewhere, such as with a client's time clock: book the hours
              of a month at once instead of clocking them again. Invoices bill them like time
              entries of the project; the daily totals export leaves them out.
            </p>
          </div>
          <button
            :if={!@form}
            id="new-flat-booking"
            type="button"
            phx-click="new"
            phx-target={@myself}
            class="btn btn-outline btn-sm gap-2"
          >
            <.icon name="hero-plus" class="size-4" /> Book flat hours
          </button>
        </div>

        <.form
          :if={@form}
          for={@form}
          id="flat-booking-form"
          phx-change="validate"
          phx-submit="save"
          phx-target={@myself}
          class="rounded-box border border-base-300 p-3"
        >
          <h3 class="font-semibold mb-2">
            {if @editing, do: "Change flat hours", else: "Book flat hours"}
          </h3>
          <div class="grid gap-x-4 sm:grid-cols-2">
            <.input
              field={@form[:month]}
              id="flat-booking-month"
              type="select"
              label="Month"
              options={@month_options}
            />
            <div :if={@projects != []} class="fieldset mb-2">
              <label for="flat-booking-project">
                <span class="label mb-1">Project</span>
                <.project_select
                  id="flat-booking-project"
                  name={@form[:project_id].name}
                  projects={@projects}
                  selected={selected_project(@form)}
                  class="w-full select"
                />
              </label>
              <p :for={message <- project_errors(@form)} class="mt-1.5 text-sm text-error">
                {message}
              </p>
            </div>
            <.input
              field={@form[:hours]}
              id="flat-booking-hours"
              label="Hours"
              inputmode="decimal"
              placeholder="e.g. 120 or 120:30"
              phx-debounce="300"
            />
            <.input
              field={@form[:notes]}
              id="flat-booking-notes"
              label="Notes (optional, printed on the time sheet)"
              placeholder="e.g. as recorded by the client's time clock"
              phx-debounce="300"
            />
          </div>
          <div class="flex gap-2 justify-end">
            <button
              type="button"
              id="cancel-flat-booking"
              phx-click="cancel"
              phx-target={@myself}
              class="btn btn-ghost btn-sm"
            >
              Cancel
            </button>
            <button
              type="submit"
              id="save-flat-booking"
              class="btn btn-primary btn-sm"
              phx-disable-with="Saving..."
            >
              {if @editing, do: "Save changes", else: "Book hours"}
            </button>
          </div>
        </.form>

        <div :if={@bookings != []} class="overflow-x-auto">
          <table id="flat-bookings" class="table table-sm w-full">
            <thead>
              <tr>
                <th>Month</th>
                <th>Hours</th>
                <th>Project</th>
                <th>Notes</th>
                <th class="text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={booking <- @bookings} id={"flat-booking-#{booking.id}"}>
                <td class="font-medium whitespace-nowrap">
                  {Calendar.strftime(booking.month, "%B %Y")}
                </td>
                <td class="font-mono text-sm whitespace-nowrap">
                  {Format.duration(booking.minutes)} h
                </td>
                <td class="text-sm">
                  <%= if booking.project do %>
                    <span class="badge badge-ghost badge-sm">{booking.project.name}</span>
                  <% else %>
                    <span class="text-base-content/40">-</span>
                  <% end %>
                </td>
                <td class="text-sm text-base-content/70 max-w-xs truncate">
                  {booking.notes || ""}
                </td>
                <td class="text-right">
                  <div class="flex gap-2 justify-end">
                    <%= cond do %>
                      <% booking.invoiced -> %>
                        <span
                          class="badge badge-info badge-sm gap-1"
                          title="On an invoice, so they can no longer be changed"
                        >
                          <.icon name="hero-lock-closed" class="size-3" /> Invoiced
                        </span>
                      <% @confirm_delete_id == to_string(booking.id) -> %>
                        <span class="text-sm text-error font-medium self-center">Delete?</span>
                        <button
                          id={"delete-flat-booking-#{booking.id}"}
                          phx-click="delete"
                          phx-value-id={booking.id}
                          phx-target={@myself}
                          class="btn btn-error btn-xs"
                        >
                          Yes
                        </button>
                        <button
                          phx-click="cancel_delete"
                          phx-target={@myself}
                          class="btn btn-ghost btn-xs"
                        >
                          No
                        </button>
                      <% true -> %>
                        <button
                          id={"edit-flat-booking-#{booking.id}"}
                          phx-click="edit"
                          phx-value-id={booking.id}
                          phx-target={@myself}
                          class="btn btn-ghost btn-xs gap-1"
                        >
                          <.icon name="hero-pencil" class="size-3" /> Edit
                        </button>
                        <button
                          id={"confirm-delete-flat-booking-#{booking.id}"}
                          phx-click="confirm_delete"
                          phx-value-id={booking.id}
                          phx-target={@myself}
                          class="btn btn-ghost btn-xs text-error gap-1"
                        >
                          <.icon name="hero-trash" class="size-3" /> Delete
                        </button>
                    <% end %>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </section>
    """
  end
end
