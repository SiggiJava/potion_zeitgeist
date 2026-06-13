defmodule PotionZeitgeistWeb.SetupController do
  use PotionZeitgeistWeb, :controller

  alias PotionZeitgeist.Accounts

  def new(conn, _params) do
    if Accounts.admin_exists?() do
      redirect(conn, to: ~p"/login")
    else
      render(conn, :new, changeset: Accounts.change_user(%Accounts.User{}))
    end
  end

  def create(conn, %{"user" => user_params}) do
    if Accounts.admin_exists?() do
      redirect(conn, to: ~p"/login")
    else
      case Accounts.create_admin(user_params) do
        {:ok, _user} ->
          conn
          |> put_flash(:info, "Admin account created. Please sign in.")
          |> redirect(to: ~p"/login")

        {:error, changeset} ->
          render(conn, :new, changeset: changeset)
      end
    end
  end
end
