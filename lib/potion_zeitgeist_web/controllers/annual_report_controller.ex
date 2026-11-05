defmodule PotionZeitgeistWeb.AnnualReportController do
  use PotionZeitgeistWeb, :controller

  alias PotionZeitgeist.Invoicing
  alias PotionZeitgeist.Invoicing.AnnualReport

  # `?basis=invoice` counts invoices by invoice date, any other basis by the
  # day their payment came in, see PotionZeitgeist.Invoicing.AnnualReport.

  @doc "A CSV file of the report: one row per invoice, or per item with `?type=items`."
  def csv(conn, %{"year" => year} = params) do
    with_report(conn, year, params, fn conn, report ->
      type = if params["type"] == "items", do: "items", else: "invoices"

      csv =
        if type == "items",
          do: AnnualReport.items_csv(report),
          else: AnnualReport.invoices_csv(report)

      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header(
        "content-disposition",
        ~s(attachment; filename="#{AnnualReport.csv_filename(report, type)}")
      )
      |> send_resp(200, csv)
    end)
  end

  @doc "The report as a page of its own, to print or save as PDF."
  def print(conn, %{"year" => year} = params) do
    with_report(conn, year, params, fn conn, report ->
      conn
      |> put_root_layout(html: {PotionZeitgeistWeb.Layouts, :report})
      |> render(:print,
        report: report,
        today: Invoicing.today(),
        page_title: "Einnahmenübersicht #{report.year} #{AnnualReport.basis_title(report.basis)}"
      )
    end)
  end

  defp with_report(conn, year, params, fun) do
    case AnnualReport.parse_year(year) do
      nil ->
        conn |> put_status(:not_found) |> text("Unknown year.")

      year ->
        fun.(conn, Invoicing.annual_report(year, AnnualReport.parse_basis(params["basis"])))
    end
  end
end
