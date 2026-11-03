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

    # Texts are measured with the sample letter of the preview, of this date.
    today = Invoicing.today()

    # A new template starts from the sample letter.
    changeset =
      case socket.assigns.live_action do
        :new -> Invoicing.change_template(template, sample_attrs(), today)
        :edit -> Invoicing.change_template(template, %{}, today)
      end

    {:ok,
     socket
     |> assign(
       :page_title,
       if(template.id, do: "Edit letter template", else: "New letter template")
     )
     |> assign(:template, template)
     |> assign(:today, today)
     |> assign(:preview_due_date?, true)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("toggle_preview_due_date", _params, socket) do
    socket = assign(socket, :preview_due_date?, not socket.assigns.preview_due_date?)
    {:noreply, assign_preview(socket, Ecto.Changeset.apply_changes(socket.assigns.form.source))}
  end

  @impl true
  def handle_event("validate", %{"invoice_template" => params}, socket) do
    changeset =
      socket.assigns.template
      |> Invoicing.change_template(params, socket.assigns.today)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("save", %{"invoice_template" => params}, socket) do
    result =
      case socket.assigns.template do
        %InvoiceTemplate{id: nil} -> Invoicing.create_template(params, socket.assigns.today)
        template -> Invoicing.update_template(template, params, socket.assigns.today)
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
    |> assign(:missing_items?, not Letter.has_items_placeholder?(template.body))
    |> assign_preview(template)
  end

  defp assign_preview(socket, template) do
    %{today: today, preview_due_date?: due_date?} = socket.assigns
    assign(socket, :preview, Letter.sample(template, today, due_date: due_date?))
  end

  defp block_tags do
    [
      {"#{Letter.tag("#faellig_am")} … #{Letter.tag("/faellig_am")}",
       "Text only on invoices with a due date"},
      {"#{Letter.tag("^faellig_am")} … #{Letter.tag("/faellig_am")}",
       "Text only on invoices without a due date"},
      {"#{Letter.tag("#ust")} … #{Letter.tag("/ust")}", "Text only on invoices with VAT"}
    ]
  end

  defp block_example do
    "… von #{Letter.tag("gesamtbetrag")}#{Letter.tag("#faellig_am")} bis zum " <>
      "#{Letter.tag("faellig_am")}#{Letter.tag("/faellig_am")} unter Angabe …"
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
                  label="Your name and address (letterhead, top right, at most 7 lines)"
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
                  label="Footer (bank details, at most 4 lines)"
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
              <h2 class="font-semibold mt-4">Text that depends on a value</h2>
              <dl id="blocks-help" class="mt-2 grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-sm">
                <%= for {block, description} <- block_tags() do %>
                  <dt><code class="text-primary">{block}</code></dt>
                  <dd class="text-base-content/70">{description}</dd>
                <% end %>
              </dl>
              <p class="mt-2 text-sm text-base-content/60">
                This works with every placeholder: the text prints when it has a value. A
                block starts and ends on the same line. A line with nothing else is left
                out when its text does not print. For example, this names the due date
                only when there is one:
              </p>
              <p id="block-example" class="mt-1 text-sm font-mono text-base-content/70 break-words">
                {block_example()}
              </p>
              <p class="mt-3 text-sm text-base-content/60">
                Your address, the tax number line, the recipient, invoice number, date,
                service period, items and totals are always printed. Without VAT, the
                invoice also always says: "{Letter.small_business_note()}"
              </p>
            </div>
          </div>
        </div>

        <div>
          <div class="flex items-center justify-between gap-3 mb-2">
            <h2 class="font-semibold">Preview with sample data</h2>
            <label class="flex items-center gap-2 text-sm cursor-pointer">
              <input
                type="checkbox"
                id="preview-due-date"
                checked={@preview_due_date?}
                phx-click="toggle_preview_due_date"
                class="checkbox checkbox-sm"
              /> With due date
            </label>
          </div>
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
