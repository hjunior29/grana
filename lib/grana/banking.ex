defmodule Grana.Banking do
  import Ecto.Query
  alias Grana.Repo

  alias Grana.Banking.{
    BankStatement,
    Transaction,
    Category,
    CategoryRule,
    RecurringRule,
    AIAnalysis,
    FinancialGoal
  }

  # Categories

  def list_categories(user_id) do
    Category
    |> where([c], is_nil(c.user_id) or c.user_id == ^user_id)
    |> order_by([c], asc: c.name)
    |> Repo.all()
  end

  def get_category!(id, user_id) do
    Category
    |> where([c], c.id == ^id and (is_nil(c.user_id) or c.user_id == ^user_id))
    |> Repo.one!()
  end

  def create_category(attrs) do
    %Category{}
    |> Category.changeset(attrs)
    |> Repo.insert()
  end

  def update_category(%Category{} = category, attrs) do
    category
    |> Category.changeset(attrs)
    |> Repo.update()
  end

  def delete_category(%Category{is_system: true}), do: {:error, :system_category}

  def delete_category(%Category{} = category) do
    Repo.delete(category)
  end

  def category_stats(user_id) do
    Category
    |> where([c], is_nil(c.user_id) or c.user_id == ^user_id)
    |> join(:left, [c], t in Transaction, on: t.category_id == c.id)
    |> join(:left, [c, _t], r in CategoryRule, on: r.category_id == c.id)
    |> group_by([c, _t, _r], c.id)
    |> select([c, t, r], %{
      category_id: c.id,
      transaction_count: count(t.id, :distinct),
      rule_count: count(r.id, :distinct)
    })
    |> Repo.all()
    |> Map.new(fn s -> {s.category_id, s} end)
  end

  def ensure_default_categories(user_id) do
    defaults = [
      %{name: "Alimentação", icon: "hero-cake", color: "#F59E0B", kind: "expense"},
      %{name: "Transporte", icon: "hero-truck", color: "#3B82F6", kind: "expense"},
      %{name: "Moradia", icon: "hero-home", color: "#8B5CF6", kind: "expense"},
      %{name: "Saúde", icon: "hero-heart", color: "#EF4444", kind: "expense"},
      %{name: "Lazer", icon: "hero-musical-note", color: "#EC4899", kind: "expense"},
      %{name: "Educação", icon: "hero-academic-cap", color: "#06B6D4", kind: "expense"},
      %{name: "Compras", icon: "hero-shopping-bag", color: "#F97316", kind: "expense"},
      %{
        name: "Transferências",
        icon: "hero-arrows-right-left",
        color: "#6366F1",
        kind: "expense"
      },
      %{name: "Investimentos", icon: "hero-chart-bar", color: "#10B981", kind: "investment"},
      %{name: "Rendimentos", icon: "hero-sparkles", color: "#14B8A6", kind: "income"},
      %{name: "Pagamentos", icon: "hero-credit-card", color: "#64748B", kind: "expense"},
      %{name: "Salário", icon: "hero-banknotes", color: "#22C55E", kind: "income"},
      %{name: "Assinaturas", icon: "hero-arrow-path", color: "#A855F7", kind: "expense"},
      %{
        name: "Sem Categoria",
        icon: "hero-question-mark-circle",
        color: "#9CA3AF",
        kind: "expense"
      }
    ]

    Enum.each(defaults, fn cat_attrs ->
      attrs = Map.merge(cat_attrs, %{user_id: user_id, is_system: true})

      %Category{}
      |> Category.system_changeset(attrs)
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

  def get_statement!(id, user_id) do
    BankStatement
    |> where([s], s.id == ^id and s.user_id == ^user_id)
    |> Repo.one!()
  end

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

  def delete_statements(ids, user_id) when is_list(ids) do
    BankStatement
    |> where([s], s.id in ^ids and s.user_id == ^user_id)
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

  @doc """
  Análise de despesas fixas (recorrentes) vs variáveis.

  `:window` é o número de meses analisados (default 6) ou `:all` para tudo.
  Considera apenas despesas reais: débitos, sem transferências internas, sem
  parcelas (já têm visão própria) e fora de categorias de investimento. As
  regras salvas pelo usuário definem o estado efetivo quando existem.
  """
  def recurring_analysis(user_id, opts \\ []) do
    today = Keyword.get(opts, :today, Date.utc_today())
    window = Keyword.get(opts, :window, 6)

    list_opts =
      [type: "debit", internal: "hide", date_from: window_start(today, window)]
      |> maybe_put(:bank, Keyword.get(opts, :bank))
      |> maybe_put(:statement_type, Keyword.get(opts, :statement_type))

    expenses =
      list_transactions(user_id, list_opts)
      |> Enum.reject(&(&1.installment_total != nil))
      |> Enum.reject(&investment_category?/1)

    Grana.Banking.RecurringExpenses.analyze(expenses, rules: recurring_rules_map(user_id))
  end

  defp maybe_put(opts, _key, value) when value in [nil, "all"], do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp investment_category?(%{category: %{kind: "investment"}}), do: true
  defp investment_category?(_), do: false

  defp window_start(_today, :all), do: nil

  defp window_start(today, months) when is_integer(months) do
    total = today.year * 12 + (today.month - 1) - (months - 1)
    Date.new!(div(total, 12), rem(total, 12) + 1, 1)
  end

  # Regras de recorrência por comerciante.

  def list_recurring_rules(user_id) do
    RecurringRule
    |> where([r], r.user_id == ^user_id)
    |> order_by([r], asc: r.pattern)
    |> Repo.all()
  end

  defp recurring_rules_map(user_id) do
    user_id
    |> list_recurring_rules()
    |> Map.new(fn r -> {r.pattern, r.mode} end)
  end

  @doc "Marca um comerciante como fixo/variável (cria ou atualiza a regra)."
  def upsert_recurring_rule(user_id, pattern, mode) do
    pattern = Grana.Banking.RecurringExpenses.normalize(pattern)

    %RecurringRule{}
    |> RecurringRule.changeset(%{user_id: user_id, pattern: pattern, mode: mode})
    |> Repo.insert(
      on_conflict: [set: [mode: mode, updated_at: DateTime.utc_now(:second)]],
      conflict_target: [:user_id, :pattern]
    )
  end

  @doc "Remove a regra de recorrência do comerciante."
  def delete_recurring_rule(user_id, pattern) do
    pattern = Grana.Banking.RecurringExpenses.normalize(pattern)

    RecurringRule
    |> where([r], r.user_id == ^user_id and r.pattern == ^pattern)
    |> Repo.delete_all()
  end

  @doc """
  Define o modo de recorrência a partir de uma transação do usuário.

  A regra é gravada pelo comerciante normalizado da transação, então variações do
  mesmo lançamento e importações futuras passam a seguir o modo escolhido.
  """
  def set_transaction_recurring_mode(user_id, transaction_id, mode)
      when mode in ["fixed", "variable"] do
    transaction = get_transaction!(transaction_id, user_id)

    if recurring_manageable_transaction?(transaction) do
      upsert_recurring_rule(user_id, transaction.description, mode)
    else
      {:error, :not_recurring_expense}
    end
  end

  def set_transaction_recurring_mode(_user_id, _transaction_id, _mode),
    do: {:error, :invalid_mode}

  def recurring_manageable_transaction?(%Transaction{} = transaction) do
    transaction.type == "debit" and
      transaction.is_internal_transfer == false and
      is_nil(transaction.installment_total) and
      not investment_category?(transaction)
  end

  @doc """
  Retorna o estado efetivo de recorrência para transações já carregadas.

  O resultado é um mapa `%{transaction_id => %{status, pattern, editable}}`.
  """
  def recurring_statuses(user_id, transactions, opts \\ []) do
    rules = recurring_rules_map(user_id)
    analysis = recurring_analysis(user_id, opts)

    fixed_patterns =
      ((analysis.fixed |> Enum.flat_map(& &1.patterns)) ++
         (rules
          |> Enum.filter(fn {_pattern, mode} -> mode == "fixed" end)
          |> Enum.map(&elem(&1, 0))))
      |> MapSet.new()

    Map.new(transactions, fn transaction ->
      pattern = Grana.Banking.RecurringExpenses.normalize(transaction.description)

      status =
        cond do
          not recurring_manageable_transaction?(transaction) -> "none"
          Map.get(rules, pattern) == "fixed" -> "fixed"
          Map.get(rules, pattern) == "variable" -> "variable"
          MapSet.member?(fixed_patterns, pattern) -> "fixed"
          true -> "variable"
        end

      {transaction.id, %{status: status, pattern: pattern, editable: status != "none"}}
    end)
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

    query = filter_by_category(query, Keyword.get(opts, :category_id))
    query = filter_by_uncategorized(query, Keyword.get(opts, :uncategorized), user_id)
    query = filter_by_statement(query, Keyword.get(opts, :bank_statement_id))
    query = filter_by_statement_ids(query, Keyword.get(opts, :bank_statement_ids))
    query = filter_by_date_from(query, Keyword.get(opts, :date_from))
    query = filter_by_date_to(query, Keyword.get(opts, :date_to))
    query = filter_by_search(query, Keyword.get(opts, :search))
    query = filter_by_bank(query, Keyword.get(opts, :bank), user_id)
    query = filter_by_statement_type(query, Keyword.get(opts, :statement_type), user_id)
    query = filter_by_type(query, Keyword.get(opts, :type))
    query = filter_by_amount_min(query, Keyword.get(opts, :amount_min))
    query = filter_by_amount_max(query, Keyword.get(opts, :amount_max))
    query = filter_by_internal(query, Keyword.get(opts, :internal))

    sort_transactions(
      query,
      Keyword.get(opts, :sort_by, "date"),
      Keyword.get(opts, :sort_dir, "desc")
    )
  end

  defp sort_transactions(query, sort_by, sort_dir) do
    dir = if sort_dir == "asc", do: :asc, else: :desc

    case sort_by do
      "description" ->
        order_by(query, [t], [{^dir, t.description}, {^dir, t.id}])

      "bank" ->
        query
        |> join(:left, [t], bs in assoc(t, :bank_statement), as: :sort_bank_statement)
        |> order_by([t, sort_bank_statement: bs], [{^dir, bs.bank}, {^dir, t.date}, {^dir, t.id}])

      "category" ->
        query
        |> join(:left, [t], c in assoc(t, :category), as: :sort_category)
        |> order_by([t, sort_category: c], [{^dir, c.name}, {^dir, t.date}, {^dir, t.id}])

      "type" ->
        order_by(query, [t], [{^dir, t.type}, {^dir, t.date}, {^dir, t.id}])

      "amount" ->
        order_by(query, [t], [{^dir, fragment("ABS(?)", t.amount)}, {^dir, t.date}, {^dir, t.id}])

      _ ->
        order_by(query, [t], [{^dir, t.date}, {^dir, t.id}])
    end
  end

  defp filter_by_category(query, nil), do: query
  defp filter_by_category(query, id), do: where(query, [t], t.category_id == ^id)

  defp filter_by_uncategorized(query, true, user_id) do
    uncat_ids =
      Category
      |> where([c], c.name == "Sem Categoria" and c.user_id == ^user_id)
      |> select([c], c.id)

    where(query, [t], is_nil(t.category_id) or t.category_id in subquery(uncat_ids))
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

  defp filter_by_search(query, term) do
    pattern = "%#{term}%"

    cat_ids =
      Category
      |> where([c], ilike(c.name, ^pattern))
      |> select([c], c.id)

    where(query, [t], ilike(t.description, ^pattern) or t.category_id in subquery(cat_ids))
  end

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

  defp filter_by_type(query, "investment") do
    query
    |> join(:inner, [t], c in Category, on: t.category_id == c.id and c.kind == "investment")
  end

  defp filter_by_type(query, type), do: where(query, [t], t.type == ^type)

  defp filter_by_statement_type(query, nil, _user_id), do: query
  defp filter_by_statement_type(query, "all", _user_id), do: query

  defp filter_by_statement_type(query, st_type, user_id) do
    stmt_ids =
      BankStatement
      |> where([bs], bs.user_id == ^user_id and bs.statement_type == ^st_type)
      |> select([bs], bs.id)

    where(query, [t], t.bank_statement_id in subquery(stmt_ids))
  end

  defp filter_by_statement_ids(query, nil), do: query

  defp filter_by_statement_ids(query, ids) do
    where(query, [t], t.bank_statement_id in ^ids)
  end

  defp filter_by_amount_min(query, nil), do: query

  defp filter_by_amount_min(query, min) do
    where(query, [t], fragment("ABS(?)", t.amount) >= ^min)
  end

  defp filter_by_amount_max(query, nil), do: query

  defp filter_by_amount_max(query, max) do
    where(query, [t], fragment("ABS(?)", t.amount) <= ^max)
  end

  defp filter_by_internal(query, nil), do: query
  defp filter_by_internal(query, "all"), do: query
  defp filter_by_internal(query, "hide"), do: where(query, [t], t.is_internal_transfer == false)
  defp filter_by_internal(query, "only"), do: where(query, [t], t.is_internal_transfer == true)

  def get_transaction!(id, user_id) do
    Transaction
    |> where([t], t.id == ^id and t.user_id == ^user_id)
    |> Repo.one!()
    |> Repo.preload([:category, :bank_statement])
  end

  def update_transaction(transaction, attrs) do
    transaction
    |> Transaction.changeset(attrs)
    |> Repo.update()
  end

  def bulk_update_categories(transaction_ids, category_id, user_id) do
    from(t in Transaction,
      where: t.id in ^transaction_ids and t.user_id == ^user_id
    )
    |> Repo.update_all(set: [category_id: category_id, updated_at: DateTime.utc_now(:second)])
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

  # Internal Transfer Detection

  # Known credit card company names used with "pagto eletron" detection
  @cc_issuers [
    "nu pagamentos",
    "nubank"
  ]

  # Standalone patterns that always indicate CC bill payment. Quando a fatura do
  # cartão é importada, o lançamento agregado no extrato ("GASTOS CARTAO DE
  # CREDITO", "GASTOS CARTOES", etc.) duplica os gastos detalhados da fatura —
  # por isso é tratado como transferência interna e excluído dos totais.
  @cc_payment_patterns [
    "pagamento de fatura",
    "pag fatura",
    "pgto fatura",
    "gastos cartao",
    "gastos cartoes",
    "gasto cartao",
    "gastos com cartao"
  ]

  @transfer_patterns [
    "pix",
    "transferência",
    "transferencia",
    "ted",
    "doc",
    "transf "
  ]

  # Créditos no extrato que representam a liquidação em conta de um provento da
  # B3 (dividendo/JCP/rendimento). NÃO inclui "rentab" — esse é o rendimento do
  # produto do próprio banco, que não existe na B3 e nunca deve ser deduplicado.
  @b3_income_patterns [
    "pgto de rendimento",
    "dividendo",
    "provento",
    "jcp"
  ]

  def detect_internal_transfers(user_id) do
    Repo.transaction(fn ->
      # 1) Reset all
      Transaction
      |> where([t], t.user_id == ^user_id and t.is_internal_transfer == true)
      |> Repo.update_all(
        set: [is_internal_transfer: false, updated_at: DateTime.utc_now(:second)]
      )

      # 2) Mark credit card bill payments in extratos
      mark_cc_bill_payments(user_id)

      # 3) Mark matching inter-account transfers
      mark_inter_account_transfers(user_id)

      # 4) Mark investment income that already landed as a B3 provento (avoids
      #    counting the same rendimento twice: bank credit + B3 provento).
      mark_investment_income_settlements(user_id)
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp mark_cc_bill_payments(user_id) do
    extrato_stmt_ids =
      BankStatement
      |> where([bs], bs.user_id == ^user_id and bs.statement_type == "extrato")
      |> select([bs], bs.id)

    transactions =
      Transaction
      |> where([t], t.user_id == ^user_id and t.type == "debit")
      |> where([t], t.bank_statement_id in subquery(extrato_stmt_ids))
      |> Repo.all()

    cc_payment_ids =
      transactions
      |> Enum.filter(fn t ->
        desc = String.downcase(t.description)

        Enum.any?(@cc_payment_patterns, &String.contains?(desc, &1)) or
          (String.contains?(desc, "pagto eletron") and
             Enum.any?(@cc_issuers, &String.contains?(desc, &1)))
      end)
      |> Enum.map(& &1.id)

    if cc_payment_ids != [] do
      Transaction
      |> where([t], t.id in ^cc_payment_ids)
      |> Repo.update_all(set: [is_internal_transfer: true, updated_at: DateTime.utc_now(:second)])
    end
  end

  defp mark_inter_account_transfers(user_id) do
    # Load all transactions with their bank info
    transactions =
      Transaction
      |> where([t], t.user_id == ^user_id and t.is_internal_transfer == false)
      |> preload(:bank_statement)
      |> Repo.all()

    # Filter to only transfer-like descriptions
    transfer_txns =
      Enum.filter(transactions, fn t ->
        desc = String.downcase(t.description)
        Enum.any?(@transfer_patterns, &String.contains?(desc, &1))
      end)

    {debits, credits} = Enum.split_with(transfer_txns, &(&1.type == "debit"))

    # Match debits with credits from different banks, same amount, close dates
    matched_ids = find_transfer_matches(debits, credits)

    if matched_ids != [] do
      Transaction
      |> where([t], t.id in ^matched_ids)
      |> Repo.update_all(set: [is_internal_transfer: true, updated_at: DateTime.utc_now(:second)])
    end
  end

  defp find_transfer_matches(debits, credits) do
    # Índice de créditos por valor (em centavos) para evitar varrer todos os
    # créditos por débito (O(n²) → ~O(n)). group_by preserva a ordem original
    # dentro de cada bucket, e o Decimal.equal? no predicado mantém a precisão.
    credits_by_amount = Enum.group_by(credits, &transfer_amount_key(&1.amount))

    # Track which credits have already been matched to avoid double-matching
    {matched_ids, _used_credits} =
      Enum.reduce(debits, {[], MapSet.new()}, fn debit, {ids, used} ->
        debit_amount = Decimal.abs(debit.amount)
        debit_bank = debit.bank_statement && debit.bank_statement.bank
        candidates = Map.get(credits_by_amount, transfer_amount_key(debit.amount), [])

        match =
          Enum.find(candidates, fn credit ->
            credit_bank = credit.bank_statement && credit.bank_statement.bank

            not MapSet.member?(used, credit.id) and
              credit_bank != debit_bank and
              Decimal.equal?(Decimal.abs(credit.amount), debit_amount) and
              abs(Date.diff(debit.date, credit.date)) <= 3
          end)

        case match do
          nil -> {ids, used}
          credit -> {[debit.id, credit.id | ids], MapSet.put(used, credit.id)}
        end
      end)

    matched_ids
  end

  # Chave de agrupamento por valor absoluto em centavos (money tem 2 casas).
  defp transfer_amount_key(amount) do
    amount |> Decimal.abs() |> Decimal.mult(100) |> Decimal.round() |> Decimal.to_integer()
  end

  # Marca créditos de rendimento no extrato que correspondem a um provento já
  # registrado na B3 (mesmo valor, mesmo dia). Reusa is_internal_transfer: o
  # crédito é só a liquidação em conta de um provento — o valor é contado na B3,
  # não como receita bancária. Só marca quando o provento de fato existe; sem a
  # B3 importada, o crédito continua contando normalmente.
  defp mark_investment_income_settlements(user_id) do
    extrato_stmt_ids =
      BankStatement
      |> where([bs], bs.user_id == ^user_id and bs.statement_type == "extrato")
      |> select([bs], bs.id)

    candidates =
      Transaction
      |> where(
        [t],
        t.user_id == ^user_id and t.type == "credit" and t.is_internal_transfer == false
      )
      |> where([t], t.bank_statement_id in subquery(extrato_stmt_ids))
      |> Repo.all()
      |> Enum.filter(fn t ->
        desc = String.downcase(t.description)
        Enum.any?(@b3_income_patterns, &String.contains?(desc, &1))
      end)

    matched_ids = find_settlement_matches(candidates, Grana.Investments.list_proventos(user_id))

    if matched_ids != [] do
      Transaction
      |> where([t], t.id in ^matched_ids)
      |> Repo.update_all(set: [is_internal_transfer: true, updated_at: DateTime.utc_now(:second)])
    end
  end

  defp find_settlement_matches(_candidates, []), do: []

  defp find_settlement_matches(candidates, proventos) do
    proventos_by_key = Enum.group_by(proventos, &settlement_key(&1.date, &1.amount))

    # MapSet evita que dois créditos casem com o mesmo provento.
    {matched_ids, _used} =
      Enum.reduce(candidates, {[], MapSet.new()}, fn credit, {ids, used} ->
        bucket = Map.get(proventos_by_key, settlement_key(credit.date, credit.amount), [])

        match =
          Enum.find(bucket, fn p ->
            not MapSet.member?(used, p.id) and
              Decimal.equal?(Decimal.abs(p.amount), Decimal.abs(credit.amount))
          end)

        case match do
          nil -> {ids, used}
          p -> {[credit.id | ids], MapSet.put(used, p.id)}
        end
      end)

    matched_ids
  end

  # Mesma data + mesmo valor (em centavos). Janela de data = mesmo dia.
  defp settlement_key(date, amount), do: {date, transfer_amount_key(amount)}

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
    categorize_transaction_with_rules(description, rules, user_id)
  end

  @doc """
  Categorize multiple descriptions at once, loading rules only once.
  Returns a map of %{description => category_id}.
  """
  def categorize_transactions(descriptions, user_id) when is_list(descriptions) do
    rules = list_category_rules(user_id)

    Map.new(descriptions, fn description ->
      {description, categorize_transaction_with_rules(description, rules, user_id)}
    end)
  end

  @doc false
  def categorize_transaction_with_rules(description, rules, user_id) do
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

      String.contains?(desc_lower, [
        "salário",
        "salario",
        "folha de pagamento",
        "pro-labore",
        "pró-labore"
      ]) ->
        Map.get(cat_map, "Salário")

      String.contains?(desc_lower, [
        "transferência recebida",
        "transferencia recebida",
        "transferência enviada",
        "transferencia enviada",
        "transferencia pix",
        "transferência pix",
        "pix qr code"
      ]) ->
        Map.get(cat_map, "Transferências")

      String.contains?(desc_lower, ["pagamento de fatura", "pagamento recebido"]) ->
        Map.get(cat_map, "Pagamentos")

      String.contains?(desc_lower, ["pagamento de boleto", "pagto eletron"]) ->
        Map.get(cat_map, "Pagamentos")

      String.contains?(desc_lower, ["rendimento", "rentab"]) ->
        Map.get(cat_map, "Rendimentos")

      String.contains?(desc_lower, [
        "investimento",
        "resgate",
        "rdb",
        "nuvest",
        "nuinvest",
        "criptomoeda",
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

  # Helpers

  @doc """
  Returns a list of bank_statement IDs for faturas whose period_end falls in the given month.
  This is used to correctly associate fatura transactions with the billing month,
  since transaction dates may belong to the previous month.
  """
  def fatura_ids_for_month(user_id, year, month, opts \\ []) do
    date_from = Date.new!(year, month, 1)
    date_to = Date.end_of_month(date_from)

    query =
      BankStatement
      |> where(
        [bs],
        bs.user_id == ^user_id and bs.statement_type == "fatura" and
          bs.period_end >= ^date_from and bs.period_end <= ^date_to
      )

    query = filter_stmt_by_bank(query, Keyword.get(opts, :bank))

    query
    |> select([bs], bs.id)
    |> Repo.all()
  end

  defp filter_stmt_by_bank(query, nil), do: query
  defp filter_stmt_by_bank(query, "all"), do: query
  defp filter_stmt_by_bank(query, bank), do: where(query, [bs], bs.bank == ^bank)

  # Summaries

  def monthly_summary(user_id, year, month, opts \\ []) do
    date_from = Date.new!(year, month, 1)
    date_to = Date.end_of_month(date_from)

    base_opts =
      case Keyword.get(opts, :statement_type) do
        "fatura" ->
          stmt_ids = fatura_ids_for_month(user_id, year, month, opts)
          Keyword.delete(opts, :statement_type) ++ [bank_statement_ids: stmt_ids]

        _ ->
          [date_from: date_from, date_to: date_to] ++ opts
      end

    transactions = list_transactions(user_id, base_opts)

    build_summary(transactions)
  end

  def all_time_summary(user_id, opts \\ []) do
    transactions = list_transactions(user_id, opts)
    build_summary(transactions)
  end

  def yearly_summary(user_id, year, opts \\ []) do
    date_from = Date.new!(year, 1, 1)
    date_to = Date.new!(year, 12, 31)

    base_opts =
      case Keyword.get(opts, :statement_type) do
        "fatura" ->
          stmt_ids =
            Enum.flat_map(1..12, fn month ->
              fatura_ids_for_month(user_id, year, month, opts)
            end)
            |> Enum.uniq()

          Keyword.delete(opts, :statement_type) ++ [bank_statement_ids: stmt_ids]

        _ ->
          [date_from: date_from, date_to: date_to] ++ opts
      end

    transactions = list_transactions(user_id, base_opts)

    build_summary(transactions)
  end

  defp build_summary(transactions) do
    # 0) Exclude internal transfers (CC bill payments from extrato, inter-account PIX, etc.)
    {internal, non_internal} = Enum.split_with(transactions, & &1.is_internal_transfer)

    # 1) Exclude bill payments entirely (e.g. "Pagamento recebido" in Nubank fatura)
    {_payments, relevant} = Enum.split_with(non_internal, &bill_payment?/1)

    # 2) Separate refunds (estornos) — these discount from expenses
    {refunds, rest} = Enum.split_with(relevant, &refund?/1)

    # 3) Income = remaining credits (real income from extratos)
    income_txns = Enum.filter(rest, &(&1.type == "credit"))

    total_income =
      Enum.reduce(income_txns, Decimal.new(0), fn t, acc ->
        Decimal.add(acc, Decimal.abs(t.amount))
      end)

    # 4) All debits
    debits = Enum.filter(rest, &(&1.type == "debit"))

    # 5) Separate investments from real expenses
    {investment_debits, expense_debits} =
      Enum.split_with(debits, fn t ->
        t.category && t.category.kind == "investment"
      end)

    total_investments =
      Enum.reduce(investment_debits, Decimal.new(0), fn t, acc ->
        Decimal.add(acc, Decimal.abs(t.amount))
      end)

    # 6) Gross expenses = debits in expense categories only
    gross_expenses =
      Enum.reduce(expense_debits, Decimal.new(0), fn t, acc ->
        Decimal.add(acc, Decimal.abs(t.amount))
      end)

    # 7) Refund total to subtract from expenses
    refund_total =
      Enum.reduce(refunds, Decimal.new(0), fn t, acc ->
        Decimal.add(acc, Decimal.abs(t.amount))
      end)

    total_expenses = Decimal.sub(gross_expenses, refund_total)

    by_category =
      expense_debits
      |> Enum.group_by(fn t -> t.category end)
      |> Enum.map(fn {category, txns} ->
        total =
          Enum.reduce(txns, Decimal.new(0), fn t, acc ->
            Decimal.add(acc, Decimal.abs(t.amount))
          end)

        %{category: category, total: total, count: length(txns)}
      end)
      |> Enum.sort_by(fn %{total: t} -> Decimal.to_float(t) end, :desc)

    # Pre-compute only the top debits/credits instead of returning (and holding
    # in LiveView assigns) the full transaction list, which can be thousands of rows.
    # 15 covers both the dashboard (shows 10) and the AI prompt (uses up to 15).
    top_expenses = top_n_by_amount(transactions, "debit", 15)
    top_income = top_n_by_amount(transactions, "credit", 15)

    %{
      total_income: total_income,
      total_expenses: total_expenses,
      total_investments: total_investments,
      balance: Decimal.sub(total_income, Decimal.add(total_expenses, total_investments)),
      by_category: by_category,
      top_expenses: top_expenses,
      top_income: top_income,
      transaction_count: length(relevant),
      income_count: length(income_txns),
      expense_count: length(expense_debits),
      investment_count: length(investment_debits),
      refund_count: length(refunds),
      internal_count: length(internal)
    }
  end

  defp top_n_by_amount(transactions, type, limit) do
    transactions
    |> Enum.filter(&(&1.type == type))
    |> Enum.sort_by(fn t -> Decimal.to_float(Decimal.abs(t.amount)) end, :desc)
    |> Enum.take(limit)
  end

  defp bill_payment?(t) do
    desc = String.downcase(t.description)

    t.type == "credit" and
      (String.contains?(desc, "pagamento recebido") or
         String.contains?(desc, "pagamento de fatura") or
         String.contains?(desc, "pagto fatura") or
         String.contains?(desc, "pag fatura")) and
      not String.contains?(desc, "estorno")
  end

  defp refund?(t) do
    desc = String.downcase(t.description)

    t.type == "credit" and
      (String.contains?(desc, "estorno") or
         String.contains?(desc, "devolução") or
         String.contains?(desc, "devoluç") or
         String.contains?(desc, "reembolso") or
         String.contains?(desc, "chargeback"))
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
    |> Enum.sort(:asc)
  end

  def daily_spending(user_id, year, month, opts \\ []) do
    date_from = Date.new!(year, month, 1)
    date_to = Date.end_of_month(date_from)

    investment_cat_ids =
      Category
      |> where([c], (is_nil(c.user_id) or c.user_id == ^user_id) and c.kind == "investment")
      |> select([c], c.id)

    query =
      case Keyword.get(opts, :statement_type) do
        "fatura" ->
          stmt_ids = fatura_ids_for_month(user_id, year, month, opts)

          Transaction
          |> where(
            [t],
            t.user_id == ^user_id and t.type == "debit" and
              t.bank_statement_id in ^stmt_ids and t.is_internal_transfer == false
          )

        _ ->
          base =
            Transaction
            |> where(
              [t],
              t.user_id == ^user_id and t.type == "debit" and t.date >= ^date_from and
                t.date <= ^date_to and t.is_internal_transfer == false
            )

          base
          |> filter_by_bank(Keyword.get(opts, :bank), user_id)
          |> filter_by_statement_type(Keyword.get(opts, :statement_type), user_id)
      end

    query
    |> where([t], t.category_id not in subquery(investment_cat_ids) or is_nil(t.category_id))
    |> group_by([t], t.date)
    |> select([t], %{date: t.date, total: sum(fragment("ABS(?)", t.amount))})
    |> order_by([t], asc: t.date)
    |> Repo.all()
  end

  def monthly_income_expenses(user_id, year, opts \\ []) do
    is_fatura = Keyword.get(opts, :statement_type) == "fatura"

    list_opts =
      if is_fatura do
        # For fatura, get all fatura statements for the year and fetch their transactions
        stmt_ids =
          Enum.flat_map(1..12, fn month ->
            fatura_ids_for_month(user_id, year, month, opts)
          end)
          |> Enum.uniq()

        Keyword.take(opts, [:bank, :type]) ++ [bank_statement_ids: stmt_ids]
      else
        [date_from: Date.new!(year, 1, 1), date_to: Date.new!(year, 12, 31)]
        |> Keyword.merge(Keyword.take(opts, [:bank, :statement_type, :type]))
      end

    transactions = list_transactions(user_id, list_opts)

    # Build a statement_id -> period_end month map for fatura grouping
    stmt_month_map =
      if is_fatura do
        transactions
        |> Enum.map(& &1.bank_statement)
        |> Enum.uniq_by(& &1.id)
        |> Enum.reject(&is_nil(&1.period_end))
        |> Map.new(fn bs -> {bs.id, bs.period_end.month} end)
      else
        %{}
      end

    group_fn =
      if is_fatura do
        fn t -> Map.get(stmt_month_map, t.bank_statement_id, t.date.month) end
      else
        fn t -> t.date.month end
      end

    transactions
    |> Enum.reject(& &1.is_internal_transfer)
    |> Enum.group_by(group_fn)
    |> Enum.map(fn {month, txns} ->
      relevant = Enum.reject(txns, &bill_payment?/1)
      {refunds, rest} = Enum.split_with(relevant, &refund?/1)

      income =
        rest
        |> Enum.filter(&(&1.type == "credit"))
        |> Enum.reduce(Decimal.new(0), fn t, acc -> Decimal.add(acc, Decimal.abs(t.amount)) end)

      debits = Enum.filter(rest, &(&1.type == "debit"))

      {inv_debits, exp_debits} =
        Enum.split_with(debits, fn t -> t.category && t.category.kind == "investment" end)

      gross_expenses =
        Enum.reduce(exp_debits, Decimal.new(0), fn t, acc ->
          Decimal.add(acc, Decimal.abs(t.amount))
        end)

      investments =
        Enum.reduce(inv_debits, Decimal.new(0), fn t, acc ->
          Decimal.add(acc, Decimal.abs(t.amount))
        end)

      refund_total =
        Enum.reduce(refunds, Decimal.new(0), fn t, acc ->
          Decimal.add(acc, Decimal.abs(t.amount))
        end)

      %{
        month: month,
        income: income,
        expenses: Decimal.sub(gross_expenses, refund_total),
        investments: investments
      }
    end)
    |> Enum.sort_by(& &1.month)
  end

  def transactions_summary(user_id, opts) do
    build_transactions_query(user_id, opts)
    |> exclude(:preload)
    |> exclude(:order_by)
    |> where([t], t.is_internal_transfer == false)
    |> join(:left, [t], c in Category, on: t.category_id == c.id)
    |> select([t, c], %{
      total_income:
        coalesce(
          sum(fragment("CASE WHEN ? = 'credit' THEN ABS(?) ELSE 0 END", t.type, t.amount)),
          0
        ),
      total_expenses:
        coalesce(
          sum(
            fragment(
              "CASE WHEN ? = 'debit' AND (? IS NULL OR ? != 'investment') THEN ABS(?) ELSE 0 END",
              t.type,
              c.kind,
              c.kind,
              t.amount
            )
          ),
          0
        ),
      total_investments:
        coalesce(
          sum(
            fragment(
              "CASE WHEN ? = 'debit' AND ? = 'investment' THEN ABS(?) ELSE 0 END",
              t.type,
              c.kind,
              t.amount
            )
          ),
          0
        )
    })
    |> Repo.one()
  end

  def uncategorized_count(user_id) do
    uncat_ids =
      Category
      |> where([c], c.name == "Sem Categoria" and c.user_id == ^user_id)
      |> select([c], c.id)

    Transaction
    |> where(
      [t],
      t.user_id == ^user_id and (is_nil(t.category_id) or t.category_id in subquery(uncat_ids))
    )
    |> Repo.aggregate(:count)
  end

  # Installments

  def list_active_installments(user_id, opts \\ []) do
    base =
      Transaction
      |> where([t], t.user_id == ^user_id and not is_nil(t.installment_total))

    base = filter_by_bank(base, Keyword.get(opts, :bank), user_id)
    base = filter_by_statement_type(base, Keyword.get(opts, :statement_type), user_id)

    base =
      case {Keyword.get(opts, :year), Keyword.get(opts, :month)} do
        {year, month} when is_integer(year) and is_integer(month) and month > 0 ->
          date_from = Date.new!(year, month, 1)
          date_to = Date.new!(year, month, Date.days_in_month(date_from))
          base |> where([t], t.date >= ^date_from and t.date <= ^date_to)

        _ ->
          base
      end

    subquery =
      base
      |> group_by([t], t.installment_group_id)
      |> select([t], %{
        group_id: t.installment_group_id,
        max_current: max(t.installment_current)
      })

    Transaction
    |> join(:inner, [t], s in subquery(subquery),
      on: t.installment_group_id == s.group_id and t.installment_current == s.max_current
    )
    # IMPORTANTE: installment_group_id é um hash de descrição+total, então é
    # COMPARTILHADO entre usuários (ex.: "Netflix 12x"). Sem este escopo, a query
    # externa vazaria parcelas de outros usuários (IDOR).
    |> where([t, _s], t.user_id == ^user_id)
    |> where([t, _s], t.installment_current < t.installment_total)
    |> preload(:category)
    |> order_by([t], desc: fragment("ABS(?)", t.amount))
    |> Repo.all()
  end

  # Parcelas restantes, à prova de nil (a query já filtra current < total, mas
  # defendemos contra dados parciais para não derrubar a projeção).
  defp installments_remaining(%{installment_total: total, installment_current: current})
       when is_integer(total) and is_integer(current),
       do: max(total - current, 0)

  defp installments_remaining(_), do: 0

  def installment_projection_summary(user_id, opts \\ []) do
    installments = list_active_installments(user_id, opts)

    active_count = length(installments)

    total_remaining =
      Enum.reduce(installments, Decimal.new(0), fn txn, acc ->
        remaining = installments_remaining(txn)
        Decimal.add(acc, Decimal.mult(Decimal.abs(txn.amount), remaining))
      end)

    this_month_total =
      Enum.reduce(installments, Decimal.new(0), fn txn, acc ->
        Decimal.add(acc, Decimal.abs(txn.amount))
      end)

    %{
      active_count: active_count,
      total_remaining: total_remaining,
      this_month_total: this_month_total,
      installments: installments
    }
  end

  def monthly_installment_projections(user_id, months_ahead \\ 12, opts \\ []) do
    installments = list_active_installments(user_id, opts)

    start_date =
      case {Keyword.get(opts, :year), Keyword.get(opts, :month)} do
        {year, month} when is_integer(year) and is_integer(month) and month > 0 ->
          Date.new!(year, month, 1)

        _ ->
          Date.utc_today()
      end

    0..(months_ahead - 1)
    |> Enum.map(fn offset ->
      projected_date =
        Date.new!(start_date.year, start_date.month, 1) |> Date.shift(month: offset)

      month_label = "#{month_name_short(projected_date.month)}/#{projected_date.year}"

      total =
        Enum.reduce(installments, Decimal.new(0), fn txn, acc ->
          remaining = installments_remaining(txn)

          if offset < remaining do
            Decimal.add(acc, Decimal.abs(txn.amount))
          else
            acc
          end
        end)

      %{label: month_label, total: total}
    end)
    |> Enum.reject(fn %{total: t} -> Decimal.compare(t, 0) == :eq end)
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

  def get_ai_analysis!(id, user_id) do
    AIAnalysis
    |> where([a], a.id == ^id and a.user_id == ^user_id)
    |> Repo.one!()
  end

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

  # Financial Goals

  def list_financial_goals(user_id) do
    FinancialGoal
    |> where([g], g.user_id == ^user_id and g.active == true)
    |> preload(:category)
    |> order_by([g], asc: g.type)
    |> Repo.all()
  end

  def get_financial_goal!(id, user_id) do
    FinancialGoal
    |> where([g], g.id == ^id and g.user_id == ^user_id)
    |> preload(:category)
    |> Repo.one!()
  end

  def create_financial_goal(attrs) do
    %FinancialGoal{}
    |> FinancialGoal.changeset(attrs)
    |> validate_goal_category_ownership()
    |> Repo.insert()
  end

  def update_financial_goal(%FinancialGoal{} = goal, attrs) do
    goal
    |> FinancialGoal.changeset(attrs)
    |> validate_goal_category_ownership()
    |> Repo.update()
  end

  # Guards against cross-user reference: a goal's category must belong to the
  # same user. Without this, a crafted category_id from the client could attach
  # another user's category to the goal.
  defp validate_goal_category_ownership(changeset) do
    category_id = Ecto.Changeset.get_field(changeset, :category_id)
    user_id = Ecto.Changeset.get_field(changeset, :user_id)

    cond do
      is_nil(category_id) or is_nil(user_id) ->
        changeset

      category_belongs_to_user?(category_id, user_id) ->
        changeset

      true ->
        Ecto.Changeset.add_error(changeset, :category_id, "categoria inválida")
    end
  end

  @doc """
  Verdadeiro se a categoria pertence ao usuário. Use antes de gravar `category_id`
  vindo do cliente, evitando referência cross-tenant ou FK inválido.
  """
  def category_belongs_to_user?(category_id, user_id) do
    Category
    |> where([c], c.id == ^category_id and c.user_id == ^user_id)
    |> Repo.exists?()
  end

  def delete_financial_goal(%FinancialGoal{} = goal) do
    Repo.delete(goal)
  end

  def goals_progress(user_id, year, month) do
    goals = list_financial_goals(user_id)

    case goals do
      [] ->
        []

      _ ->
        summary = monthly_summary(user_id, year, month)

        Enum.map(goals, fn goal ->
          current =
            case goal.type do
              "expense_limit" -> summary.total_expenses
              "income_goal" -> summary.total_income
              "investment_goal" -> summary.total_investments
              "category_limit" -> category_total(summary, goal.category_id)
            end

          target = goal.target_value
          pct = calc_pct(current, target)
          status = goal_status(goal.type, pct)

          %{goal: goal, current: current, target: target, pct: pct, status: status}
        end)
    end
  end

  defp category_total(summary, category_id) do
    case Enum.find(summary.by_category, fn %{category: c} -> c && c.id == category_id end) do
      %{total: total} -> total
      nil -> Decimal.new(0)
    end
  end

  defp calc_pct(_current, target) when target == nil, do: 0.0

  defp calc_pct(current, target) do
    if Decimal.compare(target, 0) == :gt do
      current
      |> Decimal.div(target)
      |> Decimal.mult(100)
      |> Decimal.round(1)
      |> Decimal.to_float()
    else
      0.0
    end
  end

  defp goal_status(type, pct) when type in ["expense_limit", "category_limit"] do
    cond do
      pct >= 100 -> :exceeded
      pct >= 80 -> :warning
      true -> :on_track
    end
  end

  defp goal_status(_type, pct) do
    cond do
      pct >= 100 -> :achieved
      pct >= 70 -> :on_track
      true -> :behind
    end
  end

  def suggest_goals(user_id) do
    # Use the last 3 months that actually have data
    months =
      available_months(user_id)
      |> Enum.take(3)

    summaries =
      Enum.map(months, fn {y, m} -> monthly_summary(user_id, y, m) end)
      |> Enum.filter(fn s -> s.transaction_count > 0 end)

    case summaries do
      [] ->
        []

      summaries ->
        count = length(summaries)

        avg_expenses =
          summaries
          |> Enum.reduce(Decimal.new(0), fn s, acc -> Decimal.add(acc, s.total_expenses) end)
          |> Decimal.div(count)
          |> Decimal.round(0)

        avg_income =
          summaries
          |> Enum.reduce(Decimal.new(0), fn s, acc -> Decimal.add(acc, s.total_income) end)
          |> Decimal.div(count)
          |> Decimal.round(0)

        avg_investments =
          summaries
          |> Enum.reduce(Decimal.new(0), fn s, acc -> Decimal.add(acc, s.total_investments) end)
          |> Decimal.div(count)
          |> Decimal.round(0)

        existing = list_financial_goals(user_id) |> Enum.map(& &1.type)

        suggestions = []

        suggestions =
          if "expense_limit" not in existing and Decimal.compare(avg_expenses, 0) == :gt,
            do: [%{type: "expense_limit", avg: avg_expenses} | suggestions],
            else: suggestions

        suggestions =
          if "income_goal" not in existing and Decimal.compare(avg_income, 0) == :gt,
            do: [%{type: "income_goal", avg: avg_income} | suggestions],
            else: suggestions

        suggestions =
          if "investment_goal" not in existing and Decimal.compare(avg_investments, 0) == :gt,
            do: [%{type: "investment_goal", avg: avg_investments} | suggestions],
            else: suggestions

        suggestions
    end
  end
end
