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

  def changeset(template, attrs) do
    template
    |> cast(attrs, [:name, :sender, :tax_id, :subject, :body, :footer], empty_values: [])
    |> update_change(:name, &(&1 && String.trim(&1)))
    |> update_change(:tax_id, &(&1 && String.trim(&1)))
    |> validate_required([:name, :sender, :tax_id, :body])
    |> validate_length(:name, max: 120)
    |> validate_length(:tax_id, max: 255)
    |> validate_length(:subject, max: 255)
    |> validate_boxes()
    |> unique_constraint(:name, message: "already exists")
  end

  # Letterhead, tax number line and footer have boxes of a fixed size on the
  # printed invoice. A text must fit as typed and as printed: a placeholder
  # can be longer or shorter than its value, so the texts are also checked
  # with the values of the preview (`PotionZeitgeist.Invoicing.Letter.sample/2`).
  # The stored texts are checked too, so a template saved before the limits
  # existed is fixed with its next save.
  defp validate_boxes(changeset) do
    sample = Letter.sample(apply_changes(changeset), Date.utc_today())

    changeset
    |> validate_box(:sender, sample.sender)
    |> validate_box(:tax_id, sample.tax_id)
    |> validate_box(:footer, sample.footer)
    |> validate_return_line(sample.sender_line)
  end

  @filled_in " with its placeholders filled in as in the preview"

  defp validate_box(changeset, field, printed) do
    typed = LetterLayout.check(get_field(changeset, field), field)

    case {typed, LetterLayout.check(printed, field)} do
      {:ok, :ok} ->
        changeset

      {{:error, message}, _printed} ->
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
