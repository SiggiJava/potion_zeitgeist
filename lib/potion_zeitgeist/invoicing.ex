defmodule PotionZeitgeist.Invoicing do
  @moduledoc """
  Invoices for booked project time, and the letter templates they are printed with.

  An invoice bills the time entries of a month, one item per project, and
  can have other items entered on the form, such as material or flat fees
  (see `PotionZeitgeist.Invoicing.ManualItem`), or only those.

  An invoice starts as a draft that can be edited and deleted. Issuing it
  assigns the invoice number and freezes the letter texts. An issued invoice
  can only be cancelled, which keeps it and its number but frees its time
  entries for a new invoice. Time entries on a draft or issued invoice can
  neither be billed again nor be changed.
  """

  import Ecto.Query

  alias PotionZeitgeist.Repo
  alias PotionZeitgeist.Invoicing.{Calculation, Invoice, InvoiceEntry, InvoiceItem}
  alias PotionZeitgeist.Invoicing.{InvoiceTemplate, Letter, LetterLayout, ManualItem}
  alias PotionZeitgeist.TimeTracking.TimeEntry

  @payment_days 14
  @default_vat_rate "19"

  # Rates below this fit the numeric(10,2) rate columns, and totals below the
  # second limit fit the numeric(12,2) amount columns.
  @max_rate Decimal.new(100_000_000)
  @max_amount Decimal.new(10_000_000_000)

  # Texts of the sample template that must not end up on a real invoice.
  @sample_markers ["Mustermann", "Musterstraße", "DE00 0000", "000/000/00000", "example.com"]

  ## Templates

  def list_templates do
    Repo.all(from t in InvoiceTemplate, order_by: [asc: t.name])
  end

  def get_template!(id), do: Repo.get!(InvoiceTemplate, id)

  @doc "Like `get_template!/1`, but `nil` when the template does not exist (any more)."
  def get_template(id), do: Repo.get(InvoiceTemplate, id)

  # The template functions take the date of the sample letter that texts are
  # measured with, see `InvoiceTemplate.changeset/3`; the form passes the
  # date of its preview.
  def create_template(attrs, today \\ today()) do
    %InvoiceTemplate{}
    |> InvoiceTemplate.changeset(attrs, today)
    |> Repo.insert()
  end

  def update_template(%InvoiceTemplate{} = template, attrs, today \\ today()) do
    template
    |> InvoiceTemplate.changeset(attrs, today)
    |> Repo.update()
  end

  @doc """
  Deletes a template. Issued invoices keep their letter texts; drafts that
  used the template need another one before they can be issued.
  """
  def delete_template(%InvoiceTemplate{} = template), do: Repo.delete(template)

  def change_template(%InvoiceTemplate{} = template, attrs \\ %{}, today \\ today()) do
    InvoiceTemplate.changeset(template, attrs, today)
  end

  @doc """
  A German sample letter to start a new template from. The § 19 UStG note,
  number, date and service period are part of the fixed layout, so the
  sample does not repeat them. The due date is optional, so the sample
  names it in a block that is left out without one.
  """
  def sample_template do
    %InvoiceTemplate{
      name: "Standard",
      sender: """
      Max Mustermann
      Musterstraße 1
      12345 Musterstadt
      Telefon: 0123 456789
      E-Mail: max@example.com\
      """,
      tax_id: "Steuernummer: 000/000/00000",
      subject: "Rechnung Nr. {{rechnungsnummer}}",
      body: """
      Sehr geehrte Damen und Herren,

      für meine Leistungen im Zeitraum {{leistungszeitraum}} berechne ich Ihnen:

      {{positionen}}

      Bitte überweisen Sie den Betrag von {{gesamtbetrag}}{{#faellig_am}} bis zum {{faellig_am}}{{/faellig_am}} unter Angabe der Rechnungsnummer {{rechnungsnummer}} auf das unten genannte Konto.

      Mit freundlichen Grüßen

      Max Mustermann\
      """,
      footer:
        "Kontoinhaber: Max Mustermann · Musterbank · IBAN: DE00 0000 0000 0000 0000 00 · BIC: XXXXXXXXXXX"
    }
  end

  ## Reading invoices

  def list_invoices do
    Repo.all(
      from i in Invoice,
        order_by: [
          asc: fragment("CASE WHEN ? = 'draft' THEN 0 ELSE 1 END", i.status),
          desc: i.invoice_date,
          desc: i.id
        ]
    )
  end

  def get_invoice!(id) do
    Invoice |> Repo.get!(id) |> Repo.preload([:items, :template])
  end

  @doc "Like `get_invoice!/1`, but `nil` when the invoice does not exist (any more)."
  def get_invoice(id) do
    case Repo.get(Invoice, id) do
      nil -> nil
      invoice -> Repo.preload(invoice, [:items, :template])
    end
  end

  @doc "The time sheet rows of an invoice, as stored when it was saved."
  def list_invoice_entries(%Invoice{id: id}) do
    Repo.all(
      from ie in InvoiceEntry,
        where: ie.invoice_id == ^id,
        order_by: [asc: ie.date, asc: ie.id]
    )
  end

  @doc "The letter of an invoice as printed, see `PotionZeitgeist.Invoicing.Letter.build/2`."
  def letter(%Invoice{} = invoice) do
    Letter.build(invoice, list_invoice_entries(invoice))
  end

  @doc """
  Today's date in Germany, where invoices are written. Taken from the
  database, so the app needs no time zone data.
  """
  def today do
    %{rows: [[date]]} = Repo.query!("SELECT (now() AT TIME ZONE 'Europe/Berlin')::date")
    date
  end

  ## Billable time

  @doc "First and last day of the month `date` falls into."
  def month_range(%Date{} = date) do
    {Date.beginning_of_month(date), Date.end_of_month(date)}
  end

  @doc """
  Completed time entries of all users with a clock-in in the month of `month`
  that are not on another draft or issued invoice. Entries already on
  `invoice` (when editing a draft) are included. Days count by clock-in date
  (UTC), as in the CSV export.
  """
  def billable_entries(%Date{} = month, invoice \\ nil, opts \\ []) do
    {first, last} = month_range(month)

    from(e in TimeEntry,
      as: :entry,
      where: not is_nil(e.clock_out),
      where: e.clock_in >= ^NaiveDateTime.new!(first, ~T[00:00:00]),
      where: e.clock_in < ^NaiveDateTime.new!(Date.add(last, 1), ~T[00:00:00]),
      order_by: [asc: e.clock_in, asc: e.id],
      preload: [:user, :project]
    )
    |> exclude_invoiced(invoice)
    |> maybe_lock(opts[:lock])
    |> Repo.all()
  end

  defp exclude_invoiced(query, invoice) do
    on_invoice =
      from ie in InvoiceEntry,
        where: ie.active and ie.time_entry_id == parent_as(:entry).id,
        select: 1

    on_invoice =
      case invoice do
        %Invoice{id: id} when not is_nil(id) -> where(on_invoice, [ie], ie.invoice_id != ^id)
        _ -> on_invoice
      end

    where(query, not exists(on_invoice))
  end

  defp maybe_lock(query, true), do: lock(query, "FOR UPDATE")
  defp maybe_lock(query, _), do: query

  @doc "Number of entries in the month of `month` that are still running."
  def running_entry_count(%Date{} = month) do
    {first, last} = month_range(month)

    Repo.aggregate(
      from(e in TimeEntry,
        where: is_nil(e.clock_out),
        where: e.clock_in >= ^NaiveDateTime.new!(first, ~T[00:00:00]),
        where: e.clock_in < ^NaiveDateTime.new!(Date.add(last, 1), ~T[00:00:00])
      ),
      :count
    )
  end

  @doc """
  Months to pick for an invoice, newest first, as `{month, unbilled_minutes}`:
  every month with time that is not invoiced yet, plus the current and the
  previous month, the month of the draft being edited and the `shown` month.
  """
  def month_choices(today, invoice \\ nil, shown \\ nil) do
    unbilled =
      from(e in TimeEntry,
        as: :entry,
        where: not is_nil(e.clock_out),
        group_by: fragment("date_trunc('month', ?)", e.clock_in),
        select:
          {fragment("date_trunc('month', ?)::date", e.clock_in),
           sum(fragment("EXTRACT(EPOCH FROM (? - ?))", e.clock_out, e.clock_in))}
      )
      |> exclude_invoiced(invoice)
      |> Repo.all()
      |> Map.new(fn {month, seconds} ->
        {month, seconds |> Decimal.new() |> Decimal.round(0) |> Decimal.to_integer() |> div(60)}
      end)

    current = Date.beginning_of_month(today)
    previous = current |> Date.add(-1) |> Date.beginning_of_month()
    draft_month = invoice && invoice.period_start
    shown = shown && Date.beginning_of_month(shown)

    [current, previous, draft_month, shown | Map.keys(unbilled)]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort({:desc, Date})
    |> Enum.map(&{&1, Map.get(unbilled, &1, 0)})
  end

  @doc "Whether a time entry is on a draft or issued invoice."
  def entry_invoiced?(entry_id) do
    Repo.exists?(from ie in InvoiceEntry, where: ie.time_entry_id == ^entry_id and ie.active)
  end

  @doc "Ids of the time entries billed on `invoice`."
  def entry_ids(%Invoice{id: nil}), do: []

  def entry_ids(%Invoice{id: id}) do
    Repo.all(
      from ie in InvoiceEntry,
        where: ie.invoice_id == ^id and not is_nil(ie.time_entry_id),
        select: ie.time_entry_id
    )
  end

  ## Form values

  @doc """
  Invoices a new one can start from: the latest issued invoice or draft per
  recipient, newest first.
  """
  def base_invoices do
    Repo.all(
      from i in Invoice,
        where: i.status != "cancelled",
        order_by: [desc: i.inserted_at, desc: i.id]
    )
    |> Enum.uniq_by(&String.trim(&1.recipient))
    |> Enum.take(20)
  end

  @doc """
  Form values for a new invoice: today's date, the payment term and the month
  before `today`. With a `base` invoice, recipient, template, tax, rates,
  descriptions and payment term are copied from it.
  """
  def new_invoice_params(today, base \\ nil) do
    month = today |> Date.beginning_of_month() |> Date.add(-1) |> Date.beginning_of_month()

    last =
      Repo.one(
        from i in Invoice,
          where: i.status != "draft",
          order_by: [desc: i.issued_at, desc: i.id],
          limit: 1
      )

    defaults = %{
      "base_id" => "",
      "month" => month_param(month),
      "template_id" => default_template_id(),
      "recipient" => "",
      "invoice_date" => Date.to_iso8601(today),
      "due_date" => today |> Date.add(@payment_days) |> Date.to_iso8601(),
      "tax_mode" => (last && last.tax_mode) || "small_business",
      "vat_rate" => last_standard_vat_rate(),
      "rate_mode" => "single",
      "hourly_rate" => "",
      "show_timesheet" => "true",
      "rates" => last_item_values(:hourly_rate),
      "descriptions" => last_item_values(:description),
      "entry_ids" => [],
      "manual_items" => []
    }

    if base, do: apply_base(defaults, base), else: defaults
  end

  @doc """
  Copies recipient, template, tax, rates, descriptions, time sheet setting and
  payment term of `base` into the form `params`. The month stays. Without a
  due date on `base`, the new invoice has none either. Items other than
  time are not copied (see `manual_item_rows/1`), so material is not billed
  twice by mistake.
  """
  def apply_base(params, %Invoice{} = base) do
    base = Repo.preload(base, :items)
    invoice_date = parse_date(params["invoice_date"]) || base.invoice_date

    due_date =
      if base.due_date,
        do:
          invoice_date
          |> Date.add(Date.diff(base.due_date, base.invoice_date))
          |> Date.to_iso8601(),
        else: ""

    template_id =
      if base.template_id && Repo.get(InvoiceTemplate, base.template_id),
        do: to_string(base.template_id),
        else: params["template_id"]

    Map.merge(params, %{
      "base_id" => to_string(base.id),
      "template_id" => template_id,
      "recipient" => base.recipient,
      "due_date" => due_date,
      "tax_mode" => base.tax_mode,
      "vat_rate" =>
        if(base.tax_mode == "standard",
          do: decimal_param(base.vat_rate),
          else: params["vat_rate"]
        ),
      "rate_mode" => base.rate_mode,
      "hourly_rate" => decimal_param(base.hourly_rate),
      "show_timesheet" => to_string(base.show_timesheet),
      "rates" => Map.merge(params["rates"] || %{}, item_values(base, :hourly_rate)),
      "descriptions" => Map.merge(params["descriptions"] || %{}, item_values(base, :description))
    })
  end

  @doc "Project keys (see `Calculation.item_key/1`) billed on `invoice`."
  def item_keys(%Invoice{} = invoice) do
    invoice
    |> time_items()
    |> Enum.map(&Calculation.item_key(&1.project_id))
  end

  @doc """
  The form rows (see `PotionZeitgeist.Invoicing.ManualItem.to_row/1`) of the
  items of `invoice` that bill no time entries, in their order.
  """
  def manual_item_rows(%Invoice{} = invoice) do
    invoice
    |> Repo.preload(:items)
    |> Map.fetch!(:items)
    |> Enum.reject(&InvoiceItem.time?/1)
    |> Enum.map(&ManualItem.to_row/1)
  end

  defp time_items(invoice) do
    invoice |> Repo.preload(:items) |> Map.fetch!(:items) |> Enum.filter(&InvoiceItem.time?/1)
  end

  @doc "Form values of an existing draft."
  def edit_invoice_params(%Invoice{} = invoice) do
    invoice = Repo.preload(invoice, :items)

    %{
      "base_id" => "",
      "month" => month_param(invoice.period_start),
      "template_id" => invoice.template_id && to_string(invoice.template_id),
      "recipient" => invoice.recipient,
      "invoice_date" => Date.to_iso8601(invoice.invoice_date),
      "due_date" => invoice.due_date && Date.to_iso8601(invoice.due_date),
      "tax_mode" => invoice.tax_mode,
      "vat_rate" =>
        if(invoice.tax_mode == "standard",
          do: decimal_param(invoice.vat_rate),
          else: last_standard_vat_rate()
        ),
      "rate_mode" => invoice.rate_mode,
      "hourly_rate" => decimal_param(invoice.hourly_rate),
      "show_timesheet" => to_string(invoice.show_timesheet),
      "rates" => Map.merge(last_item_values(:hourly_rate), item_values(invoice, :hourly_rate)),
      "descriptions" =>
        Map.merge(last_item_values(:description), item_values(invoice, :description)),
      "entry_ids" => invoice |> entry_ids() |> Enum.map(&to_string/1),
      "manual_items" => manual_item_rows(invoice)
    }
  end

  defp default_template_id do
    case Repo.one(from t in InvoiceTemplate, order_by: [asc: t.name, asc: t.id], limit: 1) do
      nil -> nil
      template -> to_string(template.id)
    end
  end

  defp last_standard_vat_rate do
    Repo.one(
      from i in Invoice,
        where: i.tax_mode == "standard",
        order_by: [desc: i.inserted_at, desc: i.id],
        limit: 1,
        select: i.vat_rate
    )
    |> case do
      nil -> @default_vat_rate
      rate -> decimal_param(rate)
    end
  end

  # The most recent rate or description billed per project, keyed like the
  # form fields. Other items than time belong to no project.
  defp last_item_values(field) do
    Repo.all(
      from it in InvoiceItem,
        join: i in assoc(it, :invoice),
        where: i.status != "cancelled" and it.kind == "time",
        distinct: it.project_id,
        order_by: [asc: it.project_id, desc: i.inserted_at, desc: it.id],
        select: {it.project_id, field(it, ^field)}
    )
    |> Map.new(fn {project_id, value} ->
      {Calculation.item_key(project_id), form_value(value)}
    end)
  end

  defp item_values(invoice, field) do
    invoice
    |> time_items()
    |> Map.new(&{Calculation.item_key(&1.project_id), form_value(Map.fetch!(&1, field))})
  end

  defp form_value(%Decimal{} = value), do: decimal_param(value)
  defp form_value(value), do: value

  ## Preview and drafts

  @doc """
  Items and totals for the selected entries, the rate fields and the other
  items of the form, for the live summary. Never touches the database.

  `:manual_errors` has the messages of the other items that are not
  complete, by row id and field (see
  `PotionZeitgeist.Invoicing.ManualItem.parse/1`); those count for nothing
  yet.
  """
  def preview(entries, params) do
    tax_mode = if params["tax_mode"] == "standard", do: "standard", else: "small_business"

    # Rounded as the saved draft stores it, so the summary shows the saved amounts.
    vat_rate =
      if tax_mode == "standard",
        do: Calculation.round_rate(parse_decimal(params["vat_rate"]) || Decimal.new(0)),
        else: Decimal.new(0)

    time_items = build_items(entries, params)
    manual = manual_items(params, length(time_items))
    items = time_items ++ manual.items

    %{
      items: items,
      totals: Calculation.totals(items, vat_rate),
      tax_mode: tax_mode,
      vat_rate: vat_rate,
      missing_rate?: Enum.any?(time_items, &is_nil(&1.hourly_rate)),
      manual_errors: manual.errors
    }
  end

  # The other items of the form that are filled in, numbered on after the
  # `before` items of time and with the id of their row, and the errors of
  # those that are not complete, by row id. Rows left blank are no items.
  defp manual_items(params, before) do
    {items, errors} =
      params
      |> ManualItem.rows()
      |> Enum.with_index()
      |> Enum.reject(fn {row, _index} -> ManualItem.blank?(row) end)
      |> Enum.reduce({[], %{}}, fn {row, index}, {items, errors} ->
        case ManualItem.parse(row) do
          {:ok, item} -> {[Map.put(item, :row_id, row_id(row, index)) | items], errors}
          {:error, messages} -> {items, Map.put(errors, row_id(row, index), messages)}
        end
      end)

    items =
      items
      |> Enum.reverse()
      |> Enum.with_index(before + 1)
      |> Enum.map(fn {item, position} -> Map.put(item, :position, position) end)

    %{items: items, errors: errors}
  end

  defp row_id(%{"id" => id}, _index) when is_binary(id) and id != "", do: id
  defp row_id(_row, index), do: to_string(index)

  defp build_items(entries, params) do
    single_rate = parse_rate(params["hourly_rate"])
    rates = params["rates"] || %{}
    descriptions = params["descriptions"] || %{}

    rate_for =
      if params["rate_mode"] == "per_project",
        do: fn group -> rates |> Map.get(group.key) |> parse_rate() end,
        else: fn _group -> single_rate end

    entries
    |> Calculation.group_entries()
    |> Calculation.build_items(rate_for, fn group -> Map.get(descriptions, group.key) end)
  end

  # Positive rates with at most two decimals, as stored.
  defp parse_rate(value) do
    case parse_decimal(value) do
      nil ->
        nil

      rate ->
        rate = Calculation.round_rate(rate)
        if Decimal.gt?(rate, 0) and Decimal.lt?(rate, @max_rate), do: rate, else: nil
    end
  end

  @doc """
  Creates a draft from the form params: the invoice fields, `"month"`
  (`"2026-10"`), `"entry_ids"`, per project `"rates"` and `"descriptions"`
  keyed by `PotionZeitgeist.Invoicing.Calculation.item_key/1`, and
  `"manual_items"`, the rows of the other items (see
  `PotionZeitgeist.Invoicing.ManualItem.rows/1`). It needs time entries,
  other items or both.
  """
  def create_draft(params), do: save_draft(%Invoice{}, params)

  @doc "Saves the form params into a draft. Fails with `:not_draft` once it is issued."
  def update_draft(%Invoice{} = invoice, params), do: save_draft(invoice, params)

  defp save_draft(invoice, params) do
    params = normalize_params(params)
    month = parse_month(params["month"])
    {period_start, period_end} = if month, do: month_range(month), else: {nil, nil}

    entry_ids =
      params
      |> Map.get("entry_ids", [])
      |> List.wrap()
      |> Enum.map(&to_string/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    Repo.transaction(fn ->
      invoice = if invoice.id, do: lock_invoice!(invoice.id, "draft"), else: invoice

      # Lock the entries, so they cannot change while their time is billed.
      entries =
        if month do
          wanted = MapSet.new(entry_ids)

          month
          |> billable_entries(invoice, lock: true)
          |> Enum.filter(&MapSet.member?(wanted, to_string(&1.id)))
        else
          []
        end

      time_items = build_items(entries, params)
      manual = manual_items(params, length(time_items))
      items = time_items ++ manual.items

      changeset =
        invoice
        |> Invoice.draft_changeset(
          Map.merge(params, %{"period_start" => period_start, "period_end" => period_end}),
          time?: entry_ids != []
        )
        |> put_totals(items)
        |> validate_entries(entries, entry_ids, manual)
        |> validate_manual_items(manual)
        |> validate_rates(time_items)
        |> validate_total()

      if changeset.valid? do
        write_draft(changeset, items, entries)
      else
        Repo.rollback(%{changeset | action: :validate})
      end
    end)
    |> case do
      {:ok, invoice} -> {:ok, get_invoice!(invoice.id)}
      {:error, reason} -> {:error, reason}
    end
  end

  # Rates may be typed with a German comma. Anything else that is not a plain
  # number (such as "85 €" or "1e9") is left for the changeset to reject.
  defp normalize_params(params) do
    Enum.reduce(["hourly_rate", "vat_rate"], params, fn key, params ->
      case params do
        %{^key => value} when is_binary(value) ->
          value =
            case parse_decimal(value) do
              %Decimal{} = number -> Decimal.to_string(number, :normal)
              nil -> if String.trim(value) == "", do: "", else: "invalid"
            end

          Map.put(params, key, value)

        _ ->
          params
      end
    end)
  end

  defp put_totals(changeset, items) do
    totals = Calculation.totals(items, Ecto.Changeset.get_field(changeset, :vat_rate))

    changeset
    |> Ecto.Changeset.put_change(:net_total, totals.net)
    |> Ecto.Changeset.put_change(:vat_total, totals.vat)
    |> Ecto.Changeset.put_change(:gross_total, totals.gross)
  end

  defp validate_entries(changeset, entries, entry_ids, manual) do
    cond do
      entry_ids == [] and manual.items == [] and manual.errors == %{} ->
        Ecto.Changeset.add_error(
          changeset,
          :entries,
          "select at least one time entry or add another item"
        )

      length(entries) < length(entry_ids) ->
        Ecto.Changeset.add_error(
          changeset,
          :entries,
          "some selected entries are no longer available (changed, running, or on another invoice)"
        )

      true ->
        changeset
    end
  end

  defp validate_manual_items(changeset, %{errors: errors}) when errors == %{}, do: changeset

  defp validate_manual_items(changeset, _manual) do
    Ecto.Changeset.add_error(
      changeset,
      :manual_items,
      "complete or remove the items marked below"
    )
  end

  defp validate_rates(changeset, time_items) do
    if Ecto.Changeset.get_field(changeset, :rate_mode) == "per_project" and
         Enum.any?(time_items, &is_nil(&1.hourly_rate)) do
      Ecto.Changeset.add_error(
        changeset,
        :rates,
        "enter an hourly rate above 0 and below 100,000,000 for every project"
      )
    else
      changeset
    end
  end

  defp validate_total(changeset) do
    if Decimal.lt?(Ecto.Changeset.get_field(changeset, :gross_total), @max_amount) do
      changeset
    else
      Ecto.Changeset.add_error(changeset, :rates, "the total is too large for one invoice")
    end
  end

  @item_fields [
    :kind,
    :position,
    :project_id,
    :description,
    :minutes,
    :hours,
    :hourly_rate,
    :quantity,
    :unit,
    :unit_price,
    :amount
  ]

  # Runs inside the transaction of save_draft/2.
  defp write_draft(changeset, items, entries) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    invoice =
      case Repo.insert_or_update(changeset) do
        {:ok, invoice} -> invoice
        {:error, changeset} -> Repo.rollback(changeset)
      end

    Repo.delete_all(from it in InvoiceItem, where: it.invoice_id == ^invoice.id)
    Repo.delete_all(from ie in InvoiceEntry, where: ie.invoice_id == ^invoice.id)

    # Every row with the same fields: items of time have no quantity, unit
    # and price per unit, other items no minutes, hours and hourly rate.
    Repo.insert_all(
      InvoiceItem,
      Enum.map(items, fn item ->
        @item_fields
        |> Map.new(&{&1, Map.get(item, &1)})
        |> Map.merge(%{invoice_id: invoice.id, inserted_at: now, updated_at: now})
      end)
    )

    descriptions =
      items |> Enum.filter(&InvoiceItem.time?/1) |> Map.new(&{&1.project_id, &1.description})

    Enum.each(entries, fn entry ->
      %InvoiceEntry{
        invoice_id: invoice.id,
        time_entry_id: entry.id,
        date: NaiveDateTime.to_date(entry.clock_in),
        minutes: Calculation.entry_minutes(entry),
        description: Map.fetch!(descriptions, entry.project_id),
        user_name: entry.user && entry.user.name,
        notes: entry.notes
      }
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.unique_constraint(:time_entry_id,
        name: :invoice_entries_active_time_entry_index
      )
      |> Repo.insert()
      |> case do
        {:ok, _} ->
          :ok

        {:error, _} ->
          Repo.rollback(
            changeset
            |> Ecto.Changeset.add_error(
              :entries,
              "some selected entries are already on another invoice"
            )
            |> Map.put(:action, :validate)
          )
      end
    end)

    invoice
  end

  # Re-reads an invoice under a row lock and rolls back unless it still has
  # the expected status, so a stale page can never change an issued invoice.
  # A draft deleted in the meantime rolls back with `:not_found`.
  defp lock_invoice!(id, status) do
    case Repo.one(from i in Invoice, where: i.id == ^id, lock: "FOR UPDATE") do
      %Invoice{status: ^status} = invoice -> invoice
      nil -> Repo.rollback(:not_found)
      _ -> Repo.rollback(if status == "draft", do: :not_draft, else: :not_issued)
    end
  end

  @doc """
  Deletes a draft, which frees its time entries. Fails with `:not_draft` once
  it is issued and with `:not_found` when it was deleted already.
  """
  def delete_draft(%Invoice{id: id}) do
    case Repo.delete_all(from i in Invoice, where: i.id == ^id and i.status == "draft") do
      {1, _} -> :ok
      _ -> {:error, if(Repo.get(Invoice, id), do: :not_draft, else: :not_found)}
    end
  end

  ## Issuing and cancelling

  @doc "The issue form: suggested number and today's date."
  def change_issue(%Invoice{} = invoice, today) do
    Invoice.issue_form_changeset(invoice, %{
      "number" => suggest_number(today),
      "invoice_date" => Date.to_iso8601(today)
    })
  end

  @doc """
  Issues a draft with `params` `"number"` and `"invoice_date"`. The due date
  moves with the invoice date. The invoice keeps the letter texts of its
  template as they are now.
  """
  def issue_invoice(%Invoice{id: id}, params) do
    Repo.transaction(fn ->
      invoice = id |> lock_invoice!("draft") |> Repo.preload([:template, :items])
      changeset = Invoice.issue_changeset(invoice, params, Letter.texts(invoice))

      cond do
        is_nil(invoice.template) ->
          Repo.rollback(
            changeset
            |> Ecto.Changeset.add_error(:template_id, "is missing, pick a letter template first")
            |> Map.put(:action, :update)
          )

        invoice.items == [] ->
          Repo.rollback(
            changeset
            |> Ecto.Changeset.add_error(:entries, "the invoice has no items")
            |> Map.put(:action, :update)
          )

        true ->
          case Repo.update(changeset) do
            {:ok, invoice} -> invoice
            {:error, changeset} -> Repo.rollback(changeset)
          end
      end
    end)
    |> case do
      {:ok, invoice} -> {:ok, get_invoice!(invoice.id)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Hints for the issue form that do not block issuing: sample texts left in
  the letter, a number that does not follow the last one, a date before the
  last invoice, and texts too long for their place on the letter.
  """
  def issue_warnings(%Invoice{} = invoice, params) do
    invoice = Repo.preload(invoice, [:template, :items])
    letter = Letter.texts(invoice)
    text = Enum.join([letter.sender, letter.tax_id, letter.body, letter.footer], "\n")
    last = last_issued()
    number = params["number"] && String.trim(params["number"])
    date = parse_date(params["invoice_date"])

    [
      Enum.any?(@sample_markers, &String.contains?(text, &1)) &&
        "The letter template still contains sample data (name, address, IBAN or tax number).",
      due_date_gap(invoice, letter),
      last && number not in [nil, ""] && number != suggest_number(date || today()) &&
        "The suggested number after #{last.number} is #{suggest_number(date || today())}.",
      last && date && Date.compare(date, last.invoice_date) == :lt &&
        "The date is before invoice #{last.number} of #{Calendar.strftime(last.invoice_date, "%Y-%m-%d")}."
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.concat(layout_warnings(invoice, params))
  end

  @doc """
  A hint when an invoice without a due date (or with `due_date` blank in
  the form) has letter `texts` that print `{{faellig_am}}` outside a
  `{{#faellig_am}}…{{/faellig_am}}` block, where it leaves a gap.
  """
  def due_date_gap(%Invoice{due_date: nil}, texts), do: due_date_gap(texts)
  def due_date_gap(%Invoice{}, _texts), do: nil

  def due_date_gap(nil), do: nil

  def due_date_gap(texts) do
    fields = [texts.sender, texts.tax_id, texts.subject, texts.body, texts.footer]

    if Enum.any?(fields, &Letter.bare_placeholder?(&1, "faellig_am")) do
      "Without a due date, the letter template prints a gap where it uses " <>
        "#{Letter.tag("faellig_am")}. Put that text between " <>
        "#{Letter.tag("#faellig_am")} and #{Letter.tag("/faellig_am")} in the template, " <>
        "so it is left out on invoices without a due date."
    end
  end

  # Texts too long for their place on the letter, measured as the letter will
  # print once issued with the number and date of the form. They still print
  # cleanly, but move the address out of the envelope window or take room
  # from the letter text. Templates and recipients saved since the letter
  # has its line limits are checked when saved (with sample values for the
  # placeholders), so this mostly catches older texts and long numbers.
  defp layout_warnings(invoice, params) do
    invoice =
      invoice
      |> Invoice.issue_changeset(params, Letter.texts(invoice))
      |> Ecto.Changeset.apply_changes()

    texts = Letter.texts(invoice)
    vars = Letter.vars(invoice, texts)

    number =
      case LetterLayout.check_characters(invoice.number) do
        :ok -> []
        {:error, message} -> ["The invoice number #{message}."]
      end

    warnings =
      for {box, text, vars, name} <- [
            {:sender, texts.sender, vars, "The sender address of the template"},
            {:recipient, invoice.recipient, nil, "The recipient"},
            {:tax_id, texts.tax_id, vars, "The tax number line of the template"},
            {:footer, texts.footer, vars, "The footer of the template"}
          ],
          message <- [layout_message(text, box, vars)],
          message != nil,
          do: {box, "#{name}#{message}."}

    return_line =
      with false <- List.keymember?(warnings, :sender, 0),
           {:error, message} <- LetterLayout.check(Letter.build(invoice).sender_line, :return) do
        ["The sender address of the template #{message}."]
      else
        _ -> []
      end

    number ++ Enum.map(warnings, &elem(&1, 1)) ++ return_line
  end

  # A text that fits as typed but not with the values of this invoice says
  # so, since the cause can be a value such as the number of the form. The
  # recipient has no placeholders (`vars` nil). Both ways, blocks print as
  # on this invoice.
  defp layout_message(text, box, nil) do
    case LetterLayout.check(text, box) do
      {:error, message} -> " " <> message
      :ok -> nil
    end
  end

  defp layout_message(text, box, vars) do
    case {text |> Letter.typed_lines(vars) |> LetterLayout.check_lines(box),
          text |> Letter.fill_lines(vars) |> LetterLayout.check_lines(box)} do
      {{:error, message}, _filled} -> " " <> message
      {:ok, {:error, message}} -> ", with its placeholders filled in, " <> message
      {:ok, :ok} -> nil
    end
  end

  @doc "The most recently issued (or cancelled) invoice."
  def last_issued do
    Repo.one(
      from i in Invoice,
        where: not is_nil(i.number),
        order_by: [desc: i.issued_at, desc: i.id],
        limit: 1
    )
  end

  @doc """
  Cancels an issued invoice. It keeps its number and stays listed as
  cancelled; its time entries can be billed again.
  """
  def cancel_invoice(%Invoice{id: id}) do
    Repo.transaction(fn ->
      invoice = lock_invoice!(id, "issued")

      Repo.update_all(from(ie in InvoiceEntry, where: ie.invoice_id == ^id), set: [active: false])
      Repo.update!(Invoice.cancel_changeset(invoice))
    end)
    |> case do
      {:ok, invoice} -> {:ok, get_invoice!(invoice.id)}
      {:error, reason} -> {:error, reason}
    end
  end

  ## Invoice numbers

  @doc """
  The number suggested for the next invoice: the number after the most
  recently issued one. "2026-007" is followed by "2026-008", and by
  "2027-001" in a new year; a year inside a prefix ("RE-2026-0043") moves on
  the same way. Without any invoice, "<year>-001".
  """
  def suggest_number(%Date{year: year}) do
    last = last_issued()

    (last && last.number)
    |> next_number(year)
    |> skip_used_numbers()
  end

  @doc false
  def next_number(nil, year), do: "#{year}-001"

  def next_number(last, year) do
    case Regex.run(~r/^(.*?)(\d+)$/, last) do
      [_, prefix, counter] ->
        case year_in_prefix(prefix) do
          {start, prefix_year} when prefix_year < year ->
            binary_part(prefix, 0, start) <>
              Integer.to_string(year) <>
              binary_part(prefix, start + 4, byte_size(prefix) - start - 4) <>
              String.pad_leading("1", String.length(counter), "0")

          _ ->
            prefix <> increment(counter)
        end

      nil ->
        "#{year}-001"
    end
  end

  # Byte offset and value of the last four-digit year (19xx or 20xx) in a prefix.
  defp year_in_prefix(prefix) do
    case Regex.scan(~r/(?<!\d)(?:19|20)\d{2}(?!\d)/, prefix, return: :index) |> List.last() do
      [{start, 4}] -> {start, prefix |> binary_part(start, 4) |> String.to_integer()}
      _ -> nil
    end
  end

  defp increment(counter) do
    counter
    |> String.to_integer()
    |> Kernel.+(1)
    |> Integer.to_string()
    |> String.pad_leading(String.length(counter), "0")
  end

  defp skip_used_numbers(number) do
    if Repo.exists?(from i in Invoice, where: i.number == ^number) do
      case Regex.run(~r/^(.*?)(\d+)$/, number) do
        [_, prefix, counter] -> skip_used_numbers(prefix <> increment(counter))
        nil -> number
      end
    else
      number
    end
  end

  ## Form value helpers

  @doc "`\"2026-10\"` becomes `~D[2026-10-01]`; anything else `nil`."
  def parse_month(value) when is_binary(value) do
    with [year, month] <- String.split(value, "-"),
         {year, ""} <- Integer.parse(year),
         {month, ""} <- Integer.parse(month),
         {:ok, date} <- Date.new(year, month, 1) do
      date
    else
      _ -> nil
    end
  end

  def parse_month(_value), do: nil

  def month_param(%Date{} = date), do: Calendar.strftime(date, "%Y-%m")

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(_value), do: nil

  @doc """
  Parses a rate or percentage typed as a plain number with a dot or a German
  comma. Exponents, infinity, NaN and numbers beyond Decimal's precision are
  not numbers here.
  """
  def parse_decimal(%Decimal{} = value), do: value

  def parse_decimal(value) when is_binary(value) do
    value = value |> String.trim() |> String.replace(",", ".")

    with true <- Regex.match?(~r/^[+-]?(\d+(\.\d*)?|\.\d+)$/, value),
         {%Decimal{} = decimal, ""} <- Decimal.parse(value) do
      decimal
    else
      _ -> nil
    end
  end

  def parse_decimal(_value), do: nil

  defp decimal_param(nil), do: ""
  defp decimal_param(decimal), do: decimal |> Decimal.normalize() |> Decimal.to_string(:normal)
end
