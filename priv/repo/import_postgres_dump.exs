# priv/repo/import_postgres_dump.exs
# Converte o dump de inserts do PostgreSQL e importa para o SQLite local

source_file = "gra_na_inserts.sql"
target_file = "gra_na_sqlite_import.sql"

unless File.exists?(source_file) do
  IO.puts("Erro: arquivo #{source_file} não encontrado.")
  System.halt(1)
end

IO.puts("Convertendo #{source_file} para sintaxe SQLite em #{target_file}...")

header = """
PRAGMA foreign_keys = OFF;
BEGIN TRANSACTION;
"""

autoincrement_tables = [
  "users",
  "bank_statements",
  "categories",
  "transactions",
  "category_rules",
  "recurring_rules",
  "investment_institutions",
  "investment_statements",
  "investment_transactions",
  "users_tokens",
  "oban_jobs",
  "error_tracker_errors",
  "error_tracker_occurrences"
]

sequence_updates =
  Enum.map(autoincrement_tables, fn table ->
    "INSERT OR REPLACE INTO sqlite_sequence (name, seq) VALUES ('#{table}', (SELECT coalesce(max(id), 0) FROM #{table}));"
  end)
  |> Enum.join("\n")

footer = """
COMMIT;
#{sequence_updates}
PRAGMA foreign_keys = ON;
"""

process_statement = fn statement ->
  # 1. Converte literais hex bytea: '\xHEX' -> X'HEX'
  converted =
    Regex.replace(~r/'\\x([0-9a-fA-F]+)'/, statement, fn _, hex ->
      "X'#{hex}'"
    end)

  # 2. Ajusta tabela e comando
  cond do
    String.contains?(converted, "INSERT INTO public.schema_migrations") ->
      String.replace(converted, "INSERT INTO public.schema_migrations", "INSERT OR IGNORE INTO schema_migrations")

    String.contains?(converted, "INSERT INTO public.error_tracker_meta") ->
      String.replace(converted, "INSERT INTO public.error_tracker_meta", "INSERT OR REPLACE INTO error_tracker_meta")

    true ->
      Regex.replace(~r/INSERT INTO public\.([a-zA-Z0-9_]+)/, converted, "INSERT OR REPLACE INTO \\1")
  end
end

out_io = File.open!(target_file, [:write, :utf8])
IO.write(out_io, header)

File.stream!(source_file)
|> Enum.reduce({nil, false}, fn raw_line, {acc, in_insert?} ->
  line = String.trim(raw_line)

  cond do
    in_insert? ->
      new_acc = acc <> "\n" <> line
      if String.ends_with?(line, ");") do
        IO.write(out_io, process_statement.(new_acc) <> "\n")
        {nil, false}
      else
        {new_acc, true}
      end

    String.starts_with?(line, "INSERT INTO public.") ->
      if String.ends_with?(line, ");") do
        IO.write(out_io, process_statement.(line) <> "\n")
        {nil, false}
      else
        {line, true}
      end

    true ->
      {nil, false}
  end
end)

IO.write(out_io, footer)
File.close(out_io)

IO.puts("Arquivo #{target_file} gerado com sucesso!")
