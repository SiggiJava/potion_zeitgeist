defmodule PotionZeitgeistWeb.InvoiceHTML do
  use PotionZeitgeistWeb, :html

  import PotionZeitgeistWeb.InvoiceComponents

  def print(assigns) do
    ~H"""
    <div class="sticky top-0 z-10 flex flex-wrap items-center justify-between gap-3 border-b border-neutral-300 bg-white/90 px-4 py-2 text-neutral-900 backdrop-blur print:hidden">
      <.link navigate={~p"/admin/invoices/#{@invoice}"} class="btn btn-ghost btn-sm gap-2">
        <.icon name="hero-arrow-left" class="size-4" /> Back to invoice
      </.link>
      <div class="flex items-center gap-3">
        <span class="hidden text-sm text-neutral-600 md:inline">
          For a PDF, choose "Save as PDF" in the print dialog, scale 100 %, no headers and footers.
        </span>
        <button id="print-invoice" type="button" data-print class="btn btn-primary btn-sm gap-2">
          <.icon name="hero-printer" class="size-4" /> Print / Save as PDF
        </button>
      </div>
    </div>

    <div class="overflow-x-auto py-8 print:overflow-visible print:py-0">
      <.letter letter={@letter} />
    </div>
    """
  end
end
