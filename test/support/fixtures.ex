defmodule PotionZeitgeist.Fixtures do
  @moduledoc """
  Test helpers for creating users, projects and time entries.
  """

  alias PotionZeitgeist.{Accounts, Invoicing, Projects, Repo}
  alias PotionZeitgeist.TimeTracking.TimeEntry

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        "email" => "user#{System.unique_integer([:positive])}@example.com",
        "name" => "Test User",
        "password" => "password1234",
        "role" => "user"
      })
      |> Accounts.create_user()

    user
  end

  def admin_fixture(attrs \\ %{}) do
    attrs |> Enum.into(%{"role" => "admin", "name" => "Admin"}) |> user_fixture()
  end

  def project_fixture(attrs \\ %{}) do
    {:ok, project} =
      attrs
      |> Enum.into(%{"name" => "Project #{System.unique_integer([:positive])}"})
      |> Projects.create_project()

    project
  end

  def entry_fixture(user, clock_in, clock_out, project \\ nil) do
    Repo.insert!(%TimeEntry{
      user_id: user.id,
      project_id: project && project.id,
      clock_in: NaiveDateTime.from_iso8601!(clock_in),
      clock_out: clock_out && NaiveDateTime.from_iso8601!(clock_out)
    })
  end

  def template_fixture(attrs \\ %{}) do
    {:ok, template} =
      attrs
      |> Enum.into(%{
        "name" => "Template #{System.unique_integer([:positive])}",
        "sender" => "Michael Beispiel\nHauptstraße 1\n12345 Musterstadt",
        "tax_id" => "Steuernummer: 12/345/67890",
        "subject" => "Rechnung Nr. {{rechnungsnummer}}",
        "body" => "Guten Tag,\n\n{{positionen}}\n\nBitte zahlen Sie {{gesamtbetrag}}.",
        "footer" => "IBAN: DE12 3456 7890 1234 5678 90"
      })
      |> Invoicing.create_template()

    template
  end

  @doc "Params for `Invoicing.create_draft/1` billing `entries` at one rate."
  def draft_params(template, entries, attrs \\ %{}) do
    Enum.into(attrs, %{
      "month" => "2026-10",
      "template_id" => to_string(template.id),
      "recipient" => "Kunde GmbH\nWeg 2\n10115 Berlin",
      "invoice_date" => "2026-11-02",
      "due_date" => "2026-11-16",
      "tax_mode" => "small_business",
      "rate_mode" => "single",
      "hourly_rate" => "80",
      "show_timesheet" => "true",
      "entry_ids" => Enum.map(entries, &to_string(&1.id))
    })
  end

  def draft_fixture(template, entries, attrs \\ %{}) do
    {:ok, invoice} = template |> draft_params(entries, attrs) |> Invoicing.create_draft()
    invoice
  end
end
