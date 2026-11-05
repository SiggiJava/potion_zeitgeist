defmodule PotionZeitgeistWeb.AnnualReportHTML do
  @moduledoc """
  The print page of the annual report, in German like the invoices: the key
  figures of the year, one row per invoice with the sums of the year, the
  items of each invoice, and the invoices that do not count.
  """
  use PotionZeitgeistWeb, :html

  import PotionZeitgeistWeb.ReportComponents

  alias PotionZeitgeist.Invoicing.{AnnualReport, Format}

  def print(assigns) do
    ~H"""
    <.report_toolbar back={~p"/admin/invoices/annual?#{[year: @report.year, basis: @report.basis]}"} />

    <main class="rpt-main">
      <article id="annual-report" class="rpt-paper">
        <header>
          <h1>Einnahmenübersicht {@report.year}</h1>
          <p class="rpt-lead">{basis_text(@report)}</p>
          <p class="rpt-muted rpt-small">Stand: {Format.date(@today)}</p>
        </header>

        <dl id="report-summary" class="rpt-summary">
          <div>
            <dt>Rechnungen</dt>
            <dd>{@report.totals.count}</dd>
          </div>
          <div :if={@report.totals.time?}>
            <dt>Zeit</dt>
            <dd>{Format.hours(@report.totals.hours)} Std.</dd>
          </div>
          <div :if={@report.totals.time? && @report.totals.other?}>
            <dt>Betrag Zeit</dt>
            <dd>{Format.money(@report.totals.time_amount)}</dd>
          </div>
          <div :if={@report.totals.other?}>
            <dt>Einzelposten</dt>
            <dd>{Format.money(@report.totals.other_amount)}</dd>
          </div>
          <%= if @report.vat? do %>
            <div>
              <dt>Netto</dt>
              <dd>{Format.money(@report.totals.net)}</dd>
            </div>
            <div>
              <dt>Umsatzsteuer</dt>
              <dd>{Format.money(@report.totals.vat)}</dd>
            </div>
          <% end %>
          <div class="rpt-total">
            <dt>{if @report.vat?, do: "Brutto #{@report.year}", else: "Summe #{@report.year}"}</dt>
            <dd id="report-sum">{Format.money(@report.totals.gross)}</dd>
          </div>
        </dl>

        <%= if @report.invoices == [] do %>
          <p id="report-empty" class="rpt-empty">{empty_text(@report)}</p>
        <% else %>
          <h2>Rechnungen</h2>
          <table id="report-invoices" class="rpt-table">
            <thead>
              <tr>
                <th>Nr.</th>
                <th>Datum</th>
                <th>Bezahlt am</th>
                <th>Empfänger</th>
                <th class="rpt-num">Stunden</th>
                <th :if={@report.vat?} class="rpt-num">Netto</th>
                <th :if={@report.vat?} class="rpt-num">USt</th>
                <th class="rpt-num">{if @report.vat?, do: "Brutto", else: "Betrag"}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @report.invoices}>
                <td class="rpt-nowrap">{row.number}</td>
                <td class="rpt-nowrap">{Format.date(row.invoice_date)}</td>
                <td class="rpt-nowrap">{Format.date(row.paid_on)}</td>
                <td class="rpt-wrap">{row.recipient}</td>
                <td class="rpt-num">{Format.hours(row.hours)}</td>
                <td :if={@report.vat?} class="rpt-num">{Format.money(row.net)}</td>
                <td :if={@report.vat?} class="rpt-num">{Format.money(row.vat)}</td>
                <td class="rpt-num">{Format.money(row.gross)}</td>
              </tr>
            </tbody>
            <tfoot>
              <tr class="rpt-grand">
                <td colspan="4">
                  Summe {@report.year} ({AnnualReport.count_label(@report.totals.count)})
                </td>
                <td class="rpt-num">{Format.hours(@report.totals.hours)}</td>
                <td :if={@report.vat?} class="rpt-num">{Format.money(@report.totals.net)}</td>
                <td :if={@report.vat?} class="rpt-num">{Format.money(@report.totals.vat)}</td>
                <td class="rpt-num">{Format.money(@report.totals.gross)}</td>
              </tr>
            </tfoot>
          </table>

          <%!-- The heading sits in the first block, which is not split over
               pages, so it never ends a page alone (Safari ignores
               break-after). --%>
          <section
            :for={{row, index} <- Enum.with_index(@report.invoices)}
            id={"report-invoice-#{row.id}"}
            class="rpt-invoice"
          >
            <%= if index == 0 do %>
              <h2>Positionen</h2>
              <p class="rpt-intro rpt-intro-items">
                Zeit in Stunden zum Stundensatz und Einzelposten wie auf den Rechnungen, Beträge netto.
              </p>
            <% end %>
            <div class="rpt-invoice-head">
              <h3>Rechnung {row.number} vom {Format.date(row.invoice_date)} · {row.recipient}</h3>
              <span class="rpt-muted rpt-small">{invoice_details(row)}</span>
            </div>
            <table class="rpt-table">
              <thead>
                <tr>
                  <th style="width: 9mm">Pos.</th>
                  <th>Bezeichnung</th>
                  <th class="rpt-num" style="width: 18mm">Menge</th>
                  <th style="width: 15mm">Einheit</th>
                  <th class="rpt-num" style="width: 24mm">Einzelpreis</th>
                  <th class="rpt-num" style="width: 26mm">Betrag</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={item <- row.items}>
                  <td>{item.position}</td>
                  <td class="rpt-wrap">{item.description}</td>
                  <td class="rpt-num">{quantity(item)}</td>
                  <td>{item.unit}</td>
                  <td class="rpt-num">{Format.money(item.price)}</td>
                  <td class="rpt-num">{Format.money(item.amount)}</td>
                </tr>
              </tbody>
              <tfoot>
                <%= if row.vat? do %>
                  <tr>
                    <td colspan="5">Nettobetrag</td>
                    <td class="rpt-num">{Format.money(row.net)}</td>
                  </tr>
                  <tr>
                    <td colspan="5">Umsatzsteuer {Format.percent(row.vat_rate)}</td>
                    <td class="rpt-num">{Format.money(row.vat)}</td>
                  </tr>
                <% end %>
                <tr>
                  <td colspan="5">Gesamtbetrag</td>
                  <td class="rpt-num">{Format.money(row.gross)}</td>
                </tr>
              </tfoot>
            </table>
          </section>
        <% end %>

        <%= if @report.unpaid != [] do %>
          <h2>Noch nicht bezahlt</h2>
          <p class="rpt-intro">
            Ausgestellt bis {@report.year}, ohne Zahlungseingang. Sie zählen erst im Jahr, in dem
            ihre Zahlung eingeht, und sind oben nicht enthalten.
          </p>
          <.other_invoices id="report-unpaid" rows={@report.unpaid} />
        <% end %>

        <%= if @report.paid_later != [] do %>
          <h2>{@report.year} ausgestellt, später bezahlt</h2>
          <p class="rpt-intro">
            Sie zählen im Jahr ihrer Zahlung und sind oben nicht enthalten.
          </p>
          <.other_invoices id="report-paid-later" rows={@report.paid_later} paid?={true} />
        <% end %>

        <%= if @report.cancelled != [] do %>
          <h2>Stornierte Rechnungen {@report.year}</h2>
          <p class="rpt-intro">
            Sie behalten ihre Nummer, zählen aber nicht und sind oben nicht enthalten.
          </p>
          <.other_invoices
            id="report-cancelled"
            rows={@report.cancelled}
            paid?={true}
            cancelled?={true}
          />
        <% end %>

        <div class="rpt-notes">
          <p :if={@report.basis == "invoice"}>
            Diese Übersicht zählt nach Rechnungsdatum. In der Einnahmenüberschussrechnung zählen
            Einnahmen im Jahr ihres Zahlungseingangs (§ 11 EStG).
          </p>
          <p :if={@report.invoices != [] && @report.small_business?}>
            Alle Beträge ohne Umsatzsteuer: Die Rechnungen wurden als Kleinunternehmer nach
            § 19 UStG gestellt.
          </p>
          <p>
            Beträge wie auf den ausgestellten Rechnungen. Entwürfe sind nicht enthalten.
          </p>
        </div>
      </article>
    </main>
    """
  end

  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :paid?, :boolean, default: false
  attr :cancelled?, :boolean, default: false

  defp other_invoices(assigns) do
    ~H"""
    <table id={@id} class="rpt-table">
      <thead>
        <tr>
          <th>Nr.</th>
          <th>Datum</th>
          <th :if={@paid?}>Bezahlt am</th>
          <th :if={@cancelled?}>Storniert am</th>
          <th>Empfänger</th>
          <th class="rpt-num">Betrag</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @rows}>
          <td class="rpt-nowrap">{row.number}</td>
          <td class="rpt-nowrap">{Format.date(row.invoice_date)}</td>
          <td :if={@paid?} class="rpt-nowrap">{Format.date(row.paid_on)}</td>
          <td :if={@cancelled?} class="rpt-nowrap">
            {Format.date(row.cancelled_on)}
          </td>
          <td class="rpt-wrap">{row.recipient}</td>
          <td class="rpt-num">{Format.money(row.gross)}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp basis_text(%{basis: "paid", year: year}),
    do:
      "Ausgestellte Rechnungen, deren Zahlung im Jahr #{year} eingegangen ist " <>
        "(Zuflussprinzip, § 11 EStG)."

  defp basis_text(%{year: year}),
    do: "Ausgestellte Rechnungen mit Rechnungsdatum im Jahr #{year}."

  defp empty_text(%{basis: "paid", year: year}),
    do: "Im Jahr #{year} ist keine Zahlung für eine Rechnung eingegangen."

  defp empty_text(%{year: year}), do: "Im Jahr #{year} wurde keine Rechnung ausgestellt."

  defp invoice_details(row) do
    paid = if row.paid_on, do: " · bezahlt am #{Format.date(row.paid_on)}", else: ""
    "Leistungszeitraum #{row.period}" <> paid
  end

  # Time in hours with two decimals, other items with the decimals they have.
  defp quantity(%{time?: true, quantity: hours}), do: Format.hours(hours)
  defp quantity(%{quantity: quantity}), do: Format.quantity(quantity)
end
