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
  alias Grana.Investments
  alias Grana.Investments.{Constants, Institution}

  @doc """
  Detecta o formato e importa. Devolve `{:ok, %{transaction_count: n}}` ou
  `{:error, motivo}`.
  """
  def process(content, user_id, _filename, _opts \\ [])

  def process(content, user_id, filename, _opts) do
    case parse(content) do
      {:banking, rows} -> import_banking(rows, filename, user_id)
      {:investments, rows} -> import_investments(rows, filename, user_id)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Detecta o formato e devolve `{:banking | :investments, linhas}` ou `{:error, _}`."
  def parse(content) do
    case parse_rows(content) do
      [] ->
        {:error, "Arquivo vazio."}

      [header | rows] ->
        cols = header |> Enum.with_index() |> Map.new(fn {h, i} -> {norm(h), i} end)

        cond do
          investments_header?(cols) -> {:investments, parse_investments(cols, rows)}
          banking_header?(cols) -> {:banking, parse_banking(cols, rows)}
          true -> {:error, "Cabeçalho não reconhecido. Use um CSV exportado pelo Grana."}
        end
    end
  end

  defp banking_header?(cols) do
    Map.has_key?(cols, "categoria") or
      (Map.has_key?(cols, "tipo") and not Map.has_key?(cols, "ativo"))
  end

  defp investments_header?(cols) do
    Map.has_key?(cols, "ativo") and Map.has_key?(cols, "operacao")
  end

  # ── Banking ────────────────────────────────────────────────────────────────

  defp parse_banking(cols, rows) do
    rows
    |> Enum.map(fn row ->
      date = parse_date(at(cols, row, "data"))
      desc = at(cols, row, "descricao") || ""
      type = banking_type(at(cols, row, "tipo"))
      amount = parse_amount(at(cols, row, "valor"), type)

      if date && desc != "" && type && amount do
        {inst_current, inst_total} = parse_parcela(at(cols, row, "parcela"))

        %{
          date: date,
          description: desc,
          original_description: blank_to_nil(at(cols, row, "descricao original")) || desc,
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

    count =
      rows
      |> Enum.group_by(fn r -> {r.bank, r.statement_type} end)
      |> Enum.map(fn {{bank, stype}, group} ->
        import_banking_group(user_id, bank, stype, group, filename, cat_map, uncategorized_id)
      end)
      |> Enum.sum()

    Banking.detect_internal_transfers(user_id)
    {:ok, %{transaction_count: count}}
  end

  defp import_banking_group(user_id, bank, stype, rows, filename, cat_map, uncategorized_id) do
    {period_start, period_end} = period(rows)
    stmt = get_or_create_bank_statement(user_id, bank, stype, filename, period_start, period_end)

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
          installment_group_id: nil,
          is_internal_transfer: r.is_internal_transfer,
          bank_statement_id: stmt.id,
          user_id: user_id,
          category_id: Map.get(cat_map, norm(r.category_name), uncategorized_id)
        }
      end)
      |> dedup(user_id, &banking_fingerprint/1, &existing_banking_fingerprints/3)

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

  defp existing_banking_fingerprints(user_id, date_from, date_to) do
    Banking.list_transactions(user_id, date_from: date_from, date_to: date_to)
    |> Enum.map(&banking_fingerprint/1)
    |> Enum.frequencies()
  end

  # ── Investments ──────────────────────────────────────────────────────────────

  defp parse_investments(cols, rows) do
    rows
    |> Enum.map(fn row ->
      date = parse_date(at(cols, row, "data"))
      asset_name = blank_to_nil(at(cols, row, "ativo"))
      total = parse_decimal(at(cols, row, "valor total"))

      if date && asset_name && total do
        %{
          date: date,
          asset_name: asset_name,
          asset_ticker: blank_to_nil(at(cols, row, "ticker")),
          asset_type: asset_type_from_label(at(cols, row, "tipo ativo")),
          operation: operation_from_label(at(cols, row, "operacao")),
          quantity: parse_decimal(at(cols, row, "quantidade")) || Decimal.new(0),
          unit_price: parse_decimal(at(cols, row, "preco unit.")) || Decimal.new(0),
          total_amount: total,
          fees: parse_decimal(at(cols, row, "taxas")) || Decimal.new(0),
          identifier: blank_to_nil(at(cols, row, "identificador")),
          original_description: blank_to_nil(at(cols, row, "descricao original")),
          institution_name: blank_to_nil(at(cols, row, "instituicao")) || "Importado"
        }
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp import_investments([], _filename, _user_id),
    do: {:error, "Nenhuma transação válida no arquivo."}

  defp import_investments(rows, filename, user_id) do
    count =
      rows
      |> Enum.group_by(& &1.institution_name)
      |> Enum.map(fn {inst_name, group} ->
        inst = get_or_create_institution(user_id, inst_name)
        import_investment_group(user_id, inst, group, filename)
      end)
      |> Enum.sum()

    # Proventos importados podem casar com créditos do extrato — reconcilia.
    Banking.detect_internal_transfers(user_id)
    {:ok, %{transaction_count: count}}
  end

  defp import_investment_group(user_id, inst, rows, filename) do
    {period_start, period_end} = period(rows)
    stmt = get_or_create_inv_statement(user_id, inst.id, filename, period_start, period_end)

    entries =
      rows
      |> Enum.map(fn r ->
        %{
          date: r.date,
          asset_name: r.asset_name,
          asset_ticker: r.asset_ticker,
          asset_type: r.asset_type,
          operation: r.operation,
          quantity: r.quantity,
          unit_price: r.unit_price,
          total_amount: r.total_amount,
          fees: r.fees,
          identifier: r.identifier,
          original_description: r.original_description,
          user_id: user_id,
          statement_id: stmt.id,
          institution_id: inst.id
        }
      end)
      |> dedup(user_id, &inv_fingerprint/1, &existing_inv_fingerprints/3)

    {count, _} = Investments.bulk_insert_transactions(entries)
    Investments.update_statement(stmt, %{status: "completed", total_transactions: count})
    count
  end

  defp get_or_create_institution(user_id, name) do
    slug = Institution.Slug.slugify(name)

    case Investments.get_institution_by_slug(slug, user_id) do
      nil ->
        case Investments.create_institution(%{name: name, slug: slug, user_id: user_id}) do
          {:ok, inst} -> inst
          _ -> Investments.get_institution_by_slug(slug, user_id)
        end

      inst ->
        inst
    end
  end

  defp get_or_create_inv_statement(user_id, institution_id, filename, ps, pe) do
    attrs = %{
      filename: filename,
      user_id: user_id,
      institution_id: institution_id,
      period_start: ps,
      period_end: pe,
      status: "processing"
    }

    case Investments.create_statement(attrs) do
      {:ok, stmt} ->
        stmt

      {:error, _changeset} ->
        Repo.one(
          from(s in Grana.Investments.Statement,
            where:
              s.user_id == ^user_id and s.institution_id == ^institution_id and
                s.filename == ^filename and s.period_start == ^ps and s.period_end == ^pe
          )
        )
    end
  end

  defp inv_fingerprint(%{date: date, asset_name: name, operation: op, total_amount: amount}) do
    {date, norm(name), op, money_key(amount)}
  end

  defp existing_inv_fingerprints(user_id, date_from, date_to) do
    Investments.list_transactions(user_id, date_from: date_from, date_to: date_to)
    |> Enum.map(&inv_fingerprint/1)
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
    cleaned =
      str
      |> to_string()
      |> String.trim()
      |> String.replace(".", "")
      |> String.replace(",", ".")

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

  defp asset_type_from_label(label) do
    from_label(label, Constants.asset_types(), &Constants.asset_type_label/1)
  end

  defp operation_from_label(label) do
    from_label(label, Constants.operations(), &Constants.operation_label/1)
  end

  # Aceita tanto o rótulo ("Ações", "Compra") quanto o código ("acao", "compra").
  defp from_label(label, codes, label_fun) do
    key = norm(label)

    cond do
      key in codes -> key
      true -> Enum.find(codes, &(norm(label_fun.(&1)) == key)) || "outro"
    end
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
