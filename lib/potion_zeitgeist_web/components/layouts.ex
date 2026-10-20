defmodule PotionZeitgeistWeb.Layouts do
  use PotionZeitgeistWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_user, :map, default: nil
  attr :inner_content, :any, required: true

  def app(assigns) do
    ~H"""
    <div class="drawer lg:drawer-open min-h-screen">
      <input id="sidebar-drawer" type="checkbox" class="drawer-toggle" />

      <div class="drawer-content flex flex-col">
        <% # Mobile topbar %>
        <div class="navbar bg-base-100 lg:hidden border-b border-base-300 sticky top-0 z-10">
          <div class="flex-none">
            <label for="sidebar-drawer" class="btn btn-ghost drawer-button">
              <.icon name="hero-bars-3" class="size-6" />
            </label>
          </div>
          <div class="flex-1">
            <span class="text-lg font-bold text-primary">Potion Zeitgeist</span>
          </div>
          <.theme_toggle />
        </div>

        <% # Main content %>
        <main class="flex-1 p-4 md:p-6 lg:p-8 max-w-6xl w-full mx-auto">
          <.flash_group flash={@flash} />
          {@inner_content}
        </main>
      </div>

      <% # Sidebar %>
      <div class="drawer-side z-20">
        <label for="sidebar-drawer" class="drawer-overlay"></label>
        <aside class="bg-base-100 border-r border-base-300 min-h-full w-64 flex flex-col">
          <% # Logo %>
          <div class="p-5 border-b border-base-300 flex items-center gap-3">
            <div class="w-8 h-8 rounded-lg bg-primary flex items-center justify-center">
              <.icon name="hero-clock" class="size-5 text-primary-content" />
            </div>
            <div>
              <div class="font-bold text-base leading-tight">Potion Zeitgeist</div>
              <div class="text-xs text-base-content/50">Time Tracking</div>
            </div>
          </div>

          <% # Navigation %>
          <nav class="flex-1 p-3">
            <ul class="menu menu-sm gap-1 p-0">
              <li class="menu-title text-xs uppercase tracking-wider opacity-50 mt-2 mb-1">
                My Workspace
              </li>
              <li>
                <.link navigate="/" class="gap-3 font-medium">
                  <.icon name="hero-home" class="size-4" />
                  Dashboard
                </.link>
              </li>
              <li>
                <.link navigate="/entries" class="gap-3 font-medium">
                  <.icon name="hero-list-bullet" class="size-4" />
                  My Entries
                </.link>
              </li>
              <li>
                <a href="/export/my-entries" class="gap-3 font-medium">
                  <.icon name="hero-arrow-down-tray" class="size-4" />
                  Export My Data
                </a>
              </li>

              <%= if @current_user && @current_user.role == "admin" do %>
                <li class="menu-title text-xs uppercase tracking-wider opacity-50 mt-4 mb-1">
                  Administration
                </li>
                <li>
                  <.link navigate="/admin/users" class="gap-3 font-medium">
                    <.icon name="hero-users" class="size-4" />
                    Users
                  </.link>
                </li>
                <li>
                  <.link navigate="/admin/projects" class="gap-3 font-medium">
                    <.icon name="hero-briefcase" class="size-4" />
                    Projects
                  </.link>
                </li>
              <% end %>
            </ul>
          </nav>

          <% # User info + logout %>
          <div class="p-3 border-t border-base-300">
            <%= if @current_user do %>
              <div class="flex items-center gap-3 p-2 rounded-lg mb-2">
                <div class="bg-primary text-primary-content rounded-full w-8 h-8 flex items-center justify-center shrink-0">
                  <span class="text-xs font-bold leading-none">
                    {String.first(to_string(@current_user.name)) |> String.upcase()}
                  </span>
                </div>
                <div class="flex-1 min-w-0">
                  <div class="font-medium text-sm truncate">{@current_user.name}</div>
                  <div class="text-xs text-base-content/50 truncate">{@current_user.email}</div>
                </div>
                <span class={"badge badge-xs #{if @current_user.role == "admin", do: "badge-primary", else: "badge-ghost"}"}>
                  {@current_user.role}
                </span>
              </div>
              <form action="/logout" method="post" class="w-full">
                <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
                <button
                  type="submit"
                  class="btn btn-ghost btn-sm w-full justify-start gap-3 font-medium"
                >
                  <.icon name="hero-arrow-right-on-rectangle" class="size-4" />
                  Sign Out
                </button>
              </form>
            <% end %>
            <div class="flex justify-center mt-2">
              <.theme_toggle />
            </div>
          </div>
        </aside>
      </div>
    </div>
    """
  end

  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite" class="mb-4">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="Connection lost"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />
      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
