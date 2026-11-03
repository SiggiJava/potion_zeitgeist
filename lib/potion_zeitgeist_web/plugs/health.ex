defmodule PotionZeitgeistWeb.Plugs.Health do
  @moduledoc """
  Answers `GET /health` for the Docker health check and load balancers.

  Responds 200 "ok" when the app runs and its database answers, and 503
  otherwise. It sits at the top of the endpoint, before logging, sessions
  and the HTTPS redirect, so health checks neither fill the log nor depend
  on the first-run setup or a login.
  """

  @behaviour Plug

  import Plug.Conn

  alias PotionZeitgeist.Repo

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_info: ["health"], method: method} = conn, _opts)
      when method in ["GET", "HEAD"] do
    {status, body} = if database_up?(), do: {200, "ok"}, else: {503, "database unavailable"}

    conn
    |> put_resp_content_type("text/plain")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(status, body)
    |> halt()
  end

  def call(conn, _opts), do: conn

  defp database_up? do
    match?({:ok, _}, Repo.query("SELECT 1", [], log: false, timeout: 2_000))
  rescue
    _ -> false
  catch
    :exit, _ -> false
  end
end
