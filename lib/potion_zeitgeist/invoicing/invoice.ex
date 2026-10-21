defmodule PotionZeitgeist.Invoicing.Invoice do
  use Ecto.Schema
  import Ecto.Changeset

  alias PotionZeitgeist.Invoicing.Calculation

  @statuses ~w(draft issued cancelled)
  @rate_modes ~w(single per_project)
  @tax_modes ~w(small_business standard)

  schema "invoices" do
    field :number, :string
    field :status, :string, default: "draft"
    field :invoice_date, :date
    field :due_date, :date
    field :period_start, :date
    field :period_end, :date
    field :recipient, :string
    field :rate_mode, :string, default: "single"
    field :hourly_rate, :decimal
    # "small_business": no VAT, the § 19 UStG note is printed. "standard": VAT at vat_rate.
    field :tax_mode, :string, default: "small_business"
    field :vat_rate, :decimal, default: Decimal.new(0)
    field :net_total, :decimal, default: Decimal.new(0)
    field :vat_total, :decimal, default: Decimal.new(0)
    field :gross_total, :decimal, default: Decimal.new(0)
    field :show_timesheet, :boolean, default: true

    field :letter_sender, :string
    field :letter_tax_id, :string
    field :letter_subject, :string
    field :letter_body, :string
    field :letter_footer, :string

    field :issued_at, :utc_datetime
    field :cancelled_at, :utc_datetime

    belongs_to :template, PotionZeitgeist.Invoicing.InvoiceTemplate
    has_many :items, PotionZeitgeist.Invoicing.InvoiceItem, preload_order: [asc: :position]
    has_many :invoice_entries, PotionZeitgeist.Invoicing.InvoiceEntry

    timestamps()
  end

  def statuses, do: @statuses

  @doc """
  Validates the fields of the invoice form. Items and totals are computed by
  `PotionZeitgeist.Invoicing` and put on the changeset there.
  """
  def draft_changeset(invoice, attrs) do
    invoice
    |> cast(attrs, [
      :invoice_date,
      :due_date,
      :period_start,
      :period_end,
      :recipient,
      :template_id,
      :rate_mode,
      :tax_mode,
      :show_timesheet
    ])
    |> validate_required([
      :invoice_date,
      :period_start,
      :period_end,
      :recipient,
      :template_id,
      :rate_mode,
      :tax_mode
    ])
    |> validate_inclusion(:rate_mode, @rate_modes)
    |> validate_inclusion(:tax_mode, @tax_modes)
    |> cast_hourly_rate(attrs)
    |> cast_vat_rate(attrs)
    |> validate_recipient()
    |> validate_dates()
    |> foreign_key_constraint(:template_id, message: "was deleted, pick another one")
    |> check_constraint(:vat_rate, name: :invoices_tax_valid, message: "is not valid")
  end

  @doc "The fields of the issue form: invoice number and invoice date."
  def issue_form_changeset(invoice, attrs) do
    invoice
    |> cast(attrs, [:number, :invoice_date])
    |> update_change(:number, &String.trim/1)
    |> validate_required([:number, :invoice_date])
    |> validate_length(:number, max: 40)
    |> unique_constraint(:number, message: "is already used by another invoice")
  end

  @doc """
  Issues the invoice with the number and date of `attrs` and the letter
  texts it is printed with. The due date keeps its distance to the date.
  """
  def issue_changeset(invoice, attrs, letter) do
    changeset = issue_form_changeset(invoice, attrs)
    new_date = get_field(changeset, :invoice_date)

    due_date =
      if invoice.due_date && new_date,
        do: Date.add(invoice.due_date, Date.diff(new_date, invoice.invoice_date)),
        else: invoice.due_date

    change(changeset,
      status: "issued",
      due_date: due_date,
      issued_at: DateTime.utc_now() |> DateTime.truncate(:second),
      letter_sender: letter.sender,
      letter_tax_id: letter.tax_id,
      letter_subject: letter.subject,
      letter_body: letter.body,
      letter_footer: letter.footer
    )
  end

  def cancel_changeset(invoice) do
    change(invoice,
      status: "cancelled",
      cancelled_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
  end

  def draft?(%__MODULE__{status: "draft"}), do: true
  def draft?(_invoice), do: false

  def tax_modes, do: @tax_modes

  # The form keeps the values of rate fields it no longer shows, so only the
  # rate of the chosen mode is read. Rates are stored with two decimals and
  # validated as stored.
  defp cast_hourly_rate(changeset, attrs) do
    if get_field(changeset, :rate_mode) == "single" do
      changeset
      |> cast(attrs, [:hourly_rate])
      |> update_change(:hourly_rate, &Calculation.round_rate/1)
      |> validate_required([:hourly_rate], message: "is needed for one rate for all")
      |> validate_number(:hourly_rate, greater_than: 0, less_than: 100_000_000)
    else
      put_change(changeset, :hourly_rate, nil)
    end
  end

  # Small businesses (§ 19 UStG) charge no VAT. With VAT the rate must be set.
  defp cast_vat_rate(changeset, attrs) do
    if get_field(changeset, :tax_mode) == "standard" do
      changeset =
        changeset
        |> cast(attrs, [:vat_rate])
        |> update_change(:vat_rate, &Calculation.round_rate/1)

      # A blank rate casts to the field default 0, so check the value itself.
      rate = get_field(changeset, :vat_rate)

      cond do
        Keyword.has_key?(changeset.errors, :vat_rate) -> changeset
        rate && Decimal.gt?(rate, 0) -> validate_number(changeset, :vat_rate, less_than: 100)
        true -> add_error(changeset, :vat_rate, "is needed when charging VAT")
      end
    else
      put_change(changeset, :vat_rate, Decimal.new(0))
    end
  end

  # German invoices need the recipient's full name and address.
  defp validate_recipient(changeset) do
    validate_change(changeset, :recipient, fn :recipient, recipient ->
      lines = recipient |> String.split(["\r\n", "\n"]) |> Enum.reject(&(String.trim(&1) == ""))

      if length(lines) >= 2,
        do: [],
        else: [recipient: "needs the name and the full address, on separate lines"]
    end)
  end

  defp validate_dates(changeset) do
    invoice_date = get_field(changeset, :invoice_date)
    due_date = get_field(changeset, :due_date)

    if invoice_date && due_date && Date.compare(due_date, invoice_date) == :lt do
      add_error(changeset, :due_date, "must not be before the invoice date")
    else
      changeset
    end
  end
end
