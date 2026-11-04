defmodule PotionZeitgeistWeb.Admin.AnnualReportLive do
  @moduledoc """
  The annual report: the issued invoices of a year with their sums, counted
  by the day their payment came in (as for the EÜR) or by invoice date,
  with links to the CSV files and the print page. Payments of invoices that
  are not paid yet can be recorded right here.
  """
  use PotionZeitgeistWeb, :live_view

  alias PotionZeitgeist.Invoicing
  alias PotionZeitgeist.Invoicing.{AnnualReport, Format}

  on_mount {PotionZeitgeistWeb.UserAuth, :ensure_admin}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Annual report")
     |> assign(:today, Invoicing.today())
     |> assign(:payments, %{})}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    year = AnnualReport.parse_year(params["year"]) || socket.assigns.today.year
    basis = AnnualReport.parse_basis(params["basis"])

    {:noreply,
     socket
     |> assign(year: year, basis: basis, payments: %{})
     |> load_report()}
  end

  defp load_report(socket) do
    %{year: year, basis: basis, today: today} = socket.assigns

    socket
    |> assign(:report, Invoicing.annual_report(year, basis))
    |> assign(:years, Invoicing.report_years(today, year))
  end

  @impl true
  def handle_event("select_year", %{"year" => year}, socket) do
    year = AnnualReport.parse_year(year) || socket.assigns.year
    {:noreply, push_patch(socket, to: report_path(year, socket.assigns.basis))}
  end

  # Records the payment of an invoice of the list of invoices not paid yet.
  # A date that cannot be saved stays in its field with the reason.
  @impl true
  def handle_event("mark_paid", %{"id" => id, "payment" => params}, socket) do
    result =
      case Invoicing.get_invoice(id) do
        nil -> {:error, :not_found}
        invoice -> Invoicing.mark_paid(invoice, params)
      end

    case result do
      {:ok, invoice} ->
        {:noreply,
         socket
         |> assign(:payments, Map.delete(socket.assigns.payments, invoice.id))
         |> put_flash(
           :info,
           "Invoice #{invoice.number} marked as paid on #{Format.date(invoice.paid_on)}."
         )
         |> load_report()}

      {:error, %Ecto.Changeset{} = changeset} ->
        payment = %{value: params["paid_on"], errors: payment_errors(changeset)}

        {:noreply,
         assign(socket, :payments, Map.put(socket.assigns.payments, changeset.data.id, payment))}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "That invoice was changed in the meantime.")
         |> load_report()}
    end
  end

  defp payment_errors(changeset) do
    for {:paid_on, error} <- changeset.errors, do: translate_error(error)
  end

  defp report_path(year, basis), do: ~p"/admin/invoices/annual?#{[year: year, basis: basis]}"

  defp csv_path(report, type) do
    ~p"/admin/invoices/annual/#{report.year}/csv?#{[basis: report.basis, type: type]}"
  end

  defp print_path(report) do
    ~p"/admin/invoices/annual/#{report.year}/print?#{[basis: report.basis]}"
  end

  defp payment_value(payments, row, today) do
    case payments do
      %{^row => %{value: value}} -> value
      _ -> Date.to_iso8601(today)
    end
  end

  attr :rows, :list, required: true
  attr :id, :string, required: true
  attr :vat?, :boolean, default: false
  attr :paid?, :boolean, default: true
  attr :cancelled?, :boolean, default: false
  slot :inner_block, doc: "the row of sums"

  defp invoice_table(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow overflow-x-auto">
      <table id={@id} class="table table-zebra w-full">
        <thead>
          <tr>
            <th>Number</th>
            <th>Date</th>
            <th :if={@paid?}>Paid</th>
            <th :if={@cancelled?}>Cancelled</th>
            <th>Recipient</th>
            <th class="text-right">Hours</th>
            <th :if={@vat?} class="text-right">Net</th>
            <th :if={@vat?} class="text-right">VAT</th>
            <th class="text-right">Amount</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @rows} id={"#{@id}-#{row.id}"}>
            <td class="font-medium font-mono whitespace-nowrap">
              <.link navigate={~p"/admin/invoices/#{row.id}"} class="hover:underline">
                {row.number}
              </.link>
            </td>
            <td class="text-sm whitespace-nowrap">{Format.date(row.invoice_date)}</td>
            <td :if={@paid?} class="text-sm whitespace-nowrap">{Format.date(row.paid_on)}</td>
            <td :if={@cancelled?} class="text-sm whitespace-nowrap">
              {row.cancelled_at && Format.date(DateTime.to_date(row.cancelled_at))}
            </td>
            <td class="text-sm max-w-xs truncate">{row.recipient}</td>
            <td class="text-right font-mono text-sm whitespace-nowrap">{Format.hours(row.hours)}</td>
            <td :if={@vat?} class="text-right font-mono text-sm whitespace-nowrap">
              {Format.money(row.net)}
            </td>
            <td :if={@vat?} class="text-right font-mono text-sm whitespace-nowrap">
              {Format.money(row.vat)}
            </td>
            <td class="text-right font-mono text-sm whitespace-nowrap">{Format.money(row.gross)}</td>
          </tr>
        </tbody>
        <tfoot :if={@inner_block != []}>
          {render_slot(@inner_block)}
        </tfoot>
      </table>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-start justify-between flex-wrap gap-3">
        <div>
          <.link navigate={~p"/admin/invoices"} class="text-sm text-base-content/60 hover:underline">
            ← Invoices
          </.link>
          <h1 class="text-2xl font-bold">Annual report</h1>
          <p class="text-sm text-base-content/60">
            The issued invoices of a year with their time and other items, for your EÜR.
          </p>
        </div>
        <div class="flex gap-2 flex-wrap">
          <a id="csv-invoices" href={csv_path(@report, "invoices")} class="btn btn-ghost btn-sm gap-2">
            <.icon name="hero-arrow-down-tray" class="size-4" /> CSV: invoices
          </a>
          <a id="csv-items" href={csv_path(@report, "items")} class="btn btn-ghost btn-sm gap-2">
            <.icon name="hero-arrow-down-tray" class="size-4" /> CSV: items
          </a>
          <a
            id="print-report"
            href={print_path(@report)}
            target="_blank"
            class="btn btn-primary btn-sm gap-2"
          >
            <.icon name="hero-printer" class="size-4" /> Print / PDF
          </a>
        </div>
      </div>

      <div class="flex flex-wrap items-end gap-4">
        <form id="year-form" phx-change="select_year" class="w-32">
          <.input
            id="report-year"
            type="select"
            name="year"
            label="Year"
            options={@years}
            value={@year}
          />
        </form>
        <div class="join mb-2" role="group" aria-label="Count invoices">
          <.link
            id="basis-paid"
            patch={report_path(@year, "paid")}
            class={["btn btn-sm join-item", if(@basis == "paid", do: "btn-primary")]}
          >
            By payment date
          </.link>
          <.link
            id="basis-invoice"
            patch={report_path(@year, "invoice")}
            class={["btn btn-sm join-item", if(@basis == "invoice", do: "btn-primary")]}
          >
            By invoice date
          </.link>
        </div>
      </div>

      <p id="basis-note" class="text-sm text-base-content/70 max-w-3xl">
        <%= if @basis == "paid" do %>
          Counts each issued invoice in the year its payment came in, as the EÜR counts income
          (§ 11 EStG). Record payments on the invoice pages or in the list below.
        <% else %>
          Counts issued invoices by their invoice date. For the EÜR the year the payment came
          in counts, see "By payment date".
        <% end %>
      </p>

      <div
        id="report-totals"
        class="stats stats-vertical sm:stats-horizontal shadow bg-base-100 w-full"
      >
        <div class="stat">
          <div class="stat-title">Invoices</div>
          <div class="stat-value text-2xl">{@report.totals.count}</div>
        </div>
        <div :if={@report.totals.time?} class="stat">
          <div class="stat-title">Hours</div>
          <div class="stat-value text-2xl">{Format.hours(@report.totals.hours)}</div>
          <div class="stat-desc">{Format.money(@report.totals.time_amount)}</div>
        </div>
        <div :if={@report.totals.other?} class="stat">
          <div class="stat-title">Other items</div>
          <div class="stat-value text-2xl">{Format.money(@report.totals.other_amount)}</div>
        </div>
        <div :if={@report.vat?} class="stat">
          <div class="stat-title">Net · VAT</div>
          <div class="stat-value text-2xl">{Format.money(@report.totals.net)}</div>
          <div class="stat-desc">VAT {Format.money(@report.totals.vat)}</div>
        </div>
        <div class="stat">
          <div class="stat-title">Total {@year}</div>
          <div id="report-total" class="stat-value text-2xl text-primary">
            {Format.money(@report.totals.gross)}
          </div>
        </div>
      </div>

      <%= if @report.invoices == [] do %>
        <div class="card bg-base-100 shadow">
          <div class="card-body items-center text-center py-12">
            <.icon name="hero-document-currency-euro" class="size-12 text-base-content/30" />
            <p id="report-empty" class="text-base-content/60 mt-2">
              <%= if @basis == "paid" do %>
                No payments recorded in {@year}.
              <% else %>
                No invoices issued in {@year}.
              <% end %>
            </p>
          </div>
        </div>
      <% else %>
        <.invoice_table id="report-invoices" rows={@report.invoices} vat?={@report.vat?}>
          <tr class="font-semibold">
            <td colspan="4">{AnnualReport.count_label(@report.totals.count)} · Sum {@year}</td>
            <td class="text-right font-mono text-sm whitespace-nowrap">
              {Format.hours(@report.totals.hours)}
            </td>
            <td :if={@report.vat?} class="text-right font-mono text-sm whitespace-nowrap">
              {Format.money(@report.totals.net)}
            </td>
            <td :if={@report.vat?} class="text-right font-mono text-sm whitespace-nowrap">
              {Format.money(@report.totals.vat)}
            </td>
            <td class="text-right font-mono text-sm whitespace-nowrap">
              {Format.money(@report.totals.gross)}
            </td>
          </tr>
        </.invoice_table>
      <% end %>

      <section :if={@report.unpaid != []} id="report-unpaid" class="space-y-2">
        <h2 class="text-lg font-semibold">Not paid yet</h2>
        <p class="text-sm text-base-content/60">
          Issued up to {@year} without a payment date. They count in the year their payment
          comes in.
        </p>
        <div class="card bg-base-100 shadow overflow-x-auto">
          <table id="unpaid-invoices" class="table w-full">
            <thead>
              <tr>
                <th>Number</th>
                <th>Date</th>
                <th>Recipient</th>
                <th class="text-right">Amount</th>
                <th>Paid on</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @report.unpaid} id={"unpaid-#{row.id}"}>
                <td class="font-medium font-mono whitespace-nowrap">
                  <.link navigate={~p"/admin/invoices/#{row.id}"} class="hover:underline">
                    {row.number}
                  </.link>
                </td>
                <td class="text-sm whitespace-nowrap">{Format.date(row.invoice_date)}</td>
                <td class="text-sm max-w-xs truncate">{row.recipient}</td>
                <td class="text-right font-mono text-sm whitespace-nowrap">
                  {Format.money(row.gross)}
                </td>
                <td>
                  <form
                    id={"pay-#{row.id}"}
                    phx-submit="mark_paid"
                    novalidate
                    class="flex flex-wrap items-center gap-2"
                  >
                    <input type="hidden" name="id" value={row.id} />
                    <input
                      type="date"
                      name="payment[paid_on]"
                      aria-label={"Payment date of invoice #{row.number}"}
                      value={payment_value(@payments, row.id, @today)}
                      max={Date.to_iso8601(@today)}
                      class={[
                        "input input-sm w-40",
                        Map.has_key?(@payments, row.id) && "input-error"
                      ]}
                    />
                    <button type="submit" class="btn btn-sm gap-2" phx-disable-with="Saving...">
                      <.icon name="hero-check-circle" class="size-4" /> Paid
                    </button>
                    <p
                      :for={error <- get_in(@payments, [row.id, :errors]) || []}
                      class="text-sm text-error w-full"
                    >
                      {error}
                    </p>
                  </form>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section :if={@report.paid_later != []} id="report-paid-later" class="space-y-2">
        <h2 class="text-lg font-semibold">Issued in {@year}, paid later</h2>
        <p class="text-sm text-base-content/60">
          They count in the year of their payment.
        </p>
        <.invoice_table id="paid-later-invoices" rows={@report.paid_later} />
      </section>

      <section :if={@report.cancelled != []} id="report-cancelled" class="space-y-2">
        <h2 class="text-lg font-semibold">Cancelled invoices of {@year}</h2>
        <p class="text-sm text-base-content/60">
          Invoices of {@year} that were cancelled. They keep their numbers and never count.
        </p>
        <.invoice_table
          id="cancelled-invoices"
          rows={@report.cancelled}
          paid?={false}
          cancelled?={true}
        />
      </section>
    </div>
    """
  end
end
