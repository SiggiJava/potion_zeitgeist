defmodule PotionZeitgeistWeb.Admin.InvoiceLive do
  use PotionZeitgeistWeb, :live_view

  import PotionZeitgeistWeb.InvoiceComponents

  alias PotionZeitgeist.Invoicing
  alias PotionZeitgeist.Invoicing.Format

  on_mount {PotionZeitgeistWeb.UserAuth, :ensure_admin}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign_invoice(Invoicing.get_invoice!(id))
     |> assign(:issue_form, nil)
     |> assign(:issue_warnings, [])
     |> assign(:last_issued, nil)
     |> assign(:confirm, nil)}
  end

  defp assign_invoice(socket, invoice) do
    socket
    |> assign(:invoice, invoice)
    |> assign(:letter, Invoicing.letter(invoice))
    |> assign(:page_title, title(invoice))
  end

  defp title(%{status: "draft"}), do: "Draft invoice"
  defp title(%{number: number}), do: "Invoice #{number}"

  @impl true
  def handle_event("show_issue", _params, socket) do
    changeset = Invoicing.change_issue(socket.assigns.invoice, Invoicing.today())

    {:noreply,
     socket
     |> assign(:last_issued, Invoicing.last_issued())
     |> assign_issue_form(changeset)}
  end

  @impl true
  def handle_event("cancel_issue", _params, socket) do
    {:noreply, assign(socket, :issue_form, nil)}
  end

  @impl true
  def handle_event("validate_issue", %{"issue" => params}, socket) do
    changeset =
      socket.assigns.invoice
      |> PotionZeitgeist.Invoicing.Invoice.issue_form_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_issue_form(socket, changeset)}
  end

  @impl true
  def handle_event("issue", %{"issue" => params}, socket) do
    case Invoicing.issue_invoice(socket.assigns.invoice, params) do
      {:ok, invoice} ->
        {:noreply,
         socket
         |> assign_invoice(invoice)
         |> assign(:issue_form, nil)
         |> put_flash(
           :info,
           "Invoice #{invoice.number} issued. Save it as PDF and keep the PDF you send for 8 years."
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_issue_form(socket, changeset)}

      {:error, _} ->
        {:noreply, reload(socket, "This invoice was issued in the meantime.")}
    end
  end

  @impl true
  def handle_event("confirm", %{"action" => action}, socket) when action in ~w(delete cancel) do
    {:noreply, assign(socket, :confirm, action)}
  end

  @impl true
  def handle_event("dismiss", _params, socket) do
    {:noreply, assign(socket, :confirm, nil)}
  end

  @impl true
  def handle_event("delete_draft", _params, socket) do
    case Invoicing.delete_draft(socket.assigns.invoice) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Draft deleted. Its time entries can be billed again.")
         |> push_navigate(to: ~p"/admin/invoices")}

      {:error, _} ->
        {:noreply, reload(socket, "Only drafts can be deleted.")}
    end
  end

  @impl true
  def handle_event("cancel_invoice", _params, socket) do
    case Invoicing.cancel_invoice(socket.assigns.invoice) do
      {:ok, invoice} ->
        {:noreply,
         socket
         |> assign_invoice(invoice)
         |> assign(:confirm, nil)
         |> put_flash(
           :info,
           "Invoice #{invoice.number} cancelled. Its time entries can be billed again."
         )}

      {:error, _} ->
        {:noreply, reload(socket, "Only issued invoices can be cancelled.")}
    end
  end

  defp assign_issue_form(socket, changeset) do
    date = Ecto.Changeset.get_field(changeset, :invoice_date)

    params = %{
      "number" => to_string(Ecto.Changeset.get_field(changeset, :number)),
      "invoice_date" => date && Date.to_iso8601(date)
    }

    socket
    |> assign(:issue_form, to_form(changeset, as: :issue))
    |> assign(:issue_warnings, Invoicing.issue_warnings(socket.assigns.invoice, params))
  end

  # Errors of the issue that have no field in the form, e.g. a missing template.
  defp other_errors(form) do
    for {field, error} <- form.source.errors, field not in [:number, :invoice_date] do
      "#{Phoenix.Naming.humanize(field)} #{translate_error(error)}"
    end
  end

  # The invoice was changed in another tab. A deleted draft leaves the page.
  defp reload(socket, message) do
    case Invoicing.get_invoice(socket.assigns.invoice.id) do
      nil ->
        socket
        |> put_flash(:error, "This draft was deleted in the meantime.")
        |> push_navigate(to: ~p"/admin/invoices")

      invoice ->
        socket
        |> assign_invoice(invoice)
        |> assign(:issue_form, nil)
        |> assign(:confirm, nil)
        |> put_flash(:error, message)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-start justify-between flex-wrap gap-3 print:hidden">
        <div>
          <.link navigate={~p"/admin/invoices"} class="text-sm text-base-content/60 hover:underline">
            ← Invoices
          </.link>
          <h1 class="text-2xl font-bold flex items-center gap-3">
            {@page_title} <.invoice_status status={@invoice.status} />
          </h1>
          <p class="text-sm text-base-content/60">
            {Format.month(@invoice.period_start)} · {Format.money(@invoice.gross_total)}
            <%= if @invoice.issued_at do %>
              · issued {Calendar.strftime(@invoice.issued_at, "%Y-%m-%d")}
            <% end %>
          </p>
        </div>

        <div class="flex gap-2 flex-wrap">
          <%= if @invoice.status == "draft" do %>
            <.link
              id="edit-invoice"
              navigate={~p"/admin/invoices/#{@invoice}/edit"}
              class="btn btn-ghost btn-sm gap-2"
            >
              <.icon name="hero-pencil" class="size-4" /> Edit
            </.link>
            <button
              id="delete-invoice"
              phx-click="confirm"
              phx-value-action="delete"
              class="btn btn-ghost btn-sm gap-2 text-error"
            >
              <.icon name="hero-trash" class="size-4" /> Delete draft
            </button>
          <% end %>
          <%= if @invoice.status == "issued" do %>
            <button
              id="cancel-invoice"
              phx-click="confirm"
              phx-value-action="cancel"
              class="btn btn-ghost btn-sm gap-2 text-error"
            >
              <.icon name="hero-x-circle" class="size-4" /> Cancel invoice
            </button>
          <% end %>
          <%= if @invoice.status == "cancelled" do %>
            <.link
              id="correct-invoice"
              navigate={~p"/admin/invoices/new?#{[from: @invoice.id]}"}
              class="btn btn-ghost btn-sm gap-2"
            >
              <.icon name="hero-arrow-path" class="size-4" /> Create corrected invoice
            </.link>
          <% else %>
            <.link
              id="copy-invoice"
              navigate={~p"/admin/invoices/new?#{[from: @invoice.id]}"}
              class="btn btn-ghost btn-sm gap-2"
            >
              <.icon name="hero-document-duplicate" class="size-4" /> New invoice like this
            </.link>
          <% end %>
          <a
            id="print-link"
            href={~p"/admin/invoices/#{@invoice}/print"}
            target="_blank"
            class={[
              "btn btn-sm gap-2",
              if(@invoice.status == "issued", do: "btn-primary", else: "btn-ghost")
            ]}
          >
            <.icon name="hero-printer" class="size-4" /> Print / PDF
          </a>
          <button
            :if={@invoice.status == "draft"}
            id="issue-invoice"
            phx-click="show_issue"
            class="btn btn-primary btn-sm gap-2"
            disabled={is_nil(@invoice.template)}
          >
            <.icon name="hero-check-badge" class="size-4" /> Issue invoice
          </button>
        </div>
      </div>

      <div
        :if={@invoice.status == "draft" && is_nil(@invoice.template)}
        role="alert"
        class="alert alert-warning print:hidden"
      >
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <span>
          The letter template of this draft was deleted. Edit the draft and pick another one.
        </span>
      </div>

      <p :if={@invoice.status == "draft"} class="text-sm text-base-content/60 print:hidden">
        This is a draft. It has no number yet and can still be changed. Issuing it assigns the
        invoice number and freezes the letter.
      </p>

      <p :if={@invoice.status == "issued"} class="text-sm text-base-content/60 print:hidden">
        Issued invoices can no longer be changed. Keep the PDF you send to the client for 8 years.
      </p>

      <div :if={@invoice.status == "cancelled"} role="alert" class="alert print:hidden">
        <.icon name="hero-information-circle" class="size-5" />
        <span>
          This invoice was cancelled on {Calendar.strftime(@invoice.cancelled_at, "%Y-%m-%d")}.
          It keeps its number. Its time entries can be billed on a new invoice.
        </span>
      </div>

      <div class="overflow-x-auto rounded-box bg-base-300 p-4 sm:p-8 print:overflow-visible print:bg-transparent print:p-0">
        <.letter letter={@letter} />
      </div>

      <%= if @issue_form do %>
        <div class="modal modal-open">
          <div class="modal-box">
            <h3 class="font-bold text-lg mb-2">Issue invoice</h3>
            <p class="text-sm text-base-content/70 mb-4">
              The invoice gets its number and can no longer be edited, only cancelled.
            </p>
            <p id="last-issued" class="text-sm mb-3">
              <%= if @last_issued do %>
                Last invoice: <span class="font-mono">{@last_issued.number}</span>
                of {Calendar.strftime(@last_issued.invoice_date, "%Y-%m-%d")}
              <% else %>
                This is the first invoice in the app. Enter the number that follows your
                last invoice, so your numbering continues without gaps.
              <% end %>
            </p>
            <.form
              for={@issue_form}
              id="issue-form"
              phx-change="validate_issue"
              phx-submit="issue"
            >
              <.input field={@issue_form[:number]} label="Invoice number" required />
              <.input
                field={@issue_form[:invoice_date]}
                type="date"
                label="Invoice date"
                required
              />
              <p :if={@invoice.due_date} class="text-xs text-base-content/60 -mt-1 mb-2">
                The due date moves with the invoice date.
              </p>
              <p :for={message <- other_errors(@issue_form)} class="text-sm text-error">
                {message}
              </p>
              <div :if={@issue_warnings != []} id="issue-warnings" class="alert alert-warning mt-2">
                <.icon name="hero-exclamation-triangle" class="size-5" />
                <ul class="text-sm">
                  <li :for={warning <- @issue_warnings}>{warning}</li>
                </ul>
              </div>
              <div class="modal-action">
                <button type="button" phx-click="cancel_issue" class="btn btn-ghost">Cancel</button>
                <button type="submit" class="btn btn-primary" phx-disable-with="Issuing...">
                  Issue invoice
                </button>
              </div>
            </.form>
          </div>
          <div class="modal-backdrop" phx-click="cancel_issue"></div>
        </div>
      <% end %>

      <%= if @confirm do %>
        <div class="modal modal-open">
          <div class="modal-box">
            <%= if @confirm == "delete" do %>
              <h3 class="font-bold text-lg mb-2">Delete this draft?</h3>
              <p class="text-sm text-base-content/70">
                Its time entries become available for other invoices again.
              </p>
              <div class="modal-action">
                <button phx-click="dismiss" class="btn btn-ghost">Keep draft</button>
                <button id="confirm-delete" phx-click="delete_draft" class="btn btn-error">
                  Delete draft
                </button>
              </div>
            <% else %>
              <h3 class="font-bold text-lg mb-2">Cancel invoice {@invoice.number}?</h3>
              <p class="text-sm text-base-content/70">
                The invoice stays in the list as cancelled and keeps its number, so your
                numbering has no gaps. Its time entries can then be billed on a new invoice.
                If the client already received it, tell them in writing that it is cancelled.
              </p>
              <div class="modal-action">
                <button phx-click="dismiss" class="btn btn-ghost">Keep invoice</button>
                <button id="confirm-cancel" phx-click="cancel_invoice" class="btn btn-error">
                  Cancel invoice
                </button>
              </div>
            <% end %>
          </div>
          <div class="modal-backdrop" phx-click="dismiss"></div>
        </div>
      <% end %>
    </div>
    """
  end
end
