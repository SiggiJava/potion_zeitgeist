defmodule PotionZeitgeist.Invoicing.InvoiceTemplate do
  use Ecto.Schema
  import Ecto.Changeset

  alias PotionZeitgeist.Invoicing.{Letter, LetterLayout}

  schema "invoice_templates" do
    field :name, :string
    # Name and address of the business, printed top right and as return address.
    field :sender, :string
    # "Steuernummer: …" or "USt-IdNr.: …", always printed on the invoice.
    field :tax_id, :string
    field :subject, :string, default: ""
    field :body, :string
    field :footer, :string, default: ""

    timestamps()
  end

  @doc """
  `today` is the date of the sample letter the texts are measured with, the
  one the template form previews (see `PotionZeitgeist.Invoicing.Letter.sample/3`).
  """
  def changeset(template, attrs, today) do
    template
    |> cast(attrs, [:name, :sender, :tax_id, :subject, :body, :footer], empty_values: [])
    |> update_change(:name, &(&1 && String.trim(&1)))
    |> update_change(:tax_id, &(&1 && String.trim(&1)))
    |> validate_required([:name, :sender, :tax_id, :body])
    |> validate_length(:name, max: 120)
    |> validate_length(:tax_id, max: 255)
    |> validate_length(:subject, max: 255)
    |> validate_blocks()
    |> validate_boxes(today)
    |> unique_constraint(:name, message: "already exists")
  end

  # A block such as `{{#faellig_am}}…{{/faellig_am}}` opens and closes on one
  # line, see `PotionZeitgeist.Invoicing.Letter`.
  defp validate_blocks(changeset) do
    Enum.reduce([:sender, :tax_id, :subject, :body, :footer], changeset, fn field, changeset ->
      case changeset |> get_field(field) |> Letter.block_errors() do
        [] -> changeset
        [message | _more] -> add_error(changeset, field, message)
      end
    end)
  end

  @filled_in " with its placeholders filled in as in the preview"

  # Letterhead, tax number line and footer have boxes of a fixed size on the
  # printed invoice. A text must fit as typed and as printed: a placeholder
  # can be longer or shorter than its value, so the texts are also checked
  # with the values of the preview. Blocks can print other text on other
  # invoices, so the texts are checked as typed for each way their blocks
  # can print, and filled in with the preview's values with and without a
  # due date and VAT. The stored texts are checked too, so a template saved
  # before the limits existed is fixed with its next save.
  defp validate_boxes(changeset, today) do
    template = apply_changes(changeset)

    samples =
      for due_date? <- [true, false], vat? <- [false, true] do
        invoice = Letter.sample_invoice(template, today, due_date: due_date?, vat: vat?)
        {invoice, Letter.vars(invoice), @filled_in <> sample_name(due_date?, vat?)}
      end

    changeset
    |> validate_box(:sender, samples)
    |> validate_box(:tax_id, samples)
    |> validate_box(:footer, samples)
    |> validate_return_line(samples)
  end

  defp sample_name(true, false), do: ""
  defp sample_name(true, true), do: " of an invoice with VAT"
  defp sample_name(false, false), do: " of an invoice without a due date"
  defp sample_name(false, true), do: " of an invoice with VAT and without a due date"

  defp validate_box(changeset, field, samples) do
    text = get_field(changeset, field)
    typed = text |> Letter.typed_variants() |> first_error(field, "")

    filled =
      Enum.find_value(samples, fn {_invoice, vars, filled_in} ->
        first_error([Letter.fill_lines(text, vars)], field, filled_in)
      end)

    case typed || filled do
      nil -> changeset
      message -> add_error(changeset, field, message)
    end
  end

  defp first_error(variants, field, suffix) do
    Enum.find_value(variants, fn lines ->
      case LetterLayout.check_lines(lines, field) do
        :ok -> nil
        {:error, message} -> message <> suffix
      end
    end)
  end

  # The small return address above the recipient is made from the letterhead.
  defp validate_return_line(changeset, samples) do
    message =
      Enum.find_value(samples, fn {invoice, _vars, _filled_in} ->
        case LetterLayout.check(Letter.build(invoice).sender_line, :return) do
          :ok -> nil
          {:error, message} -> message
        end
      end)

    if message && not Keyword.has_key?(changeset.errors, :sender),
      do: add_error(changeset, :sender, message),
      else: changeset
  end
end
