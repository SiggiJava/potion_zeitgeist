defmodule PotionZeitgeistWeb.PageController do
  use PotionZeitgeistWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
