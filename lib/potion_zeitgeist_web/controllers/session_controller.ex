defmodule PotionZeitgeistWeb.SessionController do
  use PotionZeitgeistWeb, :controller

  alias PotionZeitgeist.Accounts
  alias PotionZeitgeistWeb.UserAuth

  def new(conn, _params) do
    render(conn, :new, error_message: nil)
  end

  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        conn
        |> UserAuth.log_in_user(user)
        |> redirect(to: ~p"/")

      {:error, :deactivated} ->
        render(conn, :new, error_message: "Your account has been deactivated.")

      {:error, :invalid_credentials} ->
        render(conn, :new, error_message: "Invalid email or password.")
    end
  end

  def delete(conn, _params) do
    conn
    |> UserAuth.log_out_user()
    |> redirect(to: ~p"/login")
  end
end
