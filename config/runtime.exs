import Config

# Carrega .env apenas em dev/test. Em produção a config vem de variáveis de
# ambiente reais (fly secrets); ler um .env solto no release sobrescreveria isso.
if config_env() in [:dev, :test] and File.exists?(".env") do
  ".env"
  |> File.read!()
  |> String.split("\n", trim: true)
  |> Enum.each(fn line ->
    case String.split(line, "=", parts: 2) do
      [key, value] ->
        key = String.trim(key)
        value = String.trim(value)

        unless System.get_env(key) do
          System.put_env(key, value)
        end

      _ ->
        :ok
    end
  end)
end

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
#     PHX_SERVER=true bin/grana start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
config :grana, :admin_email, System.get_env("ADMIN_EMAIL")
config :grana, :brapi_token, System.get_env("BRAPI_TOKEN")
config :grana, :roadmap_url, System.get_env("ROADMAP_URL")

# Cache (Grana.Cache / Cachex). Em dev e prod o cache roda 100% em memória (ETS).
# TTL padrão de 300s, customizável por CACHE_TTL_SECONDS. Pode ser desabilitado por CACHE_ENABLED=false.
if config_env() != :test do
  cache_ttl =
    case Integer.parse(System.get_env("CACHE_TTL_SECONDS") || "300") do
      {ttl, _} when ttl > 0 -> ttl
      _ -> 300
    end

  config :grana, Grana.Cache,
    enabled: System.get_env("CACHE_ENABLED", "true") in ~w(true 1),
    ttl_seconds: cache_ttl
end

# Encryption key for sensitive fields (API keys).
# Generate with: :crypto.strong_rand_bytes(32) |> Base.encode64()
if cloak_key = System.get_env("CLOAK_KEY") do
  config :grana, :cloak_key, cloak_key
end

if System.get_env("PHX_SERVER") do
  config :grana, GranaWeb.Endpoint, server: true
end

config :grana, GranaWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# In dev, set SMTP_IN_DEV=true in .env to send real emails via SMTP
# instead of the local mailbox at /dev/mailbox
if config_env() == :dev and System.get_env("SMTP_IN_DEV") == "true" do
  if smtp_host = System.get_env("SMTP_HOST") do
    config :grana, :smtp_available, true

    config :grana, :smtp_config,
      relay: smtp_host,
      port: String.to_integer(System.get_env("SMTP_PORT") || "587"),
      username: System.get_env("SMTP_USERNAME"),
      password: System.get_env("SMTP_PASSWORD"),
      tls: :always,
      tls_options: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        server_name_indication: String.to_charlist(smtp_host),
        depth: 3,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ],
      auth: :always,
      ssl: false

    config :grana, :mail_from,
      name: System.get_env("MAIL_FROM_NAME") || "Grana",
      address: System.get_env("MAIL_FROM_ADDRESS") || "noreply@example.com"
  end
end

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /data/grana.db
      """

  config :grana, Grana.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  # Chave de cifragem das API keys de IA (Grana.Encrypted.Binary). EXIGIDA em
  # produção — sem ela, a cifragem-at-rest cairia para a chave de dev pública.
  config :grana,
         :cloak_key,
         System.get_env("CLOAK_KEY") ||
           raise("""
           environment variable CLOAK_KEY is missing.
           Generate one with: mix phx.gen.secret 32
           """)

  host = System.get_env("PHX_HOST") || "example.com"

  config :grana, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :grana, GranaWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
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
  #     config :grana, GranaWeb.Endpoint,
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
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :grana, GranaWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer (SMTP)
  smtp_host =
    System.get_env("SMTP_HOST") ||
      raise "environment variable SMTP_HOST is missing."

  config :grana, Grana.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: smtp_host,
    port: String.to_integer(System.get_env("SMTP_PORT") || "587"),
    username: System.get_env("SMTP_USERNAME"),
    password: System.get_env("SMTP_PASSWORD"),
    tls: :always,
    tls_options: [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(smtp_host),
      depth: 3,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ],
    auth: :always,
    ssl: false

  config :grana, :mail_from,
    name: System.get_env("MAIL_FROM_NAME") || "Grana",
    address: System.get_env("MAIL_FROM_ADDRESS") || "noreply@example.com"
end
