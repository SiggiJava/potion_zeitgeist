defmodule PotionZeitgeistWeb.Admin.InvoicesLive do
  use PotionZeitgeistWeb, :live_view

  import PotionZeitgeistWeb.InvoiceComponents

  alias PotionZeitgeist.Invoicing
  alias PotionZeitgeist.Invoicing.Format

  on_mount {PotionZeitgeistWeb.UserAuth, :ensure_admin}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Invoices")
     |> assign(:invoices, Invoicing.list_invoices())
     |> assign(:has_templates?, Invoicing.list_templates() != [])}
  end

  defp first_line(text) do
    text |> to_string() |> String.split(["\r\n", "\n"], trim: true) |> List.first("")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 class="text-2xl font-bold">Invoices</h1>
          <p class="text-sm text-base-content/60">
            Bill booked project time of a month at an hourly rate.
          </p>
        </div>
        <div class="flex gap-2 flex-wrap">
          <.link navigate={~p"/admin/invoice-templates"} class="btn btn-ghost btn-sm gap-2">
            <.icon name="hero-document-duplicate" class="size-4" /> Letter templates
          </.link>
          <.link
            :if={@has_templates?}
            id="new-invoice"
            navigate={~p"/admin/invoices/new"}
            class="btn btn-primary btn-sm gap-2"
          >
            <.icon name="hero-plus" class="size-4" /> New invoice
          </.link>
        </div>
      </div>

      <div :if={!@has_templates?} role="alert" class="alert alert-info">
        <.icon name="hero-information-circle" class="size-5" />
        <span>
          Invoices are printed with a letter template. Create one first, it starts from a sample letter.
        </span>
        <.link navigate={~p"/admin/invoice-templates/new"} class="btn btn-sm">Create template</.link>
      </div>

      <%= if @invoices == [] do %>
        <div class="card bg-base-100 shadow">
          <div class="card-body items-center text-center py-16">
            <.icon name="hero-document-currency-euro" class="size-12 text-base-content/30" />
            <p class="text-base-content/60 mt-2">No invoices yet.</p>
          </div>
        </div>
      <% else %>
        <div class="card bg-base-100 shadow overflow-x-auto">
          <table id="invoices" class="table table-zebra w-full">
            <thead>
              <tr>
                <th>Number</th>
                <th>Date</th>
                <th>Recipient</th>
                <th>Period</th>
                <th class="text-right">Amount</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={invoice <- @invoices}
                id={"invoice-#{invoice.id}"}
                class="hover:bg-base-200 cursor-pointer"
                phx-click={JS.navigate(~p"/admin/invoices/#{invoice}")}
              >
                <td class="font-medium font-mono">
                  <.link navigate={~p"/admin/invoices/#{invoice}"} class="hover:underline">
                    {invoice.number || "Draft"}
                  </.link>
                </td>
                <td class="text-sm">{Format.date(invoice.invoice_date)}</td>
                <td class="text-sm max-w-xs truncate">{first_line(invoice.recipient)}</td>
                <td class="text-sm">{Format.month(invoice.period_start)}</td>
                <td class="text-right font-mono text-sm whitespace-nowrap">
                  {Format.money(invoice.gross_total)}
                </td>
                <td><.invoice_status status={invoice.status} /></td>
              </tr>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end
end
