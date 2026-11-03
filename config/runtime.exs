import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/potion_zeitgeist start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :potion_zeitgeist, PotionZeitgeistWeb.Endpoint, server: true
end

config :potion_zeitgeist, PotionZeitgeistWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  # Keys come from the environment. The Docker image also writes keys that
  # were not set to $DATA_DIR/secrets.env on first start (docker-entrypoint.sh)
  # and they are read from there, so every command in the container
  # (server, eval, remote) uses the same keys.
  stored_secrets =
    with dir when is_binary(dir) and dir != "" <- System.get_env("DATA_DIR"),
         {:ok, content} <- File.read(Path.join(dir, "secrets.env")) do
      for line <- String.split(content, ["\r\n", "\n"]),
          not String.starts_with?(String.trim_leading(line), "#"),
          [key, value] <- [String.split(line, "=", parts: 2)],
          into: %{},
          do: {String.trim(key), String.trim(value)}
    else
      _ -> %{}
    end

  # An empty variable (e.g. `VAULT_KEY=` in .env) counts as not set.
  present = fn value ->
    value = String.trim(value || "")
    if value != "", do: value
  end

  secret = fn name -> present.(System.get_env(name)) || present.(stored_secrets[name]) end

  vault_key =
    secret.("VAULT_KEY") ||
      raise """
      environment variable VAULT_KEY is missing.
      Generate one with: :crypto.strong_rand_bytes(32) |> Base.encode64() |> IO.puts()
      """

  vault_key =
    case Base.decode64(vault_key) do
      {:ok, <<_::binary-size(32)>> = key} ->
        key

      _ ->
        raise """
        environment variable VAULT_KEY is not a valid key.
        It must be 32 random bytes encoded as Base64 (44 characters ending in "=").
        Generate one with: :crypto.strong_rand_bytes(32) |> Base.encode64() |> IO.puts()
        """
    end

  config :potion_zeitgeist, PotionZeitgeist.Vault,
    ciphers: [
      default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: vault_key}
    ]

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :potion_zeitgeist, PotionZeitgeist.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    secret.("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  # PHX_HOST: the host names or IP addresses people type in the browser to
  # open the app, separated by commas, e.g. "zeit.example.com,192.168.1.20".
  # The first one is used for generated URLs. The live pages only connect
  # from these hosts (and from localhost), which protects against other
  # websites talking to the app in a user's name.
  hosts =
    (System.get_env("PHX_HOST") || "")
    |> String.split([",", " "], trim: true)
    # Tolerate "http://zeit.example.com" or "192.168.1.20:4000": keep the host.
    |> Enum.map(fn entry ->
      cond do
        String.contains?(entry, "://") -> URI.parse(entry).host
        String.starts_with?(entry, "[") -> URI.parse("//" <> entry).host
        # a bare IPv6 address such as fe80::1
        length(String.split(entry, ":")) > 2 -> entry
        true -> URI.parse("//" <> entry).host
      end
    end)
    |> Enum.reject(&(&1 in [nil, ""]))
    # Browsers send the host in lower case.
    |> Enum.map(&String.downcase/1)
    |> case do
      [] -> ["localhost"]
      hosts -> Enum.uniq(hosts)
    end

  # FORCE_SSL=true (the default): redirect plain HTTP to HTTPS and send HSTS,
  # for an app served over HTTPS, usually by a reverse proxy that sets
  # X-Forwarded-Proto. FORCE_SSL=false lets the app answer plain HTTP, e.g. on
  # http://192.168.1.20:4000 in a local network; the Docker image sets that.
  force_ssl? = System.get_env("FORCE_SSL", "true") in ~w(true 1)

  # Read by PotionZeitgeistWeb.Plugs.ForceSSL. Requests for localhost stay on
  # plain HTTP (Plug.SSL's default), so the app can be reached directly on the
  # machine it runs on; a proxy must forward the original Host header.
  config :potion_zeitgeist,
         :force_ssl,
         force_ssl? &&
           [
             rewrite_on: [:x_forwarded_proto],
             host: nil,
             exclude: [hosts: ["localhost", "127.0.0.1"]]
           ]

  url =
    if force_ssl?,
      do: [host: hd(hosts), port: 443, scheme: "https"],
      else: [
        host: hd(hosts),
        port: String.to_integer(System.get_env("PORT", "4000")),
        scheme: "http"
      ]

  # "//host" accepts that host with any scheme and port.
  check_origin =
    for host <- Enum.uniq(hosts ++ ["localhost", "127.0.0.1"]) do
      if String.contains?(host, ":"), do: "//[#{host}]", else: "//#{host}"
    end

  config :potion_zeitgeist, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :potion_zeitgeist, PotionZeitgeistWeb.Endpoint,
    url: url,
    check_origin: check_origin,
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :potion_zeitgeist, PotionZeitgeistWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # Redirecting HTTP to HTTPS is switched on with FORCE_SSL=true (see above
  # and PotionZeitgeistWeb.Plugs.ForceSSL), not with the endpoint's compile-time
  # `force_ssl` option, so the same Docker image works with and without HTTPS.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :potion_zeitgeist, PotionZeitgeist.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
