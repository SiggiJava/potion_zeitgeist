defmodule PotionZeitgeistWeb.InvoiceComponents do
  @moduledoc """
  The printed invoice (an A4 letter plus an optional time sheet) and small
  invoice UI helpers.
  """
  use Phoenix.Component

  # The invoice layout is plain CSS that is compiled into this module and sent
  # inline with the letter, see the notes at the top of invoice.css.
  @invoice_css_path Path.join(__DIR__, "invoice.css")
  @external_resource @invoice_css_path
  @invoice_style Phoenix.HTML.raw("<style>\n" <> File.read!(@invoice_css_path) <> "</style>")

  @doc """
  The `<style>` element with the invoice layout. `letter/1` brings it along;
  pages that style more than the letter with it, such as the print page,
  can include it themselves.
  """
  def invoice_style, do: @invoice_style

  @doc """
  Renders an invoice letter built by `PotionZeitgeist.Invoicing.Letter.build/2`
  as A4 sheets. The sheets are white paper in both themes and print one per page.

  The letter brings its own styles and uses only the `inv-*` classes of
  invoice.css, so it looks the same whatever stylesheet the page has loaded.
  """
  attr :letter, :map, required: true
  attr :id, :string, default: "invoice-letter"
  attr :style, :boolean, default: true, doc: "false when the page includes `invoice_style/0`"

  def letter(assigns) do
    ~H"""
    <div id={@id} class="inv-document">
      {if @style, do: invoice_style()}
      <article class="inv-sheet">
        <.watermark :if={@letter.watermark} text={@letter.watermark} />

        <div class="inv-head">
          <div class="inv-sender inv-pre" phx-no-format>{@letter.sender}</div>

          <div class="inv-address">
            <div :if={@letter.sender_line != ""} class="inv-return">{@letter.sender_line}</div>
            <div class="inv-recipient inv-pre" phx-no-format>{@letter.recipient}</div>
          </div>

          <dl class="inv-info">
            <%= for {label, value} <- @letter.info do %>
              <dt>{label}</dt>
              <dd>{value}</dd>
            <% end %>
          </dl>
        </div>

        <h2 :if={@letter.subject != ""} class="inv-subject">{@letter.subject}</h2>

        <div :if={@letter.before_items != ""} class="inv-text inv-pre" phx-no-format>{@letter.before_items}</div>

        <table class="inv-table inv-items">
          <colgroup>
            <col class="inv-col-pos" />
            <col />
            <col class="inv-col-hours" />
            <col class="inv-col-rate" />
            <col class="inv-col-amount" />
          </colgroup>
          <thead>
            <tr>
              <th>Pos.</th>
              <th>Leistung</th>
              <th class="inv-num">Std.</th>
              <th class="inv-num">Stundensatz</th>
              <th class="inv-num">Betrag</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={item <- @letter.items}>
              <td>{item.position}</td>
              <td>{item.description}</td>
              <td class="inv-num">{item.hours}</td>
              <td class="inv-num">{item.rate}</td>
              <td class="inv-num">{item.amount}</td>
            </tr>
          </tbody>
          <tfoot>
            <tr
              :for={{{label, value}, index} <- Enum.with_index(@letter.totals)}
              class={index == length(@letter.totals) - 1 && "inv-total"}
            >
              <td colspan="4" class="inv-num">{label}</td>
              <td class="inv-num">{value}</td>
            </tr>
          </tfoot>
        </table>

        <p :if={@letter.tax_note} class="inv-tax-note">{@letter.tax_note}</p>

        <div :if={@letter.after_items != ""} class="inv-text inv-pre" phx-no-format>{@letter.after_items}</div>

        <.letter_footer letter={@letter} />
      </article>

      <article :if={@letter.timesheet} class="inv-sheet">
        <.watermark :if={@letter.watermark} text={@letter.watermark} />

        <h2 class="inv-subject">{@letter.timesheet.title}</h2>
        <p class="inv-subtitle">Leistungszeitraum: {@letter.timesheet.period}</p>

        <table class="inv-table inv-timesheet">
          <colgroup>
            <col class="inv-col-date" />
            <col :if={@letter.timesheet.show_user} class="inv-col-user" />
            <col :if={@letter.timesheet.show_project} class="inv-col-project" />
            <col />
            <col class="inv-col-duration" />
          </colgroup>
          <thead>
            <tr>
              <th>Datum</th>
              <th :if={@letter.timesheet.show_user}>Mitarbeiter</th>
              <th :if={@letter.timesheet.show_project}>Leistung</th>
              <th>Tätigkeit</th>
              <th class="inv-num">Dauer (Std.)</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @letter.timesheet.rows}>
              <td class="inv-nowrap">{row.date}</td>
              <td :if={@letter.timesheet.show_user}>{row.user}</td>
              <td :if={@letter.timesheet.show_project}>{row.project}</td>
              <td>{row.notes}</td>
              <td class="inv-num">{row.duration}</td>
            </tr>
          </tbody>
          <tfoot>
            <tr class="inv-total">
              <td colspan={
                2 + if(@letter.timesheet.show_user, do: 1, else: 0) +
                  if(@letter.timesheet.show_project, do: 1, else: 0)
              }>
                Summe
              </td>
              <td class="inv-num">{@letter.timesheet.total}</td>
            </tr>
          </tfoot>
        </table>
      </article>
    </div>
    """
  end

  @doc """
  The bar above the invoice on the print page, with its own styles and
  script, so it works without app.css and app.js.
  """
  attr :back, :string, required: true, doc: "the path of the invoice page"

  def print_toolbar(assigns) do
    ~H"""
    <div class="inv-toolbar">
      <a href={@back} class="inv-button">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          aria-hidden="true"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M10.5 19.5 3 12m0 0 7.5-7.5M3 12h18"
          />
        </svg>
        Back to invoice
      </a>
      <div class="inv-toolbar-end">
        <span class="inv-toolbar-hint">
          For a PDF, choose "Save as PDF" in the print dialog and keep the scale at 100 %.
        </span>
        <button id="print-invoice" type="button" class="inv-button inv-button-primary">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
            aria-hidden="true"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M6.72 13.829c-.24.03-.48.062-.72.096m.72-.096a42.415 42.415 0 0 1 10.56 0m-10.56 0L6.34 18m10.94-4.171c.24.03.48.062.72.096m-.72-.096L17.66 18m0 0 .229 2.523a1.125 1.125 0 0 1-1.12 1.227H7.231c-.662 0-1.18-.568-1.12-1.227L6.34 18m11.318 0h1.091A2.25 2.25 0 0 0 21 15.75V9.456c0-1.081-.768-2.015-1.837-2.175a48.055 48.055 0 0 0-1.913-.247M6.34 18H5.25A2.25 2.25 0 0 1 3 15.75V9.456c0-1.081.768-2.015 1.837-2.175a48.041 48.041 0 0 1 1.913-.247m10.5 0a48.536 48.536 0 0 0-10.5 0m10.5 0V3.375c0-.621-.504-1.125-1.125-1.125h-8.25c-.621 0-1.125.504-1.125 1.125v3.659M18 10.5h.008v.008H18V10.5Zm-3 0h.008v.008H15V10.5Z"
            />
          </svg>
          Print / Save as PDF
        </button>
      </div>
    </div>
    <script>
      document.getElementById("print-invoice").addEventListener("click", function () {
        // Print with the invoice font, not a fallback that is still loading.
        var ready = document.fonts ? document.fonts.ready : Promise.resolve();
        ready.then(function () { window.print(); });
      });
    </script>
    """
  end

  @doc """
  The footer and the watermark of a letter once more, for the print page to
  put directly into `<body>`. Only these copies are printed there: Chromium
  repeats fixed boxes on every page only from `<body>`, see invoice.css.
  """
  attr :letter, :map, required: true

  def print_repeats(assigns) do
    ~H"""
    <.letter_footer letter={@letter} class="inv-page-footer" />
    <.watermark :if={@letter.watermark} text={@letter.watermark} class="inv-page-watermark" />
    """
  end

  attr :letter, :map, required: true
  attr :class, :string, default: nil

  defp letter_footer(assigns) do
    ~H"""
    <footer class={["inv-footer", @class]}>
      <div :if={@letter.tax_id != ""}>{@letter.tax_id}</div>
      <div :if={@letter.footer != ""} class="inv-pre" phx-no-format>{@letter.footer}</div>
    </footer>
    """
  end

  attr :text, :string, required: true
  attr :class, :string, default: nil

  defp watermark(assigns) do
    ~H"""
    <div aria-hidden="true" class={["inv-watermark", @class]}>
      <span>{@text}</span>
    </div>
    """
  end

  @doc "A badge for an invoice status."
  attr :status, :string, required: true

  def invoice_status(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm",
      @status == "draft" && "badge-warning",
      @status == "issued" && "badge-success",
      @status == "cancelled" && "badge-ghost"
    ]}>
      {status_label(@status)}
    </span>
    """
  end

  def status_label("draft"), do: "Draft"
  def status_label("issued"), do: "Issued"
  def status_label("cancelled"), do: "Cancelled"
end
