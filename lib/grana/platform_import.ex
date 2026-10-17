defmodule Grana.PlatformImport do
  @moduledoc """
  Importa de volta um CSV exportado pela própria plataforma (round-trip).

  Detecta sozinho, pelo cabeçalho, se o arquivo é um export **bancário**
  (extrato/fatura) ou de **investimentos**, e reconstrói tudo preservando banco,
  origem, categoria e instituição:

    * Bancário: agrupa por (banco, origem) e recria um extrato por grupo; mapeia a
      categoria por nome (criando a que faltar) e reconstrói o sinal do valor pelo
      tipo (Despesa → débito, Receita → crédito).
    * Investimentos: agrupa por instituição (criando a que faltar) e recria um
      statement por grupo, revertendo os rótulos de Operação/Tipo de ativo.

  Lê tanto o formato novo (completo) quanto o antigo (5 colunas, sem banco — nesse
  caso assume banco "importado"/extrato). Deduplica contra o que já existe, então
  reimportar por cima não duplica.
  """

  import Ecto.Query
  alias Grana.Repo
  alias Grana.Banking
  alias Grana.Banking.BankStatement

  @doc """
  Detecta o formato e importa. Devolve `{:ok, %{transaction_count: n}}` ou
  `{:error, motivo}`.
  """
  def process(content, user_id, _filename, _opts \\ [])

  def process(content, user_id, filename, _opts) do
    case parse(content) do
      {:banking, rows} -> import_banking(rows, filename, user_id)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Detecta o formato e devolve `{:banking, linhas}` ou `{:error, _}`."
  def parse(content) do
    case parse_rows(content) do
      [] ->
        {:error, "Arquivo vazio."}

      [header | rows] ->
        cols = header |> Enum.with_index() |> Map.new(fn {h, i} -> {norm(h), i} end)

        if banking_header?(cols) do
          {:banking, parse_banking(cols, rows)}
        else
          {:error, "Cabeçalho não reconhecido. Use um CSV exportado pelo Grana."}
        end
    end
  end

  defp banking_header?(cols) do
    Map.has_key?(cols, "categoria") or
      (Map.has_key?(cols, "tipo") and not Map.has_key?(cols, "ativo"))
  end

  # ── Banking ────────────────────────────────────────────────────────────────

  @formula_prefixes ["=", "+", "-", "@", "\t", "\r"]

  defp unquote_formula("'" <> rest = val) do
    if String.starts_with?(String.trim_leading(rest), @formula_prefixes), do: rest, else: val
  end

  defp unquote_formula(val), do: val

  defp parse_banking(cols, rows) do
    rows
    |> Enum.map(fn row ->
      date = parse_date(at(cols, row, "data"))
      desc = unquote_formula(at(cols, row, "descricao") || "")
      type = banking_type(at(cols, row, "tipo"))
      amount = parse_amount(at(cols, row, "valor"), type)

      if date && desc != "" && type && amount do
        {inst_current, inst_total} = parse_parcela(at(cols, row, "parcela"))

        %{
          date: date,
          description: desc,
          original_description:
            unquote_formula(blank_to_nil(at(cols, row, "descricao original")) || desc),
          amount: amount,
          type: type,
          category_name: blank_to_nil(at(cols, row, "categoria")),
          bank: (blank_to_nil(at(cols, row, "banco")) || "importado") |> String.downcase(),
          statement_type: parse_origem(at(cols, row, "origem")),
          is_internal_transfer: parse_bool(at(cols, row, "interna")),
          installment_current: inst_current,
          installment_total: inst_total,
          identifier: blank_to_nil(at(cols, row, "identificador"))
        }
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp import_banking([], _filename, _user_id),
    do: {:error, "Nenhuma transação válida no arquivo."}

  defp import_banking(rows, filename, user_id) do
    Banking.ensure_default_categories(user_id)
    cat_map = resolve_categories(user_id, rows)
    uncategorized_id = uncategorized_category_id(user_id)

    {:ok, count} =
      Repo.transaction(fn ->
        rows
        |> Enum.group_by(fn r -> {r.bank, r.statement_type} end)
        |> Enum.map(fn {{bank, stype}, group} ->
          import_banking_group(user_id, bank, stype, group, filename, cat_map, uncategorized_id)
        end)
        |> Enum.sum()
      end)

    Grana.OpenFinance.uploads_changed(user_id)
    Banking.detect_internal_transfers(user_id)
    {:ok, %{transaction_count: count}}
  end

  defp import_banking_group(user_id, bank, stype, rows, filename, cat_map, uncategorized_id) do
    {period_start, period_end} = period(rows)
    stmt = get_or_create_bank_statement(user_id, bank, stype, filename, period_start, period_end)

    # Como num upload comum: o período importado deixa de vir do Open Finance.
    Grana.OpenFinance.release_period(user_id, bank, stype, period_start, period_end)

    entries =
      rows
      |> Enum.map(fn r ->
        %{
          date: r.date,
          description: r.description,
          original_description: r.original_description,
          amount: r.amount,
          type: r.type,
          identifier: r.identifier,
          installment_current: r.installment_current,
          installment_total: r.installment_total,
          installment_group_id:
            Grana.Banking.Parsers.InstallmentParser.generate_group_id(
              r.description,
              r.installment_total
            ),
          is_internal_transfer: r.is_internal_transfer,
          internal_override:
            if(is_boolean(r.is_internal_transfer), do: r.is_internal_transfer, else: nil),
          bank_statement_id: stmt.id,
          user_id: user_id,
          category_id: Map.get(cat_map, norm(r.category_name), uncategorized_id)
        }
      end)
      |> dedup(user_id, &banking_fingerprint/1, fn uid, f, t ->
        existing_banking_fingerprints(uid, f, t, bank, stype)
      end)

    {count, _} = Banking.bulk_insert_transactions(entries)
    Banking.update_statement(stmt, %{status: "completed", total_transactions: count})
    count
  end

  defp resolve_categories(user_id, rows) do
    existing = Banking.list_categories(user_id) |> Map.new(fn c -> {norm(c.name), c.id} end)

    rows
    |> Enum.map(& &1.category_name)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&norm/1)
    |> Enum.reduce(existing, fn name, acc ->
      key = norm(name)

      if Map.has_key?(acc, key) do
        acc
      else
        case Banking.create_category(%{
               name: name,
               user_id: user_id,
               kind: "expense",
               color: "#9CA3AF",
               icon: "hero-tag"
             }) do
          {:ok, cat} -> Map.put(acc, key, cat.id)
          _ -> acc
        end
      end
    end)
  end

  defp uncategorized_category_id(user_id) do
    case Banking.get_uncategorized_category(user_id) do
      %{id: id} -> id
      _ -> nil
    end
  end

  defp get_or_create_bank_statement(user_id, bank, stype, filename, ps, pe) do
    attrs = %{
      bank: bank,
      filename: filename,
      statement_type: stype,
      user_id: user_id,
      period_start: ps,
      period_end: pe,
      status: "processing"
    }

    case Banking.create_statement(attrs) do
      {:ok, stmt} ->
        stmt

      {:error, _changeset} ->
        Repo.one(
          from(s in BankStatement,
            where:
              s.user_id == ^user_id and s.bank == ^bank and s.filename == ^filename and
                s.period_start == ^ps and s.period_end == ^pe
          )
        )
    end
  end

  defp banking_fingerprint(%{date: date, description: desc, amount: amount}) do
    {date, norm(desc), money_key(amount)}
  end

  defp existing_banking_fingerprints(user_id, date_from, date_to, bank, statement_type) do
    opts =
      [date_from: date_from, date_to: date_to]
      |> then(fn o -> if bank, do: Keyword.put(o, :bank, bank), else: o end)
      |> then(fn o ->
        if statement_type, do: Keyword.put(o, :statement_type, statement_type), else: o
      end)

    Banking.list_transactions(user_id, opts)
    |> Enum.map(&banking_fingerprint/1)
    |> Enum.frequencies()
  end

  # ── Dedup (compartilhado) ─────────────────────────────────────────────────────

  # Remove entradas que já existem no banco (mesma impressão digital), comparando
  # por frequência para não descartar repetições legítimas dentro do período.
  defp dedup([], _user_id, _fp_fun, _existing_fun), do: []

  defp dedup(entries, user_id, fp_fun, existing_fun) do
    dates = Enum.map(entries, & &1.date)
    freq = existing_fun.(user_id, Enum.min(dates, Date), Enum.max(dates, Date))

    {kept, _freq} =
      Enum.reduce(entries, {[], freq}, fn entry, {acc, f} ->
        key = fp_fun.(entry)

        case Map.get(f, key, 0) do
          c when c > 0 -> {acc, Map.put(f, key, c - 1)}
          _ -> {[entry | acc], f}
        end
      end)

    Enum.reverse(kept)
  end

  # ── Helpers de campo ──────────────────────────────────────────────────────────

  defp period(rows) do
    dates = Enum.map(rows, & &1.date)
    {Enum.min(dates, Date), Enum.max(dates, Date)}
  end

  defp at(cols, row, key) do
    case Map.get(cols, key) do
      nil -> nil
      idx -> row |> Enum.at(idx) |> trim_or_nil()
    end
  end

  defp trim_or_nil(nil), do: nil
  defp trim_or_nil(v), do: v |> to_string() |> String.trim()

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  defp banking_type(label) do
    case norm(label) do
      "despesa" -> "debit"
      "debito" -> "debit"
      "debit" -> "debit"
      "receita" -> "credit"
      "credito" -> "credit"
      "credit" -> "credit"
      _ -> nil
    end
  end

  defp parse_origem(label) do
    case norm(label) do
      "fatura" -> "fatura"
      _ -> "extrato"
    end
  end

  defp parse_bool(label) do
    norm(label) in ["sim", "true", "1", "yes"]
  end

  defp parse_parcela(nil), do: {nil, nil}

  defp parse_parcela(str) do
    case String.split(str, "/", parts: 2) do
      [c, t] ->
        with {ci, _} <- Integer.parse(String.trim(c)),
             {ti, _} <- Integer.parse(String.trim(t)) do
          {ci, ti}
        else
          _ -> {nil, nil}
        end

      _ ->
        {nil, nil}
    end
  end

  # Valor vem em módulo (ex.: "1.234,56"); o sinal é reconstruído pelo tipo:
  # débito → negativo, crédito → positivo (mesma convenção dos parsers de banco).
  defp parse_amount(str, type) do
    case parse_decimal(str) do
      nil ->
        nil

      dec ->
        abs = Decimal.abs(dec)
        if type == "debit", do: Decimal.negate(abs), else: abs
    end
  end

  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil

  defp parse_decimal(str) do
    trimmed = str |> to_string() |> String.trim()

    cleaned =
      if String.contains?(trimmed, ",") do
        trimmed
        |> String.replace(".", "")
        |> String.replace(",", ".")
      else
        trimmed
      end

    case Decimal.parse(cleaned) do
      {dec, _} -> dec
      :error -> nil
    end
  end

  defp parse_date(nil), do: nil

  defp parse_date(str) do
    str = String.trim(to_string(str))

    with [d, m, y] <- String.split(str, "/"),
         {di, ""} <- Integer.parse(d),
         {mi, ""} <- Integer.parse(m),
         {yi, ""} <- Integer.parse(y),
         {:ok, date} <- Date.new(yi, mi, di) do
      date
    else
      _ ->
        case Date.from_iso8601(str) do
          {:ok, date} -> date
          _ -> nil
        end
    end
  end

  defp money_key(amount) do
    amount |> Decimal.abs() |> Decimal.round(2) |> Decimal.to_string(:normal)
  end

  defp norm(nil), do: nil

  defp norm(s) do
    s
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[\x{0300}-\x{036f}]/u, "")
  end

  # ── Tokenizer CSV (RFC-4180, separador ";") ──────────────────────────────────

  @doc false
  def parse_rows(content) do
    content
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> String.graphemes()
    |> Enum.reduce({[], [], "", :normal}, &reduce_char/2)
    |> flush_rows()
    |> Enum.reject(&blank_row?/1)
  end

  defp reduce_char(ch, {rows, row, field, state}) do
    case {state, ch} do
      {:normal, "\""} when field == "" -> {rows, row, field, :in_quotes}
      {:normal, ";"} -> {rows, [field | row], "", :normal}
      {:normal, "\n"} -> {[Enum.reverse([field | row]) | rows], [], "", :normal}
      {:normal, c} -> {rows, row, field <> c, :normal}
      {:in_quotes, "\""} -> {rows, row, field, :quote_seen}
      {:in_quotes, c} -> {rows, row, field <> c, :in_quotes}
      {:quote_seen, "\""} -> {rows, row, field <> "\"", :in_quotes}
      {:quote_seen, ";"} -> {rows, [field | row], "", :normal}
      {:quote_seen, "\n"} -> {[Enum.reverse([field | row]) | rows], [], "", :normal}
      {:quote_seen, c} -> {rows, row, field <> c, :normal}
    end
  end

  defp flush_rows({rows, [], "", _state}), do: Enum.reverse(rows)

  defp flush_rows({rows, row, field, _state}),
    do: Enum.reverse([Enum.reverse([field | row]) | rows])

  defp blank_row?(row), do: Enum.all?(row, &(&1 == ""))
end
