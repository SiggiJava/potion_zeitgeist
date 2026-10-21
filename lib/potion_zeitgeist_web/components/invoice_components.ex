defmodule PotionZeitgeistWeb.InvoiceComponents do
  @moduledoc """
  The printed invoice (an A4 letter plus an optional time sheet) and small
  invoice UI helpers.
  """
  use Phoenix.Component

  @doc """
  Renders an invoice letter built by `PotionZeitgeist.Invoicing.Letter.build/2`
  as A4 sheets. The sheets are white paper in both themes and print one per page.
  """
  attr :letter, :map, required: true
  attr :id, :string, default: "invoice-letter"

  def letter(assigns) do
    ~H"""
    <div id={@id} class="invoice-document space-y-8 print:space-y-0">
      <article class="invoice-sheet">
        <.watermark :if={@letter.watermark} text={@letter.watermark} />

        <div class="flex justify-end">
          <div
            class="whitespace-pre-line text-right text-[9pt] leading-snug text-neutral-700"
            phx-no-format
          >{@letter.sender}</div>
        </div>

        <div class="mt-[8mm] flex items-start justify-between gap-[10mm]">
          <div class="w-[85mm] min-h-[40mm]">
            <div
              :if={@letter.sender_line != ""}
              class="mb-[3mm] truncate border-b border-neutral-400 pb-0.5 text-[7pt] text-neutral-600"
            >
              {@letter.sender_line}
            </div>
            <div class="whitespace-pre-line leading-snug" phx-no-format>{@letter.recipient}</div>
          </div>

          <dl class="grid grid-cols-[auto_auto] gap-x-4 gap-y-0.5 text-[9pt]">
            <%= for {label, value} <- @letter.info do %>
              <dt class="text-neutral-600">{label}</dt>
              <dd class="text-right font-medium">{value}</dd>
            <% end %>
          </dl>
        </div>

        <h2 :if={@letter.subject != ""} class="mt-[10mm] text-[12pt] font-bold">
          {@letter.subject}
        </h2>

        <div
          :if={@letter.before_items != ""}
          class="mt-[6mm] whitespace-pre-line"
          phx-no-format
        >{@letter.before_items}</div>

        <table class="invoice-items mt-[6mm] w-full border-collapse text-[9.5pt]">
          <thead>
            <tr class="border-b-2 border-neutral-800 text-left">
              <th class="w-[12mm] py-1.5 pr-2 font-semibold">Pos.</th>
              <th class="py-1.5 pr-2 font-semibold">Leistung</th>
              <th class="py-1.5 pr-2 text-right font-semibold">Std.</th>
              <th class="py-1.5 pr-2 text-right font-semibold">Stundensatz</th>
              <th class="py-1.5 text-right font-semibold">Betrag</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={item <- @letter.items} class="border-b border-neutral-300 align-top">
              <td class="py-1.5 pr-2">{item.position}</td>
              <td class="py-1.5 pr-2">{item.description}</td>
              <td class="py-1.5 pr-2 text-right tabular-nums">{item.hours}</td>
              <td class="py-1.5 pr-2 text-right tabular-nums whitespace-nowrap">{item.rate}</td>
              <td class="py-1.5 text-right tabular-nums whitespace-nowrap">{item.amount}</td>
            </tr>
          </tbody>
          <tfoot>
            <%= for {{label, value}, index} <- Enum.with_index(@letter.totals) do %>
              <tr class={
                if index == length(@letter.totals) - 1,
                  do: "border-t-2 border-neutral-800 font-bold",
                  else: ""
              }>
                <td colspan="4" class="py-1 pr-2 text-right">{label}</td>
                <td class="py-1 text-right tabular-nums whitespace-nowrap">{value}</td>
              </tr>
            <% end %>
          </tfoot>
        </table>

        <p :if={@letter.tax_note} class="mt-[4mm] text-[9pt]">{@letter.tax_note}</p>

        <div
          :if={@letter.after_items != ""}
          class="mt-[6mm] whitespace-pre-line"
          phx-no-format
        >{@letter.after_items}</div>

        <footer class="mt-auto pt-[10mm] text-center text-[7.5pt] leading-snug text-neutral-600">
          <div class="border-t border-neutral-300 pt-[3mm]">
            <div :if={@letter.tax_id != ""}>{@letter.tax_id}</div>
            <div :if={@letter.footer != ""} class="whitespace-pre-line" phx-no-format>{@letter.footer}</div>
          </div>
        </footer>
      </article>

      <article :if={@letter.timesheet} class="invoice-sheet invoice-sheet-break">
        <.watermark :if={@letter.watermark} text={@letter.watermark} />

        <h2 class="text-[12pt] font-bold">{@letter.timesheet.title}</h2>
        <p class="mt-1 text-[9pt] text-neutral-600">
          Leistungszeitraum: {@letter.timesheet.period}
        </p>

        <table class="mt-[6mm] w-full border-collapse text-[9pt]">
          <thead>
            <tr class="border-b-2 border-neutral-800 text-left">
              <th class="py-1.5 pr-2 font-semibold whitespace-nowrap">Datum</th>
              <th :if={@letter.timesheet.show_user} class="py-1.5 pr-2 font-semibold">
                Mitarbeiter
              </th>
              <th :if={@letter.timesheet.show_project} class="py-1.5 pr-2 font-semibold">
                Leistung
              </th>
              <th class="py-1.5 pr-2 font-semibold">Tätigkeit</th>
              <th class="py-1.5 text-right font-semibold whitespace-nowrap">Dauer (Std.)</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={row <- @letter.timesheet.rows}
              class="border-b border-neutral-200 align-top break-inside-avoid"
            >
              <td class="py-1 pr-2 whitespace-nowrap">{row.date}</td>
              <td :if={@letter.timesheet.show_user} class="py-1 pr-2">{row.user}</td>
              <td :if={@letter.timesheet.show_project} class="py-1 pr-2">{row.project}</td>
              <td class="py-1 pr-2">{row.notes}</td>
              <td class="py-1 text-right tabular-nums">{row.duration}</td>
            </tr>
          </tbody>
          <tfoot>
            <tr class="border-t-2 border-neutral-800 font-bold">
              <td
                colspan={
                  2 + if(@letter.timesheet.show_user, do: 1, else: 0) +
                    if(@letter.timesheet.show_project, do: 1, else: 0)
                }
                class="py-1 pr-2"
              >
                Summe
              </td>
              <td class="py-1 text-right tabular-nums">{@letter.timesheet.total}</td>
            </tr>
          </tfoot>
        </table>
      </article>
    </div>
    """
  end

  attr :text, :string, required: true

  defp watermark(assigns) do
    ~H"""
    <div
      aria-hidden="true"
      class="pointer-events-none absolute inset-0 flex items-center justify-center overflow-hidden"
    >
      <span class="-rotate-30 select-none text-[64pt] font-black tracking-widest text-neutral-900/[0.06]">
        {@text}
      </span>
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
