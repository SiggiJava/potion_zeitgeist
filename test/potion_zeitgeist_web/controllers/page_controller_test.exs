defmodule PotionZeitgeistWeb.PageControllerTest do
  use PotionZeitgeistWeb.ConnCase

  test "GET / redirects to setup while no admin exists", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/setup"
  end
end
