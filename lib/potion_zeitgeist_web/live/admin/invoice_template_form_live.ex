defmodule PotionZeitgeistWeb.Admin.InvoiceTemplateFormLive do
  use PotionZeitgeistWeb, :live_view

  import PotionZeitgeistWeb.InvoiceComponents

  alias PotionZeitgeist.Invoicing
  alias PotionZeitgeist.Invoicing.{InvoiceTemplate, Letter}

  on_mount {PotionZeitgeistWeb.UserAuth, :ensure_admin}

  @impl true
  def mount(params, _session, socket) do
    template =
      case socket.assigns.live_action do
        :edit -> Invoicing.get_template!(params["id"])
        :new -> %InvoiceTemplate{}
      end

    # A new template starts from the sample letter.
    changeset =
      case socket.assigns.live_action do
        :new -> Invoicing.change_template(template, sample_attrs())
        :edit -> Invoicing.change_template(template)
      end

    {:ok,
     socket
     |> assign(
       :page_title,
       if(template.id, do: "Edit letter template", else: "New letter template")
     )
     |> assign(:template, template)
     |> assign(:today, Invoicing.today())
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"invoice_template" => params}, socket) do
    changeset =
      socket.assigns.template
      |> Invoicing.change_template(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("save", %{"invoice_template" => params}, socket) do
    result =
      case socket.assigns.template do
        %InvoiceTemplate{id: nil} -> Invoicing.create_template(params)
        template -> Invoicing.update_template(template, params)
      end

    case result do
      {:ok, _template} ->
        {:noreply,
         socket
         |> put_flash(:info, "Template saved.")
         |> push_navigate(to: ~p"/admin/invoice-templates")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset) do
    template = Ecto.Changeset.apply_changes(changeset)

    socket
    |> assign(:form, to_form(changeset))
    |> assign(:preview, Letter.sample(template, socket.assigns.today))
    |> assign(:missing_items?, not Letter.has_items_placeholder?(template.body))
  end

  defp sample_attrs do
    Invoicing.sample_template() |> Map.take([:name, :sender, :tax_id, :subject, :body, :footer])
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <.link
          navigate={~p"/admin/invoice-templates"}
          class="text-sm text-base-content/60 hover:underline"
        >
          ← Letter templates
        </.link>
        <h1 class="text-2xl font-bold">{@page_title}</h1>
      </div>

      <div class="grid gap-6 xl:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
        <div class="space-y-6">
          <div class="card bg-base-100 shadow">
            <div class="card-body">
              <.form for={@form} id="template-form" phx-change="validate" phx-submit="save">
                <p :if={@template.id == nil} class="text-sm text-warning mb-3">
                  <.icon name="hero-pencil-square" class="size-4" />
                  The new template starts from a sample letter. Replace the sample name, address,
                  tax number and bank details with your own.
                </p>
                <.input field={@form[:name]} label="Template name" required phx-debounce="300" />
                <.input
                  field={@form[:sender]}
                  type="textarea"
                  label="Your name and address (letterhead, top right)"
                  rows="6"
                  required
                  phx-debounce="300"
                />
                <.input
                  field={@form[:tax_id]}
                  label="Tax number line, printed on every invoice"
                  placeholder="Steuernummer: 123/456/78901"
                  required
                  phx-debounce="300"
                />
                <.input field={@form[:subject]} label="Subject" phx-debounce="300" />
                <.input
                  field={@form[:body]}
                  type="textarea"
                  label="Letter text"
                  rows="16"
                  required
                  phx-debounce="300"
                />
                <p :if={@missing_items?} class="text-sm text-warning mb-2">
                  <.icon name="hero-exclamation-triangle" class="size-4" /> The letter text has no
                  <code>{Letter.tag("positionen")}</code>
                  placeholder, so the table of items follows the whole text.
                </p>
                <.input
                  field={@form[:footer]}
                  type="textarea"
                  label="Footer (bank details)"
                  rows="3"
                  phx-debounce="300"
                />
                <div class="flex justify-end gap-2 mt-4">
                  <.link navigate={~p"/admin/invoice-templates"} class="btn btn-ghost">
                    Cancel
                  </.link>
                  <button type="submit" class="btn btn-primary" phx-disable-with="Saving...">
                    Save template
                  </button>
                </div>
              </.form>
            </div>
          </div>

          <div class="card bg-base-100 shadow">
            <div class="card-body">
              <h2 class="font-semibold">Placeholders</h2>
              <p class="text-sm text-base-content/60">
                Usable in every field. They are replaced when the invoice is printed.
              </p>
              <dl id="placeholders" class="mt-2 grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-sm">
                <%= for {name, description} <- Letter.placeholders() do %>
                  <dt><code class="text-primary">{Letter.tag(name)}</code></dt>
                  <dd class="text-base-content/70">{description}</dd>
                <% end %>
              </dl>
              <p class="mt-3 text-sm text-base-content/60">
                Your address, the tax number line, the recipient, invoice number, date,
                service period, items and totals are always printed. Without VAT, the
                invoice also always says: "{Letter.small_business_note()}"
              </p>
            </div>
          </div>
        </div>

        <div>
          <h2 class="font-semibold mb-2">Preview with sample data</h2>
          <div class="overflow-hidden rounded-box bg-base-300 p-4">
            <div class="[zoom:0.62] origin-top">
              <.letter id="template-preview" letter={@preview} />
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
