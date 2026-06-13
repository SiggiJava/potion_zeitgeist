defmodule PotionZeitgeist.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, PotionZeitgeist.Encrypted.Binary, source: :encrypted_email
    field :email_hash, Cloak.Ecto.SHA256
    field :name, PotionZeitgeist.Encrypted.Binary, source: :encrypted_name
    field :password_hash, :string
    field :role, :string, default: "user"
    field :active, :boolean, default: true

    field :password, :string, virtual: true

    has_many :time_entries, PotionZeitgeist.TimeTracking.TimeEntry

    timestamps()
  end

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :password, :role])
    |> validate_required([:email, :name, :password])
    |> validate_email()
    |> validate_password()
    |> validate_inclusion(:role, ["admin", "user"])
    |> put_email_hash()
    |> put_password_hash()
  end

  def update_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :role, :active])
    |> validate_required([:email, :name, :role])
    |> validate_email()
    |> validate_inclusion(:role, ["admin", "user"])
    |> put_email_hash()
  end

  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_password()
    |> put_password_hash()
  end

  def valid_password?(%__MODULE__{password_hash: hash}, password)
      when is_binary(hash) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hash)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  def admin?(%__MODULE__{role: "admin"}), do: true
  def admin?(_), do: false

  defp validate_email(changeset) do
    changeset
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/,
      message: "must contain @ and no spaces"
    )
    |> validate_length(:email, max: 254)
    |> unique_constraint(:email_hash,
      name: :users_email_hash_index,
      message: "has already been taken"
    )
  end

  defp validate_password(changeset) do
    changeset
    |> validate_length(:password, min: 8, max: 72)
  end

  defp put_email_hash(changeset) do
    case get_change(changeset, :email) do
      nil -> changeset
      email -> force_change(changeset, :email_hash, email)
    end
  end

  defp put_password_hash(%{valid?: true, changes: %{password: password}} = changeset) do
    put_change(changeset, :password_hash, Bcrypt.hash_pwd_salt(password))
  end

  defp put_password_hash(changeset), do: changeset
end
