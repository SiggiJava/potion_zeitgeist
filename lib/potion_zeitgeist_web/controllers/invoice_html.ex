defmodule PotionZeitgeistWeb.InvoiceHTML do
  use PotionZeitgeistWeb, :html

  import PotionZeitgeistWeb.InvoiceComponents

  def print(assigns) do
    ~H"""
    <.print_toolbar back={~p"/admin/invoices/#{@invoice}"} />

    <main class="inv-print-main">
      <.letter letter={@letter} style={false} />
    </main>

    <.print_repeats letter={@letter} />
    """
  end
end
