defmodule PotionZeitgeistWeb.ReportComponents do
  @moduledoc """
  The styles and the toolbar of the print page of the annual report.
  """
  use Phoenix.Component

  # Plain CSS compiled into this module and sent inline by the report
  # layout, see the notes at the top of report.css.
  @report_css_path Path.join(__DIR__, "report.css")
  @external_resource @report_css_path
  @report_style Phoenix.HTML.raw("<style>\n" <> File.read!(@report_css_path) <> "</style>")

  @doc "The `<style>` element of the report's print page."
  def report_style, do: @report_style

  @doc """
  The toolbar above the report, which is not printed: back to the report
  page, and a button to print or save as PDF.

  The button prints a moment after the click and the page runs no script
  while it prints: Safari prints blank pages when `print()` runs within the
  click (see `PotionZeitgeistWeb.InvoiceComponents.print_toolbar/1`). It
  waits for the report font, so the PDF does not use a fallback font.
  """
  attr :back, :string, required: true, doc: "the path of the report page"

  def report_toolbar(assigns) do
    ~H"""
    <div class="rpt-toolbar">
      <a href={@back} class="rpt-button">
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
        Back to the annual report
      </a>
      <div class="rpt-toolbar-end">
        <span class="rpt-toolbar-hint">
          For a PDF, choose "Save as PDF" in the print dialog. In Safari, also turn off
          "Print headers and footers".
        </span>
        <button id="print-report" type="button" class="rpt-button rpt-button-primary">
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
      (function () {
        var printRequested = false;

        function printReport() {
          setTimeout(function () {
            printRequested = false;
            window.print();
          }, 200);
        }

        document.getElementById("print-report").addEventListener("click", function () {
          if (printRequested) return;
          printRequested = true;
          if (!document.fonts || document.fonts.status === "loaded") printReport();
          else document.fonts.ready.then(printReport);
        });
      })();
    </script>
    """
  end
end
