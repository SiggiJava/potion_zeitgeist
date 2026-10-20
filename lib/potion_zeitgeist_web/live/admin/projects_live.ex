defmodule PotionZeitgeistWeb.Admin.ProjectsLive do
  use PotionZeitgeistWeb, :live_view

  alias PotionZeitgeist.Projects
  alias PotionZeitgeist.Projects.Project

  on_mount {PotionZeitgeistWeb.UserAuth, :ensure_admin}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Projects")
     |> assign(:projects, Projects.list_projects())
     |> assign(:show_create_modal, false)
     |> assign(:create_changeset, Projects.change_project(%Project{}))
     |> assign(:editing_project, nil)
     |> assign(:edit_changeset, nil)
     |> assign(:confirm_delete_id, nil)}
  end

  @impl true
  def handle_event("show_create", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_create_modal, true)
     |> assign(:create_changeset, Projects.change_project(%Project{}))}
  end

  @impl true
  def handle_event("cancel_create", _params, socket) do
    {:noreply, assign(socket, :show_create_modal, false)}
  end

  @impl true
  def handle_event("create_project", %{"project" => params}, socket) do
    case Projects.create_project(params) do
      {:ok, _project} ->
        {:noreply,
         socket
         |> assign(:projects, Projects.list_projects())
         |> assign(:show_create_modal, false)
         |> put_flash(:info, "Project created.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :create_changeset, changeset)}
    end
  end

  @impl true
  def handle_event("edit_project", %{"id" => id}, socket) do
    project = Projects.get_project!(id)

    {:noreply,
     socket
     |> assign(:editing_project, project)
     |> assign(:edit_changeset, Projects.change_project(project))}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_project, nil)
     |> assign(:edit_changeset, nil)}
  end

  @impl true
  def handle_event("save_edit", %{"project" => params}, socket) do
    case Projects.update_project(socket.assigns.editing_project, params) do
      {:ok, _project} ->
        {:noreply,
         socket
         |> assign(:projects, Projects.list_projects())
         |> assign(:editing_project, nil)
         |> assign(:edit_changeset, nil)
         |> put_flash(:info, "Project updated.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :edit_changeset, changeset)}
    end
  end

  @impl true
  def handle_event("toggle_active", %{"id" => id}, socket) do
    project = Projects.get_project!(id)

    case Projects.update_project(project, %{active: !project.active}) do
      {:ok, updated} ->
        message = if updated.active, do: "Project reactivated.", else: "Project archived."

        {:noreply,
         socket
         |> assign(:projects, Projects.list_projects())
         |> put_flash(:info, message)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update project.")}
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
  def handle_event("delete_project", %{"id" => id}, socket) do
    project = Projects.get_project!(id)

    case Projects.delete_project(project) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:projects, Projects.list_projects())
         |> assign(:confirm_delete_id, nil)
         |> put_flash(:info, "Project deleted.")}

      {:error, :has_entries} ->
        {:noreply,
         socket
         |> assign(:confirm_delete_id, nil)
         |> put_flash(
           :error,
           "This project already has booked time. Archive it instead to keep the records."
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete project.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 class="text-2xl font-bold">Projects</h1>
          <p class="text-sm text-base-content/60">
            All users can book their time to active projects.
          </p>
        </div>
        <button id="new-project" phx-click="show_create" class="btn btn-primary btn-sm gap-2">
          <.icon name="hero-plus" class="size-4" /> New Project
        </button>
      </div>

      <%= if @projects == [] do %>
        <div class="card bg-base-100 shadow">
          <div class="card-body items-center text-center py-16">
            <.icon name="hero-briefcase" class="size-12 text-base-content/30" />
            <p class="text-base-content/60 mt-2">No projects yet.</p>
            <p class="text-sm text-base-content/50">
              Without projects, time is recorded and exported as before.
            </p>
          </div>
        </div>
      <% else %>
        <div class="card bg-base-100 shadow overflow-x-auto">
          <table id="projects" class="table w-full">
            <thead>
              <tr>
                <th>Name</th>
                <th>Description</th>
                <th>Status</th>
                <th class="text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              <%= for project <- @projects do %>
                <tr id={"project-#{project.id}"} class={if !project.active, do: "opacity-50"}>
                  <td class="font-medium">{project.name}</td>
                  <td class="text-sm text-base-content/70 max-w-xs truncate">
                    {project.description || ""}
                  </td>
                  <td>
                    <span class={"badge badge-sm #{if project.active, do: "badge-success", else: "badge-ghost"}"}>
                      {if project.active, do: "Active", else: "Archived"}
                    </span>
                  </td>
                  <td class="text-right">
                    <div class="flex gap-1 justify-end flex-wrap">
                      <button
                        phx-click="edit_project"
                        phx-value-id={project.id}
                        class="btn btn-ghost btn-xs gap-1"
                      >
                        <.icon name="hero-pencil" class="size-3" /> Edit
                      </button>
                      <button
                        phx-click="toggle_active"
                        phx-value-id={project.id}
                        class="btn btn-ghost btn-xs gap-1"
                      >
                        <%= if project.active do %>
                          <.icon name="hero-archive-box" class="size-3" /> Archive
                        <% else %>
                          <.icon name="hero-arrow-uturn-left" class="size-3" /> Reactivate
                        <% end %>
                      </button>
                      <%= if @confirm_delete_id == project.id do %>
                        <span class="text-error text-xs self-center font-medium">Delete?</span>
                        <button
                          phx-click="delete_project"
                          phx-value-id={project.id}
                          class="btn btn-error btn-xs"
                        >
                          Yes
                        </button>
                        <button phx-click="cancel_delete" class="btn btn-ghost btn-xs">No</button>
                      <% else %>
                        <button
                          phx-click="confirm_delete"
                          phx-value-id={project.id}
                          class="btn btn-ghost btn-xs text-error gap-1"
                        >
                          <.icon name="hero-trash" class="size-3" /> Delete
                        </button>
                      <% end %>
                    </div>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>

      <% # Create Project Modal %>
      <%= if @show_create_modal do %>
        <div class="modal modal-open">
          <div class="modal-box">
            <h3 class="font-bold text-lg mb-4">New Project</h3>
            <.form :let={f} for={@create_changeset} id="project-form" phx-submit="create_project">
              <div class="form-control mb-4">
                <label class="label">
                  <span class="label-text font-medium">Name</span>
                </label>
                <input
                  type="text"
                  name={f[:name].name}
                  value={f[:name].value}
                  class="input input-bordered w-full"
                  placeholder="e.g. Customer Portal"
                  required
                />
                <%= if error = List.first(f[:name].errors) do %>
                  <label class="label">
                    <span class="label-text-alt text-error">{translate_error(error)}</span>
                  </label>
                <% end %>
              </div>

              <div class="form-control mb-6">
                <label class="label">
                  <span class="label-text font-medium">Description</span>
                </label>
                <textarea
                  name={f[:description].name}
                  class="textarea textarea-bordered w-full"
                  rows="3"
                  placeholder="Optional"
                >{f[:description].value}</textarea>
              </div>

              <div class="modal-action">
                <button type="button" phx-click="cancel_create" class="btn btn-ghost">
                  Cancel
                </button>
                <button type="submit" class="btn btn-primary">Create Project</button>
              </div>
            </.form>
          </div>
          <div class="modal-backdrop" phx-click="cancel_create"></div>
        </div>
      <% end %>

      <% # Edit Project Modal %>
      <%= if @editing_project do %>
        <div class="modal modal-open">
          <div class="modal-box">
            <h3 class="font-bold text-lg mb-4">Edit Project</h3>
            <.form :let={f} for={@edit_changeset} id="edit-project-form" phx-submit="save_edit">
              <div class="form-control mb-4">
                <label class="label">
                  <span class="label-text font-medium">Name</span>
                </label>
                <input
                  type="text"
                  name={f[:name].name}
                  value={f[:name].value}
                  class="input input-bordered w-full"
                  required
                />
                <%= if error = List.first(f[:name].errors) do %>
                  <label class="label">
                    <span class="label-text-alt text-error">{translate_error(error)}</span>
                  </label>
                <% end %>
              </div>

              <div class="form-control mb-4">
                <label class="label">
                  <span class="label-text font-medium">Description</span>
                </label>
                <textarea
                  name={f[:description].name}
                  class="textarea textarea-bordered w-full"
                  rows="3"
                >{f[:description].value}</textarea>
              </div>

              <div class="form-control mb-6">
                <label class="cursor-pointer label">
                  <span class="label-text font-medium">Active</span>
                  <input type="hidden" name={f[:active].name} value="false" />
                  <input
                    type="checkbox"
                    name={f[:active].name}
                    value="true"
                    checked={@editing_project.active}
                    class="toggle toggle-success"
                  />
                </label>
              </div>

              <div class="modal-action">
                <button type="button" phx-click="cancel_edit" class="btn btn-ghost">Cancel</button>
                <button type="submit" class="btn btn-primary">Save</button>
              </div>
            </.form>
          </div>
          <div class="modal-backdrop" phx-click="cancel_edit"></div>
        </div>
      <% end %>
    </div>
    """
  end
end
