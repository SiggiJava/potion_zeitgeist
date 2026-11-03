defmodule PotionZeitgeistWeb.Plugs.ForceSSL do
  @moduledoc """
  Redirects plain HTTP to HTTPS and sends HSTS, when switched on.

  It runs `Plug.SSL` with the options in `config :potion_zeitgeist, :force_ssl`,
  which config/runtime.exs sets when the app starts with FORCE_SSL=true, and
  does nothing otherwise. Phoenix's own `force_ssl` endpoint option is fixed
  at compile time; this way one Docker image serves both a local network over
  HTTP and a public HTTPS setup behind a reverse proxy.
  """

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case Application.get_env(:potion_zeitgeist, :force_ssl) do
      ssl_opts when is_list(ssl_opts) -> Plug.SSL.call(conn, Plug.SSL.init(ssl_opts))
      _ -> conn
    end
  end
end
