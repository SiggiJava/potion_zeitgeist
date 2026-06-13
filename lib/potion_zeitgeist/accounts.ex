defmodule PotionZeitgeist.Accounts do
  import Ecto.Query

  alias PotionZeitgeist.Repo
  alias PotionZeitgeist.Accounts.User

  def admin_exists? do
    Repo.exists?(from u in User, where: u.role == "admin" and u.active == true)
  end

  def list_users do
    Repo.all(from u in User, order_by: [asc: u.inserted_at])
  end

  def get_user(id) do
    Repo.get(User, id)
  end

  def get_user!(id) do
    Repo.get!(User, id)
  end

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email_hash: email)
  end

  def authenticate_user(email, password) do
    user = get_user_by_email(email)

    cond do
      user && user.active && User.valid_password?(user, password) ->
        {:ok, user}

      user && !user.active ->
        {:error, :deactivated}

      true ->
        {:error, :invalid_credentials}
    end
  end

  def create_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def create_admin(attrs) do
    attrs = Map.put(attrs, "role", "admin")

    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.update_changeset(attrs)
    |> Repo.update()
  end

  def change_user_password(%User{} = user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> Repo.update()
  end

  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  def change_user(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs)
  end

  def change_user_update(%User{} = user, attrs \\ %{}) do
    User.update_changeset(user, attrs)
  end
end
