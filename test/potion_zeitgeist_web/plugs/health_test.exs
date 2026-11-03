defmodule PotionZeitgeistWeb.Plugs.HealthTest do
  use PotionZeitgeistWeb.ConnCase, async: true

  test "GET /health answers ok before the first-run setup and without login", %{conn: conn} do
    conn = get(conn, "/health")

    assert response(conn, 200) == "ok"
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "HEAD /health answers 200", %{conn: conn} do
    conn = head(conn, "/health")

    assert conn.status == 200
  end

  test "other pages still need the setup", %{conn: conn} do
    conn = get(conn, "/")

    assert redirected_to(conn) == "/setup"
  end
end
