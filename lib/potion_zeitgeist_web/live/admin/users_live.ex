defmodule PotionZeitgeistWeb.Admin.UsersLive do
  use PotionZeitgeistWeb, :live_view

  alias PotionZeitgeist.Accounts
  alias PotionZeitgeist.Accounts.User

  on_mount {PotionZeitgeistWeb.UserAuth, :ensure_admin}

  @impl true
  def mount(_params, _session, socket) do
    users = Accounts.list_users()

    {:ok,
     socket
     |> assign(:page_title, "User Management")
     |> assign(:users, users)
     |> assign(:show_create_modal, false)
     |> assign(:create_changeset, Accounts.change_user(%User{}))
     |> assign(:editing_user, nil)
     |> assign(:edit_changeset, nil)
     |> assign(:confirm_delete_id, nil)}
  end

  @impl true
  def handle_event("show_create", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_create_modal, true)
     |> assign(:create_changeset, Accounts.change_user(%User{}))}
  end

  @impl true
  def handle_event("cancel_create", _params, socket) do
    {:noreply, assign(socket, :show_create_modal, false)}
  end

  @impl true
  def handle_event("create_user", %{"user" => params}, socket) do
    case Accounts.create_user(params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> assign(:users, Accounts.list_users())
         |> assign(:show_create_modal, false)
         |> put_flash(:info, "User created successfully.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :create_changeset, changeset)}
    end
  end

  @impl true
  def handle_event("edit_user", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)
    changeset = Accounts.change_user_update(user)

    {:noreply,
     socket
     |> assign(:editing_user, user)
     |> assign(:edit_changeset, changeset)}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_user, nil)
     |> assign(:edit_changeset, nil)}
  end

  @impl true
  def handle_event("save_edit", %{"user" => params}, socket) do
    user = socket.assigns.editing_user

    case Accounts.update_user(user, params) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> assign(:users, Accounts.list_users())
         |> assign(:editing_user, nil)
         |> assign(:edit_changeset, nil)
         |> put_flash(:info, "User updated.")}

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
  def handle_event("delete_user", %{"id" => id}, socket) do
    current_user = socket.assigns.current_user

    if String.to_integer(id) == current_user.id do
      {:noreply, put_flash(socket, :error, "You cannot delete your own account.")}
    else
      user = Accounts.get_user!(id)

      case Accounts.delete_user(user) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:users, Accounts.list_users())
           |> assign(:confirm_delete_id, nil)
           |> put_flash(:info, "User deleted.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not delete user.")}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between flex-wrap gap-3">
        <h1 class="text-2xl font-bold">User Management</h1>
        <div class="flex gap-2 flex-wrap">
          <a
            id="export-all-daily"
            href={~p"/export/all"}
            class="btn btn-outline btn-sm gap-2"
            title="Daily totals of all users, split by project"
          >
            <.icon name="hero-arrow-down-tray" class="size-4" /> Export all daily totals
          </a>
          <button phx-click="show_create" class="btn btn-primary btn-sm gap-2">
            <.icon name="hero-user-plus" class="size-4" /> New User
          </button>
        </div>
      </div>

      <div class="card bg-base-100 shadow overflow-x-auto">
        <table class="table w-full">
          <thead>
            <tr>
              <th>Name</th>
              <th>Email</th>
              <th>Role</th>
              <th>Status</th>
              <th>Created</th>
              <th class="text-right">Actions</th>
            </tr>
          </thead>
          <tbody>
            <%= for user <- @users do %>
              <tr class={if !user.active, do: "opacity-50"}>
                <td class="font-medium">{user.name}</td>
                <td class="text-sm">{user.email}</td>
                <td>
                  <span class={"badge badge-sm #{if user.role == "admin", do: "badge-primary", else: "badge-ghost"}"}>
                    {user.role}
                  </span>
                </td>
                <td>
                  <span class={"badge badge-sm #{if user.active, do: "badge-success", else: "badge-error"}"}>
                    {if user.active, do: "Active", else: "Inactive"}
                  </span>
                </td>
                <td class="text-sm text-base-content/60">
                  {Calendar.strftime(user.inserted_at, "%Y-%m-%d")}
                </td>
                <td class="text-right">
                  <div class="flex gap-1 justify-end flex-wrap">
                    <.link
                      navigate={~p"/admin/users/#{user.id}/entries"}
                      class="btn btn-ghost btn-xs gap-1"
                    >
                      <.icon name="hero-clock" class="size-3" /> Entries
                    </.link>
                    <a
                      href={~p"/export/users/#{user.id}/entries"}
                      class="btn btn-ghost btn-xs gap-1"
                    >
                      <.icon name="hero-arrow-down-tray" class="size-3" /> Export
                    </a>
                    <button
                      phx-click="edit_user"
                      phx-value-id={user.id}
                      class="btn btn-ghost btn-xs gap-1"
                    >
                      <.icon name="hero-pencil" class="size-3" /> Edit
                    </button>
                    <%= if @confirm_delete_id == user.id do %>
                      <span class="text-error text-xs self-center font-medium">Delete?</span>
                      <button
                        phx-click="delete_user"
                        phx-value-id={user.id}
                        class="btn btn-error btn-xs"
                      >
                        Yes
                      </button>
                      <button phx-click="cancel_delete" class="btn btn-ghost btn-xs">No</button>
                    <% else %>
                      <button
                        phx-click="confirm_delete"
                        phx-value-id={user.id}
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

      <% # Create User Modal %>
      <%= if @show_create_modal do %>
        <div class="modal modal-open">
          <div class="modal-box">
            <h3 class="font-bold text-lg mb-4">Create New User</h3>
            <.form :let={f} for={@create_changeset} phx-submit="create_user">
              <div class="form-control mb-4">
                <label class="label">
                  <span class="label-text font-medium">Full Name</span>
                </label>
                <input
                  type="text"
                  name={f[:name].name}
                  class="input input-bordered w-full"
                  placeholder="Jane Doe"
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
                  <span class="label-text font-medium">Email</span>
                </label>
                <input
                  type="email"
                  name={f[:email].name}
                  class="input input-bordered w-full"
                  placeholder="user@example.com"
                  required
                />
                <%= if error = List.first(f[:email].errors) do %>
                  <label class="label">
                    <span class="label-text-alt text-error">{translate_error(error)}</span>
                  </label>
                <% end %>
              </div>

              <div class="form-control mb-4">
                <label class="label">
                  <span class="label-text font-medium">Password</span>
                </label>
                <input
                  type="password"
                  name={f[:password].name}
                  class="input input-bordered w-full"
                  placeholder="Min. 8 characters"
                  required
                />
                <%= if error = List.first(f[:password].errors) do %>
                  <label class="label">
                    <span class="label-text-alt text-error">{translate_error(error)}</span>
                  </label>
                <% end %>
              </div>

              <div class="form-control mb-6">
                <label class="label">
                  <span class="label-text font-medium">Role</span>
                </label>
                <select name={f[:role].name} class="select select-bordered w-full">
                  <option value="user">User</option>
                  <option value="admin">Admin</option>
                </select>
              </div>

              <div class="modal-action">
                <button type="button" phx-click="cancel_create" class="btn btn-ghost">
                  Cancel
                </button>
                <button type="submit" class="btn btn-primary">Create User</button>
              </div>
            </.form>
          </div>
          <div class="modal-backdrop" phx-click="cancel_create"></div>
        </div>
      <% end %>

      <% # Edit User Modal %>
      <%= if @editing_user do %>
        <div class="modal modal-open">
          <div class="modal-box">
            <h3 class="font-bold text-lg mb-4">Edit User</h3>
            <.form :let={f} for={@edit_changeset} phx-submit="save_edit">
              <div class="form-control mb-4">
                <label class="label">
                  <span class="label-text font-medium">Full Name</span>
                </label>
                <input
                  type="text"
                  name={f[:name].name}
                  value={@editing_user.name}
                  class="input input-bordered w-full"
                  required
                />
              </div>

              <div class="form-control mb-4">
                <label class="label">
                  <span class="label-text font-medium">Email</span>
                </label>
                <input
                  type="email"
                  name={f[:email].name}
                  value={@editing_user.email}
                  class="input input-bordered w-full"
                  required
                />
                <%= if error = List.first(f[:email].errors) do %>
                  <label class="label">
                    <span class="label-text-alt text-error">{translate_error(error)}</span>
                  </label>
                <% end %>
              </div>

              <div class="form-control mb-4">
                <label class="label">
                  <span class="label-text font-medium">Role</span>
                </label>
                <select name={f[:role].name} class="select select-bordered w-full">
                  <option value="user" selected={@editing_user.role == "user"}>User</option>
                  <option value="admin" selected={@editing_user.role == "admin"}>Admin</option>
                </select>
              </div>

              <div class="form-control mb-6">
                <label class="cursor-pointer label">
                  <span class="label-text font-medium">Active</span>
                  <input type="hidden" name={f[:active].name} value="false" />
                  <input
                    type="checkbox"
                    name={f[:active].name}
                    value="true"
                    checked={@editing_user.active}
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
