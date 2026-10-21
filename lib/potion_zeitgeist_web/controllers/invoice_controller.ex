defmodule PotionZeitgeistWeb.InvoiceController do
  use PotionZeitgeistWeb, :controller

  alias PotionZeitgeist.Invoicing
  alias PotionZeitgeist.Invoicing.Letter

  def print(conn, %{"id" => id}) do
    invoice = Invoicing.get_invoice!(id)

    conn
    |> put_root_layout(html: {PotionZeitgeistWeb.Layouts, :print})
    |> render(:print,
      invoice: invoice,
      letter: Invoicing.letter(invoice),
      page_title: Letter.document_title(invoice)
    )
  end
end
