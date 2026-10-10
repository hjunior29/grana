import Config

# Chave de cifragem fixa só para testes (Grana.Encrypted.Binary).
config :grana, :cloak_key, "uAsvYu1DjJFziFfKP1ZJyiinCOYCZD1CFb4QMGMzpZU="

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :grana, Grana.Repo,
  database: Path.expand("../grana_test#{System.get_env("MIX_TEST_PARTITION")}.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  busy_timeout: 15_000,
  journal_mode: :wal,
  synchronous: :normal

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :grana, GranaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Br3CLjLNbS9RxyqPc44qFkZehkGe+aYAZSUcazX8pdKqGNzRrI5LFpcFayN/zUN7",
  server: false

# In test we don't send emails
config :grana, Grana.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Disable Oban in tests
config :grana, Oban, testing: :manual

# Skip rate limiting in tests
config :grana, :skip_rate_limit, true

# Cache desligado nos testes: Grana.Cache cai no fallback (executa a query direto),
# evitando vazamento de estado de cache entre testes.
config :grana, Grana.Cache, enabled: false

# Print only warnings and errors during test
config :logger, level: :warning

# Keep generated Ecto validation messages aligned with the existing test suite.
config :grana, GranaWeb.Gettext, default_locale: "en"

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Sem cache do estado de setup e sem código no log: o banco muda a cada teste.
config :grana, :cache_setup_state, false
config :grana, :announce_setup_code, false

# O SMTP configurado nos testes envia pelo adapter Test, nunca pela rede.
config :grana, :smtp_adapter, Swoosh.Adapters.Test
