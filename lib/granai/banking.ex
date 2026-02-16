defmodule Granai.Banking do
  import Ecto.Query
  alias Granai.Repo
  alias Granai.Banking.{BankStatement, Transaction, Category, CategoryRule, AIAnalysis}

  # Categories

  def list_categories(user_id) do
    Category
    |> where([c], is_nil(c.user_id) or c.user_id == ^user_id)
    |> order_by([c], asc: c.name)
    |> Repo.all()
  end

  def get_category!(id), do: Repo.get!(Category, id)

  def create_category(attrs) do
    %Category{}
    |> Category.changeset(attrs)
    |> Repo.insert()
  end

  def ensure_default_categories(user_id) do
    defaults = [
      %{name: "Alimentação", icon: "hero-cake", color: "#F59E0B"},
      %{name: "Transporte", icon: "hero-truck", color: "#3B82F6"},
      %{name: "Moradia", icon: "hero-home", color: "#8B5CF6"},
      %{name: "Saúde", icon: "hero-heart", color: "#EF4444"},
      %{name: "Lazer", icon: "hero-musical-note", color: "#EC4899"},
      %{name: "Educação", icon: "hero-academic-cap", color: "#06B6D4"},
      %{name: "Compras", icon: "hero-shopping-bag", color: "#F97316"},
      %{name: "Transferências", icon: "hero-arrows-right-left", color: "#6366F1"},
      %{name: "Investimentos", icon: "hero-chart-bar", color: "#10B981"},
      %{name: "Pagamentos", icon: "hero-credit-card", color: "#64748B"},
      %{name: "Salário", icon: "hero-banknotes", color: "#22C55E"},
      %{name: "Assinaturas", icon: "hero-arrow-path", color: "#A855F7"},
      %{name: "Sem Categoria", icon: "hero-question-mark-circle", color: "#9CA3AF"}
    ]

    Enum.each(defaults, fn cat_attrs ->
      attrs = Map.merge(cat_attrs, %{user_id: user_id, is_system: true})

      %Category{}
      |> Category.changeset(attrs)
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:name, :user_id])
    end)

    list_categories(user_id)
  end

  def get_uncategorized_category(user_id) do
    Category
    |> where([c], c.name == "Sem Categoria" and c.user_id == ^user_id)
    |> Repo.one()
  end

  # Statements

  def list_statements(user_id) do
    BankStatement
    |> where([s], s.user_id == ^user_id)
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
  end

  def list_statements_paginated(user_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    offset = (page - 1) * per_page

    base =
      BankStatement
      |> where([s], s.user_id == ^user_id)
      |> order_by([s], desc: s.inserted_at)

    total = Repo.aggregate(base, :count)
    statements = base |> limit(^per_page) |> offset(^offset) |> Repo.all()

    {statements, total}
  end

  def get_statement!(id), do: Repo.get!(BankStatement, id)

  def create_statement(attrs) do
    %BankStatement{}
    |> BankStatement.changeset(attrs)
    |> Repo.insert()
  end

  def update_statement(statement, attrs) do
    statement
    |> BankStatement.changeset(attrs)
    |> Repo.update()
  end

  def delete_statement(statement) do
    Repo.delete(statement)
  end

  def delete_statements(ids) when is_list(ids) do
    BankStatement
    |> where([s], s.id in ^ids)
    |> Repo.delete_all()
  end

  def available_banks(user_id) do
    BankStatement
    |> where([bs], bs.user_id == ^user_id)
    |> select([bs], bs.bank)
    |> distinct(true)
    |> Repo.all()
  end

  # Transactions

  def list_transactions(user_id, opts \\ []) do
    user_id
    |> build_transactions_query(opts)
    |> Repo.all()
  end

  def list_transactions_paginated(user_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 50)
    offset = (page - 1) * per_page

    base = build_transactions_query(user_id, opts)
    total = Repo.aggregate(base, :count)

    transactions =
      base
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    {transactions, total}
  end

  defp build_transactions_query(user_id, opts) do
    query =
      Transaction
      |> where([t], t.user_id == ^user_id)
      |> preload([:category, :bank_statement])
      |> order_by([t], desc: t.date)

    query = filter_by_category(query, Keyword.get(opts, :category_id))
    query = filter_by_uncategorized(query, Keyword.get(opts, :uncategorized), user_id)
    query = filter_by_statement(query, Keyword.get(opts, :bank_statement_id))
    query = filter_by_date_from(query, Keyword.get(opts, :date_from))
    query = filter_by_date_to(query, Keyword.get(opts, :date_to))
    query = filter_by_search(query, Keyword.get(opts, :search))
    query = filter_by_bank(query, Keyword.get(opts, :bank), user_id)
    query = filter_by_type(query, Keyword.get(opts, :type))
    query = filter_by_amount_min(query, Keyword.get(opts, :amount_min))
    filter_by_amount_max(query, Keyword.get(opts, :amount_max))
  end

  defp filter_by_category(query, nil), do: query
  defp filter_by_category(query, id), do: where(query, [t], t.category_id == ^id)

  defp filter_by_uncategorized(query, true, user_id) do
    case get_uncategorized_category(user_id) do
      nil -> where(query, [t], is_nil(t.category_id))
      %{id: id} -> where(query, [t], is_nil(t.category_id) or t.category_id == ^id)
    end
  end

  defp filter_by_uncategorized(query, _, _user_id), do: query

  defp filter_by_statement(query, nil), do: query
  defp filter_by_statement(query, id), do: where(query, [t], t.bank_statement_id == ^id)

  defp filter_by_date_from(query, nil), do: query
  defp filter_by_date_from(query, date), do: where(query, [t], t.date >= ^date)

  defp filter_by_date_to(query, nil), do: query
  defp filter_by_date_to(query, date), do: where(query, [t], t.date <= ^date)

  defp filter_by_search(query, nil), do: query
  defp filter_by_search(query, ""), do: query
  defp filter_by_search(query, term), do: where(query, [t], ilike(t.description, ^"%#{term}%"))

  defp filter_by_bank(query, nil, _user_id), do: query
  defp filter_by_bank(query, "all", _user_id), do: query

  defp filter_by_bank(query, bank, user_id) do
    stmt_ids =
      BankStatement
      |> where([bs], bs.user_id == ^user_id and bs.bank == ^bank)
      |> select([bs], bs.id)

    where(query, [t], t.bank_statement_id in subquery(stmt_ids))
  end

  defp filter_by_type(query, nil), do: query
  defp filter_by_type(query, "all"), do: query
  defp filter_by_type(query, type), do: where(query, [t], t.type == ^type)

  defp filter_by_amount_min(query, nil), do: query

  defp filter_by_amount_min(query, min) do
    where(query, [t], fragment("ABS(?)", t.amount) >= ^min)
  end

  defp filter_by_amount_max(query, nil), do: query

  defp filter_by_amount_max(query, max) do
    where(query, [t], fragment("ABS(?)", t.amount) <= ^max)
  end

  def get_transaction!(id) do
    Transaction
    |> Repo.get!(id)
    |> Repo.preload([:category, :bank_statement])
  end

  def update_transaction(transaction, attrs) do
    transaction
    |> Transaction.changeset(attrs)
    |> Repo.update()
  end

  def bulk_insert_transactions(transactions_attrs) do
    now = DateTime.utc_now(:second)

    entries =
      Enum.map(transactions_attrs, fn attrs ->
        attrs
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    Repo.insert_all(Transaction, entries)
  end

  # Category Rules

  def list_category_rules(user_id) do
    CategoryRule
    |> where([r], r.user_id == ^user_id)
    |> preload(:category)
    |> Repo.all()
  end

  def create_category_rule(attrs) do
    %CategoryRule{}
    |> CategoryRule.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:category_id, :updated_at]},
      conflict_target: [:pattern, :user_id]
    )
  end

  def categorize_transaction(description, user_id) do
    rules = list_category_rules(user_id)
    desc_lower = String.downcase(description)

    matched_rule =
      Enum.find(rules, fn rule ->
        String.contains?(desc_lower, rule.pattern)
      end)

    case matched_rule do
      %{category_id: category_id} -> category_id
      nil -> apply_default_rules(description, user_id)
    end
  end

  defp apply_default_rules(description, user_id) do
    categories = list_categories(user_id)
    cat_map = Map.new(categories, fn c -> {c.name, c.id} end)
    desc_lower = String.downcase(description)

    cond do
      String.contains?(desc_lower, [
        "supermercado",
        "mercado",
        "mercearia",
        "atacado",
        "emporio",
        "empório"
      ]) ->
        Map.get(cat_map, "Alimentação")

      String.contains?(desc_lower, [
        "restauran",
        "pizza",
        "lanchonete",
        "café",
        "cafe",
        "subway",
        "confeitaria",
        "padaria",
        "padani",
        "bebidas",
        "coliseu"
      ]) ->
        Map.get(cat_map, "Alimentação")

      String.contains?(desc_lower, [
        "drogasil",
        "drogaria",
        "droga",
        "farmácia",
        "farmacia",
        "pacheco",
        "unimed"
      ]) ->
        Map.get(cat_map, "Saúde")

      String.contains?(desc_lower, [
        "posto",
        "combustível",
        "combustivel",
        "braspetro",
        "auto",
        "estacionamento",
        "allpark"
      ]) ->
        Map.get(cat_map, "Transporte")

      String.contains?(desc_lower, ["aluguel", "imob", "empreendimento"]) ->
        Map.get(cat_map, "Moradia")

      String.contains?(desc_lower, [
        "sesi",
        "educação",
        "educacao",
        "escola",
        "universidade",
        "fundacao de apoio"
      ]) ->
        Map.get(cat_map, "Educação")

      String.contains?(desc_lower, ["transferência recebida", "transferencia recebida"]) ->
        Map.get(cat_map, "Salário")

      String.contains?(desc_lower, [
        "transferência enviada",
        "transferencia enviada",
        "transferencia pix",
        "transferência pix",
        "pix qr code"
      ]) ->
        Map.get(cat_map, "Transferências")

      String.contains?(desc_lower, ["pagamento de fatura"]) ->
        Map.get(cat_map, "Pagamentos")

      String.contains?(desc_lower, ["pagamento de boleto", "pagto eletron"]) ->
        Map.get(cat_map, "Pagamentos")

      String.contains?(desc_lower, [
        "investimento",
        "resgate",
        "rdb",
        "nuvest",
        "nuinvest",
        "criptomoeda",
        "rendimento",
        "rentab",
        "capitalizacao"
      ]) ->
        Map.get(cat_map, "Investimentos")

      String.contains?(desc_lower, [
        "bytedance",
        "tiktok",
        "netflix",
        "spotify",
        "amazon",
        "mercado pago"
      ]) ->
        Map.get(cat_map, "Assinaturas")

      String.contains?(desc_lower, ["diversões", "diversoes", "farofa", "lazer"]) ->
        Map.get(cat_map, "Lazer")

      String.contains?(desc_lower, ["ferr", "ferram"]) ->
        Map.get(cat_map, "Compras")

      true ->
        Map.get(cat_map, "Sem Categoria")
    end
  end

  # Summaries

  def monthly_summary(user_id, year, month, opts \\ []) do
    date_from = Date.new!(year, month, 1)
    date_to = Date.end_of_month(date_from)

    base_opts = [date_from: date_from, date_to: date_to] ++ opts
    transactions = list_transactions(user_id, base_opts)

    build_summary(transactions)
  end

  def yearly_summary(user_id, year, opts \\ []) do
    date_from = Date.new!(year, 1, 1)
    date_to = Date.new!(year, 12, 31)

    base_opts = [date_from: date_from, date_to: date_to] ++ opts
    transactions = list_transactions(user_id, base_opts)

    build_summary(transactions)
  end

  defp build_summary(transactions) do
    total_income =
      transactions
      |> Enum.filter(&(&1.type == "credit"))
      |> Enum.reduce(Decimal.new(0), fn t, acc -> Decimal.add(acc, t.amount) end)

    total_expenses =
      transactions
      |> Enum.filter(&(&1.type == "debit"))
      |> Enum.reduce(Decimal.new(0), fn t, acc -> Decimal.add(acc, Decimal.abs(t.amount)) end)

    by_category =
      transactions
      |> Enum.filter(&(&1.type == "debit"))
      |> Enum.group_by(fn t -> t.category end)
      |> Enum.map(fn {category, txns} ->
        total =
          Enum.reduce(txns, Decimal.new(0), fn t, acc ->
            Decimal.add(acc, Decimal.abs(t.amount))
          end)

        %{category: category, total: total, count: length(txns)}
      end)
      |> Enum.sort_by(fn %{total: t} -> Decimal.to_float(t) end, :desc)

    %{
      total_income: total_income,
      total_expenses: total_expenses,
      balance: Decimal.sub(total_income, total_expenses),
      by_category: by_category,
      transactions: transactions,
      transaction_count: length(transactions)
    }
  end

  def available_months(user_id) do
    Transaction
    |> where([t], t.user_id == ^user_id)
    |> select([t], fragment("DISTINCT date_trunc('month', ?)", t.date))
    |> order_by([t], desc: fragment("date_trunc('month', ?)", t.date))
    |> Repo.all()
    |> Enum.map(fn dt ->
      date =
        case dt do
          %NaiveDateTime{} -> NaiveDateTime.to_date(dt)
          %DateTime{} -> DateTime.to_date(dt)
          %Date{} -> dt
        end

      {date.year, date.month}
    end)
  end

  def available_years(user_id) do
    user_id
    |> available_months()
    |> Enum.map(fn {y, _m} -> y end)
    |> Enum.uniq()
    |> Enum.sort(:desc)
  end

  def daily_spending(user_id, year, month, opts \\ []) do
    date_from = Date.new!(year, month, 1)
    date_to = Date.end_of_month(date_from)

    query =
      Transaction
      |> where(
        [t],
        t.user_id == ^user_id and t.type == "debit" and t.date >= ^date_from and
          t.date <= ^date_to
      )

    query = filter_by_bank(query, Keyword.get(opts, :bank), user_id)

    query
    |> group_by([t], t.date)
    |> select([t], %{date: t.date, total: sum(fragment("ABS(?)", t.amount))})
    |> order_by([t], asc: t.date)
    |> Repo.all()
  end

  def monthly_income_expenses(user_id, year) do
    date_from = Date.new!(year, 1, 1)
    date_to = Date.new!(year, 12, 31)

    Transaction
    |> where([t], t.user_id == ^user_id and t.date >= ^date_from and t.date <= ^date_to)
    |> group_by([t], [fragment("EXTRACT(MONTH FROM ?)::integer", t.date), t.type])
    |> select([t], %{
      month: fragment("EXTRACT(MONTH FROM ?)::integer", t.date),
      type: t.type,
      total: sum(fragment("ABS(?)", t.amount))
    })
    |> Repo.all()
    |> Enum.group_by(& &1.month)
    |> Enum.map(fn {month, items} ->
      income =
        Enum.find_value(items, Decimal.new(0), fn
          %{type: "credit", total: t} -> t
          _ -> nil
        end)

      expenses =
        Enum.find_value(items, Decimal.new(0), fn
          %{type: "debit", total: t} -> t
          _ -> nil
        end)

      %{month: month, income: income, expenses: expenses}
    end)
    |> Enum.sort_by(& &1.month)
  end

  def uncategorized_count(user_id) do
    uncat = get_uncategorized_category(user_id)

    query =
      case uncat do
        nil ->
          Transaction |> where([t], t.user_id == ^user_id and is_nil(t.category_id))

        %{id: id} ->
          Transaction
          |> where([t], t.user_id == ^user_id and (is_nil(t.category_id) or t.category_id == ^id))
      end

    Repo.aggregate(query, :count)
  end

  # AI Analyses

  def create_ai_analysis(attrs) do
    %AIAnalysis{}
    |> AIAnalysis.changeset(attrs)
    |> Repo.insert()
  end

  def list_ai_analyses(user_id) do
    AIAnalysis
    |> where([a], a.user_id == ^user_id)
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end

  def get_ai_analysis!(id), do: Repo.get!(AIAnalysis, id)

  def delete_ai_analysis(%AIAnalysis{} = analysis) do
    Repo.delete(analysis)
  end

  # Shared helpers

  def month_name(1), do: "Janeiro"
  def month_name(2), do: "Fevereiro"
  def month_name(3), do: "Março"
  def month_name(4), do: "Abril"
  def month_name(5), do: "Maio"
  def month_name(6), do: "Junho"
  def month_name(7), do: "Julho"
  def month_name(8), do: "Agosto"
  def month_name(9), do: "Setembro"
  def month_name(10), do: "Outubro"
  def month_name(11), do: "Novembro"
  def month_name(12), do: "Dezembro"

  def month_name_short(1), do: "Jan"
  def month_name_short(2), do: "Fev"
  def month_name_short(3), do: "Mar"
  def month_name_short(4), do: "Abr"
  def month_name_short(5), do: "Mai"
  def month_name_short(6), do: "Jun"
  def month_name_short(7), do: "Jul"
  def month_name_short(8), do: "Ago"
  def month_name_short(9), do: "Set"
  def month_name_short(10), do: "Out"
  def month_name_short(11), do: "Nov"
  def month_name_short(12), do: "Dez"
end
