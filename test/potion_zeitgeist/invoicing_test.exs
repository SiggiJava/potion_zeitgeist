defmodule PotionZeitgeist.InvoicingTest do
  use PotionZeitgeist.DataCase, async: true

  import PotionZeitgeist.Fixtures

  alias PotionZeitgeist.{Accounts, Invoicing, TimeTracking}

  setup do
    user = user_fixture(%{"name" => "Michael"})
    website = project_fixture(%{"name" => "Website"})
    app = project_fixture(%{"name" => "App"})

    entries = [
      entry_fixture(user, "2026-10-01 08:00:00", "2026-10-01 12:00:00", website),
      entry_fixture(user, "2026-10-02 08:00:00", "2026-10-02 09:30:00", website),
      entry_fixture(user, "2026-10-02 10:00:00", "2026-10-02 11:00:00", app)
    ]

    %{user: user, website: website, app: app, entries: entries, template: template_fixture()}
  end

  describe "billable entries" do
    test "only completed entries of the month that are not invoiced", ctx do
      entry_fixture(ctx.user, "2026-09-30 08:00:00", "2026-09-30 09:00:00")
      entry_fixture(ctx.user, "2026-11-01 00:00:00", "2026-11-01 01:00:00")
      entry_fixture(ctx.user, "2026-10-20 08:00:00", nil)

      assert ids(Invoicing.billable_entries(~D[2026-10-15])) == ids(ctx.entries)
      assert Invoicing.running_entry_count(~D[2026-10-01]) == 1

      [first | rest] = ctx.entries
      draft = draft_fixture(ctx.template, [first])

      assert ids(Invoicing.billable_entries(~D[2026-10-01])) == ids(rest)
      # The draft being edited still sees its own entries.
      assert ids(Invoicing.billable_entries(~D[2026-10-01], draft)) == ids(ctx.entries)
    end

    test "month choices list months with unbilled time", ctx do
      entry_fixture(ctx.user, "2026-07-10 08:00:00", "2026-07-10 08:30:00")

      assert [{~D[2026-11-01], 0}, {~D[2026-10-01], 390}, {~D[2026-07-01], 30}] =
               Invoicing.month_choices(~D[2026-11-05])

      # The month the form shows is always one of the choices.
      assert {~D[2026-04-01], 0} in Invoicing.month_choices(~D[2026-11-05], nil, ~D[2026-04-01])
    end
  end

  describe "drafts" do
    test "bill the selected entries per project at one rate", ctx do
      draft = draft_fixture(ctx.template, ctx.entries, %{"hourly_rate" => "85,5"})

      assert draft.status == "draft"
      assert draft.number == nil
      assert draft.period_start == ~D[2026-10-01]
      assert draft.period_end == ~D[2026-10-31]

      assert [
               %{position: 1, description: "App", minutes: 60} = app,
               %{position: 2, description: "Website", minutes: 330} = website
             ] = draft.items

      assert Decimal.equal?(app.amount, Decimal.new("85.50"))
      assert Decimal.equal?(website.hours, Decimal.new("5.50"))
      assert Decimal.equal?(website.amount, Decimal.new("470.25"))
      assert Decimal.equal?(draft.gross_total, Decimal.new("555.75"))
      assert Decimal.equal?(draft.vat_rate, 0)
    end

    test "bill per project rates and descriptions", ctx do
      params =
        draft_params(ctx.template, ctx.entries, %{
          "rate_mode" => "per_project",
          "hourly_rate" => "",
          "rates" => %{to_string(ctx.website.id) => "100", to_string(ctx.app.id) => "50"},
          "descriptions" => %{to_string(ctx.website.id) => "Website-Relaunch"}
        })

      missing = put_in(params, ["rates", to_string(ctx.app.id)], "")
      assert {:error, changeset} = Invoicing.create_draft(missing)

      assert %{rates: ["enter an hourly rate above 0 and below 100,000,000 for every project"]} =
               errors_on(changeset)

      assert {:ok, draft} = Invoicing.create_draft(params)
      assert [%{description: "App"} = app, %{description: "Website-Relaunch"} = web] = draft.items
      assert Decimal.equal?(app.amount, Decimal.new("50.00"))
      assert Decimal.equal?(web.amount, Decimal.new("550.00"))
    end

    test "with VAT", ctx do
      params =
        draft_params(ctx.template, ctx.entries, %{"tax_mode" => "standard", "vat_rate" => ""})

      assert {:error, changeset} = Invoicing.create_draft(params)
      assert %{vat_rate: [_]} = errors_on(changeset)

      draft =
        draft_fixture(ctx.template, ctx.entries, %{"tax_mode" => "standard", "vat_rate" => "19"})

      assert Decimal.equal?(draft.net_total, Decimal.new("520.00"))
      assert Decimal.equal?(draft.vat_total, Decimal.new("98.80"))
      assert Decimal.equal?(draft.gross_total, Decimal.new("618.80"))
    end

    test "read only the rate fields of the chosen modes", ctx do
      # The form keeps what was typed into fields it no longer shows.
      draft =
        draft_fixture(ctx.template, ctx.entries, %{
          "rate_mode" => "per_project",
          "hourly_rate" => "85 €",
          "rates" => %{to_string(ctx.website.id) => "100", to_string(ctx.app.id) => "50"},
          "tax_mode" => "small_business",
          "vat_rate" => "19 %"
        })

      assert draft.hourly_rate == nil
      assert Decimal.equal?(draft.vat_rate, 0)

      # A single rate cleared later is a missing rate, not a crash.
      :ok = Invoicing.delete_draft(draft)
      single = draft_fixture(ctx.template, ctx.entries)

      assert {:error, changeset} =
               Invoicing.update_draft(
                 single,
                 draft_params(ctx.template, ctx.entries, %{"hourly_rate" => ""})
               )

      assert %{hourly_rate: ["is needed for one rate for all"]} = errors_on(changeset)
    end

    test "store the VAT rate with two decimals and compute with that rate", ctx do
      draft =
        draft_fixture(ctx.template, ctx.entries, %{
          "tax_mode" => "standard",
          "vat_rate" => "7,125"
        })

      assert Decimal.equal?(draft.vat_rate, Decimal.new("7.13"))
      # 520.00 net at 7.13 %
      assert Decimal.equal?(draft.vat_total, Decimal.new("37.08"))

      # The live summary shows the same rate and amounts.
      preview =
        Invoicing.preview(Invoicing.billable_entries(~D[2026-10-01], draft), %{
          "tax_mode" => "standard",
          "vat_rate" => "7,125",
          "hourly_rate" => "80"
        })

      assert Decimal.equal?(preview.vat_rate, draft.vat_rate)
      assert Decimal.equal?(preview.totals.gross, draft.gross_total)

      for {rate, message} <- [
            {"99,999", "must be less than 100"},
            {"0,001", "is needed when charging VAT"},
            {"19 %", "is invalid"},
            {"inf", "is invalid"},
            {"1e2", "is invalid"}
          ] do
        params =
          draft_params(ctx.template, ctx.entries, %{"tax_mode" => "standard", "vat_rate" => rate})

        assert {:error, changeset} = Invoicing.create_draft(params)
        assert %{vat_rate: [^message]} = errors_on(changeset)
      end
    end

    test "reject rates and totals too large to store", ctx do
      rates = %{to_string(ctx.website.id) => "100000000", to_string(ctx.app.id) => "50"}

      assert {:error, changeset} =
               Invoicing.create_draft(
                 draft_params(ctx.template, ctx.entries, %{
                   "rate_mode" => "per_project",
                   "rates" => rates
                 })
               )

      assert %{rates: [_]} = errors_on(changeset)

      for rate <- ["100000000", "inf", "NaN", "1e400000000", String.duplicate("9", 35)] do
        assert {:error, changeset} =
                 Invoicing.create_draft(
                   draft_params(ctx.template, ctx.entries, %{"hourly_rate" => rate})
                 )

        assert %{hourly_rate: [_]} = errors_on(changeset)
      end

      # 200 hours at almost 100 million an hour is more than an amount column holds.
      long = entry_fixture(ctx.user, "2026-10-03 00:00:00", "2026-10-11 08:00:00")

      assert {:error, changeset} =
               Invoicing.create_draft(
                 draft_params(ctx.template, [long], %{"hourly_rate" => "99999999"})
               )

      assert %{rates: ["the total is too large for one invoice"]} = errors_on(changeset)
    end

    test "take long item texts", ctx do
      text = String.duplicate("Entwicklung und Betreuung ", 20)

      draft =
        draft_fixture(ctx.template, ctx.entries, %{
          "descriptions" => %{to_string(ctx.website.id) => text}
        })

      assert Enum.any?(draft.items, &(&1.description == String.trim(text)))
    end

    test "report a template deleted in the meantime on the template field", ctx do
      {:ok, _} = Invoicing.delete_template(ctx.template)

      assert {:error, changeset} =
               Invoicing.create_draft(draft_params(ctx.template, ctx.entries))

      assert %{template_id: ["was deleted, pick another one"]} = errors_on(changeset)
    end

    test "deleted elsewhere cannot be saved, issued or deleted again", ctx do
      draft = draft_fixture(ctx.template, ctx.entries)
      assert :ok = Invoicing.delete_draft(draft)

      assert Invoicing.get_invoice(draft.id) == nil
      assert {:error, :not_found} = Invoicing.delete_draft(draft)

      assert {:error, :not_found} =
               Invoicing.update_draft(draft, draft_params(ctx.template, ctx.entries))

      assert {:error, :not_found} =
               Invoicing.issue_invoice(draft, %{"number" => "1", "invoice_date" => "2026-11-02"})
    end

    test "need entries, a rate and a full recipient address", ctx do
      assert {:error, changeset} =
               Invoicing.create_draft(
                 draft_params(ctx.template, [], %{"hourly_rate" => "", "recipient" => "Kunde"})
               )

      errors = errors_on(changeset)
      assert errors.entries == ["select at least one time entry"]
      assert errors.hourly_rate == ["is needed for one rate for all"]
      assert [_] = errors.recipient
    end

    test "cannot bill time twice", ctx do
      draft_fixture(ctx.template, ctx.entries)

      assert {:error, changeset} =
               Invoicing.create_draft(draft_params(ctx.template, ctx.entries))

      assert %{entries: [message]} = errors_on(changeset)
      assert message =~ "no longer available"
    end

    test "can be edited and deleted, which frees their entries", ctx do
      [first, second, third] = ctx.entries
      draft = draft_fixture(ctx.template, [first, second])

      assert {:ok, draft} =
               Invoicing.update_draft(draft, draft_params(ctx.template, [second, third]))

      assert Enum.sort(Invoicing.entry_ids(draft)) == Enum.sort([second.id, third.id])
      assert ids(Invoicing.billable_entries(~D[2026-10-01])) == [first.id]

      assert :ok = Invoicing.delete_draft(draft)
      assert length(Invoicing.billable_entries(~D[2026-10-01])) == 3
    end

    test "lock their entries against changes", ctx do
      [first | _] = ctx.entries
      draft_fixture(ctx.template, [first])

      assert {:error, :invoiced} = TimeTracking.update_entry(first, %{"notes" => "x"})
      assert {:error, :invoiced} = TimeTracking.delete_entry(first)
      assert {:error, :invoiced} = TimeTracking.set_entry_project(first, nil)

      assert [true, false, false] =
               ctx.user.id
               |> TimeTracking.list_entries()
               |> Enum.sort_by(& &1.clock_in, NaiveDateTime)
               |> Enum.map(& &1.invoiced)
    end

    test "a stale clock-out or project switch cannot change an invoiced entry", ctx do
      # Running in one tab, finished on the entries page and invoiced since.
      stale = entry_fixture(ctx.user, "2026-10-05 08:00:00", nil)

      {:ok, finished} =
        TimeTracking.update_entry(stale, %{"clock_out" => ~N[2026-10-05 12:00:00]})

      draft_fixture(ctx.template, [finished])

      assert {:error, :not_clocked_in} = TimeTracking.clock_out(stale)
      assert {:error, :not_clocked_in} = TimeTracking.switch_project(stale, ctx.app.id)
      assert Repo.reload(finished).clock_out == ~N[2026-10-05 12:00:00]
    end
  end

  describe "issuing" do
    test "assigns the number, freezes the letter and keeps entries locked", ctx do
      draft = draft_fixture(ctx.template, ctx.entries)

      assert {:ok, invoice} =
               Invoicing.issue_invoice(draft, %{
                 "number" => " 2026-001 ",
                 "invoice_date" => "2026-11-04"
               })

      assert invoice.status == "issued"
      assert invoice.number == "2026-001"
      assert invoice.invoice_date == ~D[2026-11-04]
      # The due date keeps its 14 days.
      assert invoice.due_date == ~D[2026-11-18]
      assert invoice.letter_tax_id == "Steuernummer: 12/345/67890"

      {:ok, _} =
        Invoicing.update_template(ctx.template, %{"subject" => "Neu {{rechnungsnummer}}"})

      assert Invoicing.letter(Invoicing.get_invoice!(invoice.id)).subject ==
               "Rechnung Nr. 2026-001"

      assert {:error, :not_draft} =
               Invoicing.update_draft(draft, draft_params(ctx.template, ctx.entries))

      assert {:error, :not_draft} = Invoicing.delete_draft(draft)
      assert {:error, :not_draft} = Invoicing.issue_invoice(draft, %{"number" => "2026-002"})
      assert Invoicing.billable_entries(~D[2026-10-01]) == []
    end

    test "rejects blank and duplicate numbers", ctx do
      [first, second, _] = ctx.entries
      one = draft_fixture(ctx.template, [first])
      two = draft_fixture(ctx.template, [second])

      assert {:error, changeset} =
               Invoicing.issue_invoice(one, %{"number" => " ", "invoice_date" => "2026-11-02"})

      assert %{number: ["can't be blank"]} = errors_on(changeset)

      assert {:ok, _} =
               Invoicing.issue_invoice(one, %{"number" => "A-1", "invoice_date" => "2026-11-02"})

      assert {:error, changeset} =
               Invoicing.issue_invoice(two, %{"number" => "A-1", "invoice_date" => "2026-11-02"})

      assert %{number: ["is already used by another invoice"]} = errors_on(changeset)
    end

    test "needs a letter template", ctx do
      draft = draft_fixture(ctx.template, ctx.entries)
      {:ok, _} = Invoicing.delete_template(ctx.template)

      assert {:error, changeset} =
               Invoicing.issue_invoice(Repo.reload(draft), %{
                 "number" => "2026-001",
                 "invoice_date" => "2026-11-02"
               })

      assert %{template_id: [_]} = errors_on(changeset)
    end

    test "warns about sample data and numbers out of sequence", ctx do
      [first, second, _] = ctx.entries
      sample = Invoicing.sample_template() |> Map.from_struct() |> Map.put(:name, "Sample")
      {:ok, sample} = Invoicing.create_template(sample)

      one = draft_fixture(sample, [first])
      assert [warning] = Invoicing.issue_warnings(one, %{"number" => "2026-001"})
      assert warning =~ "sample data"

      {:ok, _} =
        Invoicing.issue_invoice(draft_fixture(ctx.template, [second]), %{
          "number" => "2026-005",
          "invoice_date" => "2026-11-02"
        })

      two = draft_fixture(ctx.template, [Enum.at(ctx.entries, 2)])

      assert [] =
               Invoicing.issue_warnings(two, %{
                 "number" => "2026-006",
                 "invoice_date" => "2026-11-03"
               })

      assert [skipped, earlier] =
               Invoicing.issue_warnings(two, %{
                 "number" => "2026-009",
                 "invoice_date" => "2026-10-30"
               })

      assert skipped =~ "2026-006"
      assert earlier =~ "before invoice 2026-005"
    end

    test "the time sheet survives deleting the user", ctx do
      {:ok, entry} = TimeTracking.update_entry(hd(ctx.entries), %{"notes" => "Startseite"})
      draft = draft_fixture(ctx.template, [entry])

      {:ok, invoice} =
        Invoicing.issue_invoice(draft, %{"number" => "1", "invoice_date" => "2026-11-02"})

      {:ok, _} = Accounts.delete_user(ctx.user)

      sheet = Invoicing.letter(Invoicing.get_invoice!(invoice.id)).timesheet

      assert [%{date: "01.10.2026", duration: "4:00", notes: "Startseite", project: "Website"}] =
               sheet.rows
    end
  end

  describe "cancelling" do
    test "keeps the number and frees the entries", ctx do
      draft = draft_fixture(ctx.template, ctx.entries)

      {:ok, invoice} =
        Invoicing.issue_invoice(draft, %{"number" => "2026-001", "invoice_date" => "2026-11-02"})

      assert {:ok, cancelled} = Invoicing.cancel_invoice(invoice)
      assert cancelled.status == "cancelled"
      assert cancelled.number == "2026-001"
      assert {:error, :not_issued} = Invoicing.cancel_invoice(cancelled)

      assert length(Invoicing.billable_entries(~D[2026-10-01])) == 3
      assert {:ok, _} = TimeTracking.update_entry(hd(ctx.entries), %{"notes" => "fixed"})

      # A cancelled number is never suggested again.
      assert Invoicing.suggest_number(~D[2026-11-05]) == "2026-002"
      assert Invoicing.letter(cancelled).watermark == "STORNIERT"
    end
  end

  describe "invoice numbers" do
    test "keep prefixes with umlauts and other non-ASCII characters" do
      assert Invoicing.next_number("KÜ-2026-007", 2026) == "KÜ-2026-008"
      assert Invoicing.next_number("KÜ-2026-007", 2027) == "KÜ-2027-001"
      assert Invoicing.next_number("№2025-01", 2026) == "№2026-01"
    end

    test "follow the last number and start over in a new year" do
      assert Invoicing.next_number(nil, 2026) == "2026-001"
      assert Invoicing.next_number("2026-007", 2026) == "2026-008"
      assert Invoicing.next_number("2026-099", 2026) == "2026-100"
      assert Invoicing.next_number("2025-042", 2026) == "2026-001"
      assert Invoicing.next_number("RE-2025-0043", 2026) == "RE-2026-0001"
      assert Invoicing.next_number("RE-2026-0043", 2026) == "RE-2026-0044"
      assert Invoicing.next_number("17", 2026) == "18"
      assert Invoicing.next_number("ABC", 2026) == "2026-001"
    end

    test "suggestions skip numbers already used", ctx do
      [first, second, _] = ctx.entries

      {:ok, _} =
        Invoicing.issue_invoice(draft_fixture(ctx.template, [first]), %{
          "number" => "2026-002",
          "invoice_date" => "2026-11-02"
        })

      {:ok, _} =
        Invoicing.issue_invoice(draft_fixture(ctx.template, [second]), %{
          "number" => "2026-001",
          "invoice_date" => "2026-11-02"
        })

      assert Invoicing.suggest_number(~D[2026-11-02]) == "2026-003"
    end
  end

  describe "form values" do
    test "a new invoice can start from an earlier one", ctx do
      params =
        draft_params(ctx.template, ctx.entries, %{
          "rate_mode" => "per_project",
          "rates" => %{to_string(ctx.website.id) => "100", to_string(ctx.app.id) => "50"},
          "descriptions" => %{to_string(ctx.website.id) => "Website-Relaunch"},
          "due_date" => "2026-12-02"
        })

      {:ok, base} = Invoicing.create_draft(params)

      # A newer invoice for another client bills the same project differently.
      later = entry_fixture(ctx.user, "2026-11-03 08:00:00", "2026-11-03 10:00:00", ctx.website)

      draft_fixture(ctx.template, [later], %{
        "month" => "2026-11",
        "recipient" => "Andere AG\nAllee 1\n20095 Hamburg",
        "rate_mode" => "per_project",
        "rates" => %{to_string(ctx.website.id) => "120"},
        "descriptions" => %{to_string(ctx.website.id) => "Wartung"}
      })

      assert Invoicing.new_invoice_params(~D[2026-12-03])["rates"][to_string(ctx.website.id)] ==
               "120"

      new = Invoicing.new_invoice_params(~D[2026-12-03], base)
      assert new["month"] == "2026-11"
      assert new["recipient"] == base.recipient
      assert new["rate_mode"] == "per_project"
      assert new["rates"][to_string(ctx.website.id)] == "100"
      assert new["descriptions"][to_string(ctx.website.id)] == "Website-Relaunch"
      # Same payment term of 30 days.
      assert new["due_date"] == "2027-01-02"

      fresh = Invoicing.new_invoice_params(~D[2026-12-03])
      assert fresh["recipient"] == ""
      assert fresh["tax_mode"] == "small_business"
    end
  end

  test "templates need sender, tax number and text" do
    assert {:error, changeset} = Invoicing.create_template(%{"name" => "X"})
    assert %{sender: [_], tax_id: [_], body: [_]} = errors_on(changeset)
  end

  defp ids(entries), do: Enum.map(entries, & &1.id)
end
