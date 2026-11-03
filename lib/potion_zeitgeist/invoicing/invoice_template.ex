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

  # Letterhead, tax number line and footer have boxes of a fixed size on the
  # printed invoice. A text must fit as typed and as printed: a placeholder
  # can be longer or shorter than its value, so the texts are also checked
  # with the values of the preview, with and without a due date, since
  # blocks can print other text without one. As typed, a text is measured
  # with the text of all its blocks but without their tags, which never
  # print. The stored texts are checked too, so a template saved before the
  # limits existed is fixed with its next save.
  defp validate_boxes(changeset, today) do
    template = apply_changes(changeset)

    samples =
      for {due_date?, suffix} <- [{true, ""}, {false, " and without a due date"}] do
        invoice = Letter.sample_invoice(template, today, due_date: due_date?)

        {invoice, Letter.vars(invoice),
         " with its placeholders filled in as in the preview" <> suffix}
      end

    changeset
    |> validate_box(:sender, samples)
    |> validate_box(:tax_id, samples)
    |> validate_box(:footer, samples)
    |> validate_return_line(samples)
  end

  defp validate_box(changeset, field, samples) do
    text = get_field(changeset, field)

    filled =
      Enum.find_value(samples, fn {_invoice, vars, filled_in} ->
        case text |> Letter.fill_lines(vars) |> LetterLayout.check_lines(field) do
          :ok -> nil
          {:error, message} -> message <> filled_in
        end
      end)

    case {LetterLayout.check(text, field, &Letter.without_block_tags/1), filled} do
      {:ok, nil} -> changeset
      {{:error, message}, _filled} -> add_error(changeset, field, message)
      {:ok, message} -> add_error(changeset, field, message)
    end
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
