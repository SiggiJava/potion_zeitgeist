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
  one the template form previews (see `PotionZeitgeist.Invoicing.Letter.sample/2`).
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
    |> validate_boxes(today)
    |> unique_constraint(:name, message: "already exists")
  end

  # Letterhead, tax number line and footer have boxes of a fixed size on the
  # printed invoice. A text must fit as typed and as printed: a placeholder
  # can be longer or shorter than its value, so the texts are also checked
  # with the values of the preview. The stored texts are checked too, so a
  # template saved before the limits existed is fixed with its next save.
  defp validate_boxes(changeset, today) do
    invoice = Letter.sample_invoice(apply_changes(changeset), today)
    vars = Letter.vars(invoice)
    fill = &Letter.fill(&1, vars)

    changeset
    |> validate_box(:sender, fill)
    |> validate_box(:tax_id, fill)
    |> validate_box(:footer, fill)
    |> validate_return_line(Letter.build(invoice).sender_line)
  end

  @filled_in " with its placeholders filled in as in the preview"

  defp validate_box(changeset, field, fill) do
    text = get_field(changeset, field)

    case {LetterLayout.check(text, field), LetterLayout.check(text, field, fill)} do
      {:ok, :ok} ->
        changeset

      {{:error, message}, _filled} ->
        add_error(changeset, field, message)

      {:ok, {:error, message}} ->
        add_error(changeset, field, message <> @filled_in)
    end
  end

  # The small return address above the recipient is made from the letterhead.
  defp validate_return_line(changeset, line) do
    with false <- Keyword.has_key?(changeset.errors, :sender),
         {:error, message} <- LetterLayout.check(line, :return) do
      add_error(changeset, :sender, message)
    else
      _ -> changeset
    end
  end
end
