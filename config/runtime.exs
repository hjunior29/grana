import Config

# Carrega .env apenas em dev/test. Em produção a config vem de variáveis de
# ambiente reais (systemd, Docker, etc.); ler um .env solto no release sobrescreveria isso.
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
# URL pública da instância (opcional), usada nos links enviados por email e como
# base do webhook da Pluggy. PHX_HOST continua valendo como alias (https).
public_url =
  case System.get_env("PUBLIC_URL") ||
         (System.get_env("PHX_HOST") && "https://#{System.get_env("PHX_HOST")}") do
    nil -> nil
    "" -> nil
    url -> String.trim_trailing(url, "/")
  end

config :grana, :public_url, public_url
config :grana, :trust_proxy_headers, System.get_env("TRUST_PROXY_HEADERS") == "true"

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

# Chaves de integrações por ambiente. Quando definidas no .env têm prioridade e a
# tela não oferece salvar outras; sem elas, cada usuário salva as suas pela tela
# (cifradas). PLUGGY_WEBHOOK_URL (HTTPS público, ex.: túnel ngrok) habilita o
# webhook. Em test nada disso é lido, para nunca usar credenciais reais.
if config_env() != :test do
  # Provedores de IA por ambiente: aparecem na tela como "do .env", sem edição.
  config :grana, :ai_env_keys, %{
    "gemini" => System.get_env("GEMINI_API_KEY"),
    "openai" => System.get_env("OPENAI_API_KEY"),
    "anthropic" => System.get_env("ANTHROPIC_API_KEY")
  }

  config :grana, :pluggy,
    client_id: System.get_env("PLUGGY_CLIENT_ID"),
    client_secret: System.get_env("PLUGGY_CLIENT_SECRET"),
    webhook_url:
      System.get_env("PLUGGY_WEBHOOK_URL") || (public_url && "#{public_url}/webhooks/pluggy")
end

# Encryption key for sensitive fields (API keys).
# Generate with: :crypto.strong_rand_bytes(32) |> Base.encode64()
if config_env() != :test do
  if cloak_key = System.get_env("CLOAK_KEY") do
    config :grana, :cloak_key, cloak_key
  end
end

if System.get_env("PHX_SERVER") do
  config :grana, GranaWeb.Endpoint, server: true
end

config :grana, GranaWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# SMTP do ambiente, campo a campo: cada variável definida vence o campo salvo pela tela,
# e o que faltar pode ser preenchido lá. Em dev só vale com SMTP_IN_DEV=true (senão os
# emails vão para /dev/mailbox); em test nunca é lido.
if config_env() != :test and (config_env() != :dev or System.get_env("SMTP_IN_DEV") == "true") do
  smtp_env =
    [
      host: "SMTP_HOST",
      port: "SMTP_PORT",
      username: "SMTP_USERNAME",
      password: "SMTP_PASSWORD",
      tls: "SMTP_TLS",
      from_name: "MAIL_FROM_NAME",
      from_address: "MAIL_FROM_ADDRESS"
    ]
    |> Enum.flat_map(fn {field, var} ->
      case System.get_env(var) do
        value when value in [nil, ""] -> []
        value when field == :port -> [{field, String.to_integer(value)}]
        value when field == :tls -> [{field, String.to_existing_atom(value)}]
        value -> [{field, value}]
      end
    end)
    |> Map.new()

  config :grana, :smtp_env, smtp_env
end

if config_env() == :prod do
  data_dir = System.get_env("DATA_DIR") || "/var/lib/grana"
  File.mkdir_p!(data_dir)

  config :grana, :data_dir, data_dir

  database_path = System.get_env("DATABASE_PATH") || Path.join(data_dir, "grana.db")

  # busy_timeout: as conexões do pool disputam o lock de escrita do SQLite durante
  # as migrations do boot; esperar evita erros de "database is locked" na subida.
  config :grana, Grana.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5"),
    busy_timeout: 5_000

  # Gerados no primeiro boot e guardados em $DATA_DIR/secrets; o ambiente sobrescreve.
  secrets_dir = Path.join(data_dir, "secrets")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      Grana.Release.Secrets.load_or_generate(secrets_dir, :secret_key_base)

  # Chave de cifragem das credenciais (Grana.Encrypted.Binary). Guarde-a junto dos
  # backups para poder levar as credenciais cifradas para outra instância.
  cloak_key =
    System.get_env("CLOAK_KEY") ||
      Grana.Release.Secrets.load_or_generate(secrets_dir, :cloak_key)

  config :grana, :cloak_key, cloak_key

  public_uri = public_url && URI.parse(public_url)

  endpoint_url =
    if public_uri && public_uri.host do
      [host: public_uri.host, port: public_uri.port, scheme: public_uri.scheme]
    else
      [host: "localhost"]
    end

  force_ssl =
    if public_uri && public_uri.scheme == "https" do
      [rewrite_on: [:x_forwarded_proto], hsts: true, host: nil]
    else
      false
    end

  listen_ip =
    case :inet.parse_address(String.to_charlist(System.get_env("LISTEN_IP", "127.0.0.1"))) do
      {:ok, ip} -> ip
      _ -> raise "LISTEN_IP inválido"
    end

  port = String.to_integer(System.get_env("PORT", "4000"))

  endpoint_config = [
    url: endpoint_url,
    check_origin: :conn,
    http: [
      ip: listen_ip,
      port: port
    ],
    secret_key_base: secret_key_base
  ]

  endpoint_config =
    if force_ssl do
      Keyword.put(endpoint_config, :force_ssl, force_ssl)
    else
      endpoint_config
    end

  config :grana, GranaWeb.Endpoint, endpoint_config
end
