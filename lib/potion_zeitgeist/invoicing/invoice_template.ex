defmodule PotionZeitgeist.Invoicing.InvoiceTemplate do
  use Ecto.Schema
  import Ecto.Changeset

  alias PotionZeitgeist.Invoicing.LetterLayout

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
    |> validate_box(:sender)
    |> validate_box(:tax_id)
    |> validate_box(:footer)
    |> unique_constraint(:name, message: "already exists")
  end

  # Letterhead and footer have boxes of a fixed size on the printed invoice.
  # The stored text is checked too, so a template saved before the limits
  # existed is fixed with its next save.
  defp validate_box(changeset, field) do
    case LetterLayout.check(get_field(changeset, field), field) do
      :ok -> changeset
      {:error, message} -> add_error(changeset, field, message)
    end
  end
end
