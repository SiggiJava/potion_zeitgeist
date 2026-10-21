defmodule PotionZeitgeistWeb.Admin.InvoiceTemplatesLive do
  use PotionZeitgeistWeb, :live_view

  alias PotionZeitgeist.Invoicing

  on_mount {PotionZeitgeistWeb.UserAuth, :ensure_admin}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Letter templates")
     |> assign(:templates, Invoicing.list_templates())
     |> assign(:confirm_delete_id, nil)}
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
  def handle_event("delete_template", %{"id" => id}, socket) do
    template = Invoicing.get_template!(id)

    case Invoicing.delete_template(template) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:templates, Invoicing.list_templates())
         |> assign(:confirm_delete_id, nil)
         |> put_flash(:info, "Template deleted. Issued invoices keep their letter text.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete the template.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between flex-wrap gap-3">
        <div>
          <.link navigate={~p"/admin/invoices"} class="text-sm text-base-content/60 hover:underline">
            ← Invoices
          </.link>
          <h1 class="text-2xl font-bold">Letter templates</h1>
          <p class="text-sm text-base-content/60">
            Invoice letters with placeholders that are filled in for each invoice.
          </p>
        </div>
        <.link
          id="new-template"
          navigate={~p"/admin/invoice-templates/new"}
          class="btn btn-primary btn-sm gap-2"
        >
          <.icon name="hero-plus" class="size-4" /> New template
        </.link>
      </div>

      <%= if @templates == [] do %>
        <div class="card bg-base-100 shadow">
          <div class="card-body items-center text-center py-16">
            <.icon name="hero-document-text" class="size-12 text-base-content/30" />
            <p class="text-base-content/60 mt-2">No letter templates yet.</p>
            <p class="text-sm text-base-content/50">
              A new template starts from a sample letter you can adapt.
            </p>
            <.link navigate={~p"/admin/invoice-templates/new"} class="btn btn-primary btn-sm mt-4">
              Create the first template
            </.link>
          </div>
        </div>
      <% else %>
        <div class="card bg-base-100 shadow overflow-x-auto">
          <table id="invoice-templates" class="table w-full">
            <thead>
              <tr>
                <th>Name</th>
                <th>Subject</th>
                <th>Last changed</th>
                <th class="text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={template <- @templates} id={"template-#{template.id}"}>
                <td class="font-medium">{template.name}</td>
                <td class="text-sm text-base-content/70 max-w-xs truncate">{template.subject}</td>
                <td class="text-sm text-base-content/70">
                  {Calendar.strftime(template.updated_at, "%Y-%m-%d")}
                </td>
                <td class="text-right">
                  <div class="flex gap-1 justify-end flex-wrap">
                    <.link
                      navigate={~p"/admin/invoice-templates/#{template}/edit"}
                      class="btn btn-ghost btn-xs gap-1"
                    >
                      <.icon name="hero-pencil" class="size-3" /> Edit
                    </.link>
                    <%= if @confirm_delete_id == template.id do %>
                      <span class="text-error text-xs self-center font-medium">Delete?</span>
                      <button
                        phx-click="delete_template"
                        phx-value-id={template.id}
                        class="btn btn-error btn-xs"
                      >
                        Yes
                      </button>
                      <button phx-click="cancel_delete" class="btn btn-ghost btn-xs">No</button>
                    <% else %>
                      <button
                        phx-click="confirm_delete"
                        phx-value-id={template.id}
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
      <% end %>
    </div>
    """
  end
end
