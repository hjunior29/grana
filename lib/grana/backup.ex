defmodule Grana.Backup do
  @moduledoc """
  Backup, restauração e "apagar tudo". Tudo vive em um único arquivo SQLite.

  Restaurar nunca troca o arquivo do banco em uso: o backup enviado é validado e
  preparado numa cópia temporária (com um repo dinâmico) e só então os dados são
  copiados para o banco vivo, numa transação, com as filas do Oban pausadas.
  """

  import Ecto.Query

  require Logger

  alias Grana.{Accounts, Cache, DataDir, Repo, Setup}
  alias Grana.Accounts.UserToken

  @sqlite_header "SQLite format 3\0"
  @secret_columns ~w(cpf pluggy_client_secret pluggy_webhook_secret smtp_password)
  @stale_after_seconds 3600
  @retryable [
    {:error, :wrong_cloak_key},
    {:error, :password_required},
    {:error, :password_invalid}
  ]

  ## Download

  @doc "Grava uma cópia consistente do banco em `dest` (`VACUUM INTO`)."
  def create(dest) do
    case Repo.query("VACUUM INTO ?", [dest]) do
      {:ok, _} -> :ok
      {:error, error} -> {:error, Exception.message(error)}
    end
  end

  def download_filename, do: "grana-backup-#{Date.utc_today()}.db"

  ## Restauração

  @doc """
  Valida o arquivo enviado e o prepara numa cópia temporária.

  Devolve `{:ok, %{path: path, users: [%{id, email, transactions, has_password?}]}}`
  — `users` vem ordenado pelo que tem mais transações — ou `{:error, motivo}`.
  O chamador deve passar o `path` a `restore/2` ou `discard/1`.
  """
  def analyze(upload_path) do
    cleanup_stale()
    work = Path.join(DataDir.tmp_dir(), "restore-#{System.unique_integer([:positive])}.db")

    with :ok <- check_header(upload_path),
         :ok <- File.cp(upload_path, work),
         {:ok, users} <- prepare_copy(work) do
      {:ok, %{path: work, users: users}}
    else
      {:error, _} = error ->
        File.rm(work)
        error
    end
  end

  def discard(path), do: File.rm(path)

  @doc """
  Aplica o backup preparado ao banco vivo, ficando só com o usuário `user_id`.

  Opções: `:old_cloak_key` (chave de criptografia do backup, para levar as
  credenciais cifradas), `:new_password` (obrigatória se o usuário do backup não
  tem senha) e `:base_url`. Sem a chave antiga, os segredos cifrados são zerados e
  `{:ok, %{cleared: [...]}}` lista o que precisa ser cadastrado de novo.

  O temporário some em qualquer desfecho, exceto quando o erro pode ser corrigido
  na tela (`:wrong_cloak_key`, `:password_required`, `:password_invalid`): nesses
  casos nada foi alterado e o mesmo `analysis` serve para tentar de novo.
  """
  def restore(%{path: path}, user_id, opts \\ []) do
    result =
      with {:ok, cleared} <- prepare_user(path, user_id, opts),
           :ok <- apply_to_live(path) do
        {:ok, %{cleared: cleared}}
      end

    unless result in @retryable, do: File.rm(path)
    result
  end

  defp check_header(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, 16)) do
      {:ok, @sqlite_header} -> :ok
      _ -> {:error, :not_sqlite}
    end
  end

  defp prepare_copy(work) do
    with_temp_repo(work, fn ->
      with :ok <- integrity_check(),
           :ok <- check_triggers_and_views(),
           :ok <- check_migrations(),
           :ok <- migrate() do
        list_users()
      end
    end)
  end

  defp check_triggers_and_views do
    case Repo.query!("SELECT count(*) FROM sqlite_master WHERE type IN ('view', 'trigger')") do
      %{rows: [[0]]} -> :ok
      _ -> {:error, :untrusted_objects}
    end
  end

  defp integrity_check do
    case Repo.query!("PRAGMA integrity_check") do
      %{rows: [["ok"]]} -> :ok
      _ -> {:error, :corrupted}
    end
  end

  defp check_migrations do
    case Repo.query("SELECT version FROM schema_migrations") do
      {:ok, %{rows: rows}} ->
        unknown = Enum.map(rows, &hd/1) -- known_migration_versions()
        if unknown == [], do: :ok, else: {:error, :newer_backup}

      {:error, _} ->
        {:error, :not_grana_backup}
    end
  end

  defp known_migration_versions do
    :grana
    |> Application.app_dir("priv/repo/migrations")
    |> Path.join("*.exs")
    |> Path.wildcard()
    |> Enum.map(fn file ->
      file |> Path.basename() |> String.split("_", parts: 2) |> hd() |> String.to_integer()
    end)
  end

  defp migrate do
    Ecto.Migrator.run(Repo, :up, all: true, dynamic_repo: Repo.get_dynamic_repo(), log: false)
    :ok
  end

  defp list_users do
    %{rows: rows} =
      Repo.query!("""
      SELECT u.id, u.email, u.hashed_password IS NOT NULL,
             (SELECT count(*) FROM transactions t WHERE t.user_id = u.id)
      FROM users u ORDER BY 4 DESC, u.id
      """)

    case rows do
      [] ->
        {:error, :no_users}

      rows ->
        {:ok,
         for [id, email, has_password, count] <- rows do
           %{
             id: id,
             email: mask_email(email),
             transactions: count,
             has_password?: has_password == 1
           }
         end}
    end
  end

  defp mask_email(email) do
    case String.split(email, "@", parts: 2) do
      [local, domain] -> String.first(local) <> "•••@" <> domain
      _ -> "•••"
    end
  end

  # Tudo numa transação do backup temporário: se algo falha (chave errada, senha
  # inválida), nada é alterado e o usuário pode tentar de novo com outra escolha.
  defp prepare_user(path, user_id, opts) do
    with_temp_repo(path, fn ->
      Repo.transaction(fn ->
        Repo.query!("DELETE FROM users WHERE id != ?", [user_id])

        with {:ok, cleared} <- handle_secrets(user_id, opts[:old_cloak_key]),
             :ok <- handle_password(user_id, opts[:new_password]) do
          finish_user(user_id, opts[:base_url])
          cleared
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end)
  end

  # Segredos cifrados: colunas do usuário e a chave de cada provedor de IA.
  defp handle_secrets(user_id, old_key) do
    secrets = user_secrets(user_id) ++ provider_secrets(user_id)

    if old_key in [nil, ""] do
      Enum.each(secrets, fn {table, column, id, _value} ->
        Repo.query!("UPDATE #{table} SET #{column} = NULL WHERE id = ?", [id])
      end)

      {:ok, secrets |> Enum.map(&cleared_label/1) |> Enum.uniq()}
    else
      reencrypt_secrets(secrets, String.trim(old_key))
    end
  end

  defp user_secrets(user_id) do
    %{rows: [values]} =
      Repo.query!("SELECT #{Enum.join(@secret_columns, ", ")} FROM users WHERE id = ?", [user_id])

    for {column, value} <- Enum.zip(@secret_columns, values),
        value != nil,
        do: {"users", column, user_id, value}
  end

  defp provider_secrets(user_id) do
    %{rows: rows} =
      Repo.query!(
        "SELECT id, api_key FROM ai_providers WHERE user_id = ? AND api_key IS NOT NULL",
        [user_id]
      )

    for [id, value] <- rows, do: {"ai_providers", "api_key", id, value}
  end

  defp cleared_label({"users", column, _id, _value}), do: column
  defp cleared_label({"ai_providers", _column, _id, _value}), do: "ai_providers"

  defp reencrypt_secrets(secrets, old_key) do
    Enum.reduce_while(secrets, {:ok, []}, fn {table, column, id, value}, acc ->
      case Grana.Encrypted.Binary.reencrypt(value, old_key) do
        {:ok, new_value} ->
          Repo.query!("UPDATE #{table} SET #{column} = ? WHERE id = ?", [new_value, id])
          {:cont, acc}

        :error ->
          {:halt, {:error, :wrong_cloak_key}}
      end
    end)
  end

  defp handle_password(user_id, new_password) do
    %{rows: [[hash]]} = Repo.query!("SELECT hashed_password FROM users WHERE id = ?", [user_id])

    cond do
      new_password in [nil, ""] and hash == nil ->
        {:error, :password_required}

      new_password in [nil, ""] ->
        :ok

      String.length(new_password) < 12 or byte_size(new_password) > 72 ->
        {:error, :password_invalid}

      true ->
        Repo.query!("UPDATE users SET hashed_password = ? WHERE id = ?", [
          Bcrypt.hash_pwd_salt(new_password),
          user_id
        ])

        :ok
    end
  end

  defp finish_user(user_id, base_url) do
    now = DateTime.utc_now(:second) |> DateTime.to_iso8601()

    Repo.query!(
      "UPDATE users SET confirmed_at = COALESCE(confirmed_at, ?1), onboarded_at = COALESCE(onboarded_at, ?1), base_url = COALESCE(?2, base_url) WHERE id = ?3",
      [now, base_url, user_id]
    )
  end

  # Repo dinâmico sobre o arquivo temporário, num processo à parte para o
  # `put_dynamic_repo` não vazar para quem chamou.
  defp with_temp_repo(path, fun) do
    task =
      Task.async(fn ->
        {:ok, pid} =
          Repo.start_link(
            name: nil,
            database: path,
            pool: DBConnection.ConnectionPool,
            pool_size: 1,
            journal_mode: :delete
          )

        Repo.put_dynamic_repo(pid)

        try do
          Repo.query!("PRAGMA trusted_schema = OFF")
          fun.()
        rescue
          e ->
            Logger.warning("Backup: arquivo inutilizável: #{Exception.message(e)}")
            {:error, :invalid_file}
        after
          GenServer.stop(pid)
        end
      end)

    Task.await(task, :infinity)
  end

  ## Aplicar ao banco vivo / apagar tudo

  defp apply_to_live(path) do
    replace_live_data(fn ->
      Repo.query!("PRAGMA trusted_schema = OFF")
      Repo.query!("ATTACH DATABASE ? AS restore", [path])

      try do
        Repo.transaction(
          fn ->
            Repo.query!("PRAGMA defer_foreign_keys = ON")
            tables = app_tables()
            Enum.each(tables, &Repo.query!(~s|DELETE FROM main."#{&1}"|))
            Enum.each(tables, &copy_table/1)
          end,
          timeout: :infinity
        )
      after
        Repo.query!("DETACH DATABASE restore")
      end
    end)
  end

  @doc """
  Apaga todos os dados da instância (usuário, tudo que é dele, jobs e erros) e volta
  ao setup, com um novo código no log.
  """
  def reset_all do
    result =
      replace_live_data(fn ->
        Repo.transaction(fn ->
          Repo.query!("PRAGMA defer_foreign_keys = ON")
          Enum.each(app_tables() ++ extra_tables(), &Repo.query!(~s|DELETE FROM main."#{&1}"|))
        end)
      end)

    Setup.generate_code()
    result
  end

  # Pausa o Oban, troca os dados e depois derruba sessões e caches. Os tokens de
  # sessão são lidos antes porque a troca os apaga (cascade do usuário).
  defp replace_live_data(fun) do
    session_tokens = Repo.all(from(t in UserToken, where: t.context == "session"))
    Oban.pause_all_queues(Oban)

    try do
      case Repo.checkout(fun) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    after
      Oban.resume_all_queues(Oban)
    end
    |> tap(fn _ ->
      Accounts.invalidate_setup_cache()
      Cache.clear_all()
      GranaWeb.UserAuth.disconnect_sessions(session_tokens)
    end)
  end

  # Tabelas do app: tudo, menos migrations, Oban, ErrorTracker e sessões
  # (users_tokens), que não fazem parte de um backup.
  defp app_tables do
    %{rows: rows} =
      Repo.query!("SELECT name FROM main.sqlite_master WHERE type = 'table' ORDER BY name")

    rows
    |> Enum.map(&hd/1)
    |> Enum.reject(&excluded_table?/1)
  end

  defp excluded_table?(name) do
    name in ["schema_migrations", "users_tokens"] or
      String.starts_with?(name, ["sqlite_", "oban_", "error_tracker_"])
  end

  defp extra_tables, do: ["oban_jobs", "error_tracker_occurrences", "error_tracker_errors"]

  defp copy_table(table) do
    columns = shared_columns(table)
    list = Enum.map_join(columns, ", ", &~s|"#{&1}"|)

    Repo.query!(~s|INSERT INTO main."#{table}" (#{list}) SELECT #{list} FROM restore."#{table}"|)
  end

  defp shared_columns(table) do
    main = table_columns("main", table)
    restore = table_columns("restore", table)
    Enum.filter(main, &(&1 in restore))
  end

  defp table_columns(schema, table) do
    %{rows: rows} = Repo.query!(~s|PRAGMA #{schema}.table_info("#{table}")|)
    Enum.map(rows, &Enum.at(&1, 1))
  end

  defp cleanup_stale do
    cutoff = System.os_time(:second) - @stale_after_seconds

    DataDir.tmp_dir()
    |> Path.join("restore-*.db")
    |> Path.wildcard()
    |> Enum.filter(&(File.stat!(&1, time: :posix).mtime < cutoff))
    |> Enum.each(&File.rm/1)
  end
end
