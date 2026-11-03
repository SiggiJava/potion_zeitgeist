defmodule PotionZeitgeistWeb.Plugs.ForceSSLTest do
  # Changes application config, so it must not run alongside other tests.
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias PotionZeitgeistWeb.Plugs.ForceSSL

  # What config/runtime.exs sets with FORCE_SSL=true.
  @ssl_opts [
    rewrite_on: [:x_forwarded_proto],
    host: nil,
    exclude: [hosts: ["localhost", "127.0.0.1"]]
  ]

  setup do
    previous = Application.fetch_env(:potion_zeitgeist, :force_ssl)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:potion_zeitgeist, :force_ssl, value)
        :error -> Application.delete_env(:potion_zeitgeist, :force_ssl)
      end
    end)
  end

  defp run(conn), do: ForceSSL.call(conn, ForceSSL.init([]))

  test "leaves plain HTTP alone when FORCE_SSL is off, e.g. in a local network" do
    Application.put_env(:potion_zeitgeist, :force_ssl, false)

    conn = run(conn(:get, "http://192.168.1.20:4000/login"))

    refute conn.halted
    assert get_resp_header(conn, "strict-transport-security") == []
  end

  test "redirects plain HTTP to HTTPS on the requested host when FORCE_SSL is on" do
    Application.put_env(:potion_zeitgeist, :force_ssl, @ssl_opts)

    conn = run(conn(:get, "http://zeit.example.com/login?next=1"))

    assert conn.halted
    assert conn.status == 301
    assert get_resp_header(conn, "location") == ["https://zeit.example.com/login?next=1"]
  end

  test "keeps localhost on plain HTTP for the container's health check" do
    Application.put_env(:potion_zeitgeist, :force_ssl, @ssl_opts)

    conn = run(conn(:get, "http://localhost:4000/health"))

    refute conn.halted
  end

  test "accepts HTTPS from a reverse proxy (X-Forwarded-Proto) and sends HSTS" do
    Application.put_env(:potion_zeitgeist, :force_ssl, @ssl_opts)

    conn =
      conn(:get, "http://zeit.example.com/")
      |> put_req_header("x-forwarded-proto", "https")
      |> run()

    refute conn.halted
    assert [hsts] = get_resp_header(conn, "strict-transport-security")
    assert hsts =~ "max-age="
  end
end
