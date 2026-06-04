defmodule Grana.Investments do
  import Ecto.Query
  alias Grana.Repo
  alias Grana.Investments.{Constants, Institution, Statement, Transaction}

  # Institutions

  def list_institutions(user_id) do
    Institution
    |> where([i], i.user_id == ^user_id)
    |> order_by([i], asc: i.name)
    |> Repo.all()
  end

  def get_institution!(id, user_id) do
    Institution
    |> where([i], i.id == ^id and i.user_id == ^user_id)
    |> Repo.one!()
  end

  def get_institution_by_slug(slug, user_id) do
    Institution
    |> where([i], i.slug == ^slug and i.user_id == ^user_id)
    |> Repo.one()
  end

  def ensure_b3_institution(user_id) do
    ensure_institution(user_id, "b3", "B3", "/images/b3-logo.png")
  end

  def ensure_gcb_institution(user_id) do
    ensure_institution(user_id, "gcb", "GCB", "/images/gcb-logo.png")
  end

  defp ensure_institution(user_id, slug, name, logo_path) do
    case get_institution_by_slug(slug, user_id) do
      nil ->
        {:ok, inst} =
          create_institution(%{
            name: name,
            slug: slug,
            logo_path: logo_path,
            is_system: true,
            user_id: user_id
          })

        inst

      %{logo_path: existing} = inst when existing != logo_path ->
        {:ok, inst} = update_institution(inst, %{logo_path: logo_path})
        inst

      inst ->
        inst
    end
  end

  def create_institution(attrs) do
    %Institution{}
    |> Institution.changeset(attrs)
    |> Repo.insert()
  end

  def update_institution(%Institution{} = institution, attrs) do
    institution
    |> Institution.changeset(attrs)
    |> Repo.update()
  end

  def delete_institution(%Institution{is_system: true}), do: {:error, :system_institution}

  def delete_institution(%Institution{} = institution) do
    Repo.delete(institution)
  end

  # Statements

  def list_statements(user_id) do
    Statement
    |> where([s], s.user_id == ^user_id)
    |> preload(:institution)
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
  end

  def list_statements_paginated(user_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    offset = (page - 1) * per_page

    base =
      Statement
      |> where([s], s.user_id == ^user_id)
      |> preload(:institution)
      |> order_by([s], desc: s.inserted_at)

    total = Repo.aggregate(base, :count)
    statements = base |> limit(^per_page) |> offset(^offset) |> Repo.all()

    {statements, total}
  end

  def get_statement!(id, user_id) do
    Statement
    |> where([s], s.id == ^id and s.user_id == ^user_id)
    |> preload(:institution)
    |> Repo.one!()
  end

  def create_statement(attrs) do
    %Statement{}
    |> Statement.changeset(attrs)
    |> Repo.insert()
  end

  def update_statement(statement, attrs) do
    statement
    |> Statement.changeset(attrs)
    |> Repo.update()
  end

  def delete_statement(statement) do
    Repo.delete(statement)
  end

  def delete_statements(ids, user_id) when is_list(ids) do
    Statement
    |> where([s], s.id in ^ids and s.user_id == ^user_id)
    |> Repo.delete_all()
  end

  # Transactions

  def list_transactions(user_id, opts \\ []) do
    user_id
    |> build_transactions_query(opts)
    |> Repo.all()
  end

  @doc """
  Proventos (dividendo/JCP/rendimento/amortização) do usuário, como mapas
  `%{id:, date:, amount:}`. Usado pela conciliação banking↔investimentos para
  evitar contar o mesmo rendimento duas vezes (crédito no extrato bancário +
  provento na B3).
  """
  def list_proventos(user_id) do
    ops = Grana.Investments.Constants.dividend_ops()

    Transaction
    |> where([t], t.user_id == ^user_id and t.operation in ^ops)
    |> select([t], %{id: t.id, date: t.date, amount: t.total_amount})
    |> Repo.all()
  end

  @doc "Meses ({ano, mês}) que têm transações de investimento. Para o heatmap mensal de uploads."
  def coverage_months(user_id) do
    Transaction
    |> where([t], t.user_id == ^user_id)
    |> select([t], t.date)
    |> distinct(true)
    |> Repo.all()
    |> MapSet.new(&{&1.year, &1.month})
  end

  @doc """
  Quantidade de uploads de investimentos distintos com dados em cada mês.

  Um mesmo arquivo com várias transações no mesmo mês conta apenas uma vez.
  """
  def upload_counts_by_month(user_id) do
    Transaction
    |> where([t], t.user_id == ^user_id)
    |> select([t], {t.date, t.statement_id})
    |> Repo.all()
    |> distinct_upload_counts()
  end

  def list_transactions_paginated(user_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 50)
    offset = (page - 1) * per_page

    base = build_transactions_query(user_id, opts)
    total = Repo.aggregate(base, :count)
    transactions = base |> limit(^per_page) |> offset(^offset) |> Repo.all()

    {transactions, total}
  end

  def investments_summary(user_id, opts \\ []) do
    build_transactions_query(user_id, opts)
    |> exclude(:preload)
    |> exclude(:order_by)
    |> select([t], %{
      total_compras:
        coalesce(
          sum(
            fragment("CASE WHEN ? = 'compra' THEN ABS(?) ELSE 0 END", t.operation, t.total_amount)
          ),
          0
        ),
      total_vendas:
        coalesce(
          sum(
            fragment("CASE WHEN ? = 'venda' THEN ABS(?) ELSE 0 END", t.operation, t.total_amount)
          ),
          0
        ),
      total_proventos:
        coalesce(
          sum(
            fragment(
              "CASE WHEN ? IN ('dividendo', 'jcp', 'rendimento', 'amortizacao') THEN ABS(?) ELSE 0 END",
              t.operation,
              t.total_amount
            )
          ),
          0
        ),
      total_taxas:
        coalesce(
          sum(
            fragment("CASE WHEN ? = 'taxa' THEN ABS(?) ELSE 0 END", t.operation, t.total_amount)
          ),
          0
        )
    })
    |> Repo.one()
  end

  defp build_transactions_query(user_id, opts) do
    query =
      Transaction
      |> where([t], t.user_id == ^user_id)
      |> preload([:institution, :statement])
      |> order_by([t], desc: t.date)

    query = filter_by_institution(query, Keyword.get(opts, :institution_id))
    query = filter_by_asset_type(query, Keyword.get(opts, :asset_type))
    query = filter_by_operation(query, Keyword.get(opts, :operation))

    query =
      filter_by_date_range(query, Keyword.get(opts, :date_from), Keyword.get(opts, :date_to))

    query = filter_by_ticker(query, Keyword.get(opts, :ticker))
    query = filter_by_search(query, Keyword.get(opts, :search))
    query = filter_by_amount_min(query, Keyword.get(opts, :amount_min))
    query = filter_by_amount_max(query, Keyword.get(opts, :amount_max))
    filter_by_statement(query, Keyword.get(opts, :statement_id))
  end

  defp distinct_upload_counts(rows) do
    rows
    |> Enum.reduce(MapSet.new(), fn {date, statement_id}, acc ->
      MapSet.put(acc, {date.year, date.month, statement_id})
    end)
    |> Enum.reduce(%{}, fn {year, month, _statement_id}, acc ->
      Map.update(acc, {year, month}, 1, &(&1 + 1))
    end)
  end

  defp filter_by_institution(query, nil), do: query
  defp filter_by_institution(query, "all"), do: query
  defp filter_by_institution(query, id), do: where(query, [t], t.institution_id == ^id)

  defp filter_by_asset_type(query, nil), do: query
  defp filter_by_asset_type(query, "all"), do: query
  defp filter_by_asset_type(query, type), do: where(query, [t], t.asset_type == ^type)

  defp filter_by_operation(query, nil), do: query
  defp filter_by_operation(query, "all"), do: query

  defp filter_by_operation(query, ops) when is_list(ops),
    do: where(query, [t], t.operation in ^ops)

  defp filter_by_operation(query, op), do: where(query, [t], t.operation == ^op)

  defp filter_by_date_range(query, nil, nil), do: query
  defp filter_by_date_range(query, from, nil), do: where(query, [t], t.date >= ^from)
  defp filter_by_date_range(query, nil, to), do: where(query, [t], t.date <= ^to)

  defp filter_by_date_range(query, from, to),
    do: where(query, [t], t.date >= ^from and t.date <= ^to)

  defp filter_by_ticker(query, nil), do: query
  defp filter_by_ticker(query, "all"), do: query
  defp filter_by_ticker(query, ticker), do: where(query, [t], t.asset_ticker == ^ticker)

  defp filter_by_search(query, nil), do: query
  defp filter_by_search(query, ""), do: query

  defp filter_by_search(query, term) do
    pattern = "%#{term}%"
    where(query, [t], ilike(t.asset_name, ^pattern) or ilike(t.asset_ticker, ^pattern))
  end

  defp filter_by_amount_min(query, nil), do: query

  defp filter_by_amount_min(query, min),
    do: where(query, [t], fragment("ABS(?)", t.total_amount) >= ^min)

  defp filter_by_statement(query, nil), do: query
  defp filter_by_statement(query, id), do: where(query, [t], t.statement_id == ^id)

  defp filter_by_amount_max(query, nil), do: query

  defp filter_by_amount_max(query, max),
    do: where(query, [t], fragment("ABS(?)", t.total_amount) <= ^max)

  def bulk_insert_transactions(transactions_attrs) do
    now = DateTime.utc_now(:second)

    # insert_all ignora o changeset; validamos cada entry e descartamos as
    # inválidas (campos obrigatórios, operation/asset_type fora do domínio) em
    # vez de persistir dado inconsistente.
    {valid, invalid} =
      Enum.split_with(transactions_attrs, fn attrs ->
        Transaction.changeset(%Transaction{}, attrs).valid?
      end)

    if invalid != [] do
      require Logger

      Logger.warning(
        "Investments.bulk_insert_transactions: #{length(invalid)} transação(ões) inválida(s) descartada(s)"
      )
    end

    entries =
      Enum.map(valid, fn attrs ->
        attrs
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    Repo.insert_all(Transaction, entries)
  end

  # Summary & Analytics

  def monthly_investments(user_id, year, opts \\ []) do
    date_from = Date.new!(year, 1, 1)
    date_to = Date.new!(year, 12, 31)
    all_opts = opts ++ [date_from: date_from, date_to: date_to]

    transactions = list_transactions(user_id, all_opts)

    transactions
    |> Enum.group_by(fn t -> t.date.month end)
    |> Enum.map(fn {month, txns} ->
      invested =
        txns
        |> Enum.filter(&(&1.operation == "compra"))
        |> Enum.reduce(Decimal.new(0), fn t, acc ->
          Decimal.add(acc, Decimal.abs(t.total_amount))
        end)

      dividends =
        txns
        |> Enum.filter(&(&1.operation in Constants.dividend_ops()))
        |> Enum.reduce(Decimal.new(0), fn t, acc ->
          Decimal.add(acc, Decimal.abs(t.total_amount))
        end)

      %{month: month, invested: invested, dividends: dividends}
    end)
    |> Enum.sort_by(& &1.month)
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

  def available_institutions(user_id) do
    Transaction
    |> where([t], t.user_id == ^user_id and not is_nil(t.institution_id))
    |> select([t], t.institution_id)
    |> distinct(true)
    |> Repo.all()
    |> then(fn ids ->
      Institution
      |> where([i], i.id in ^ids)
      |> order_by([i], asc: i.name)
      |> Repo.all()
    end)
  end

  def available_asset_types(user_id) do
    Transaction
    |> where([t], t.user_id == ^user_id)
    |> select([t], t.asset_type)
    |> distinct(true)
    |> Repo.all()
    |> Enum.sort()
  end

  def available_operations(user_id) do
    Transaction
    |> where([t], t.user_id == ^user_id)
    |> select([t], t.operation)
    |> distinct(true)
    |> Repo.all()
    |> Enum.sort()
  end

  @doc """
  Activity data grouped by the appropriate time period.
  - total: grouped by year
  - year: grouped by month
  - month: grouped by day
  Returns list of %{key, aportes, dividends}.
  """
  def period_activity(user_id, view_mode, year, month, opts \\ []) do
    {extra_opts, group_fn} =
      case view_mode do
        "total" ->
          {[], fn t -> t.date.year end}

        "year" ->
          {[date_from: Date.new!(year, 1, 1), date_to: Date.new!(year, 12, 31)],
           fn t -> t.date.month end}

        "month" ->
          date_start = Date.new!(year, month, 1)

          {[date_from: date_start, date_to: Date.end_of_month(date_start)],
           fn t -> t.date.day end}
      end

    txns = list_transactions(user_id, opts ++ extra_opts)

    txns
    |> Enum.group_by(group_fn)
    |> Enum.map(fn {key, group_txns} ->
      aportes =
        group_txns
        |> Enum.filter(&(&1.operation == "compra"))
        |> Enum.reduce(Decimal.new(0), fn t, acc ->
          Decimal.add(acc, Decimal.abs(t.total_amount))
        end)

      resgates =
        group_txns
        |> Enum.filter(&(&1.operation == "venda"))
        |> Enum.reduce(Decimal.new(0), fn t, acc ->
          Decimal.add(acc, Decimal.abs(t.total_amount))
        end)

      dividends =
        group_txns
        |> Enum.filter(&(&1.operation in Constants.dividend_ops()))
        |> Enum.reduce(Decimal.new(0), fn t, acc ->
          Decimal.add(acc, Decimal.abs(t.total_amount))
        end)

      # Lucro realizado = vendas - compras (pode ser negativo = prejuízo)
      realized_profit = Decimal.sub(resgates, aportes)
      proventos = Decimal.add(dividends, Decimal.max(realized_profit, Decimal.new(0)))

      %{
        key: key,
        aportes: aportes,
        resgates: resgates,
        proventos: proventos,
        realized_profit: realized_profit
      }
    end)
    |> Enum.sort_by(& &1.key)
  end

  @doc """
  Portfolio with live market data from brapi.dev.
  Enriches holdings with current price, current value, and gain/loss.
  Falls back to cost-base only if API is unavailable.
  """
  def portfolio_with_market_data(user_id, opts \\ []) do
    summary = portfolio_summary(user_id, opts)

    active =
      summary.holdings
      |> Enum.filter(& &1.is_active)

    all_tickers = Enum.map(active, & &1.ticker)

    tickers =
      all_tickers
      |> Enum.filter(&(&1 && String.match?(&1, ~r/^[A-Z]{4}\d{1,2}$/i)))

    skipped = all_tickers -- tickers

    if skipped != [] do
      require Logger
      Logger.info("QuoteProvider: skipped tickers (no match): #{inspect(skipped)}")
    end

    quotes =
      case Grana.Investments.QuoteProvider.get_quotes(tickers,
             fetch_remote: Keyword.get(opts, :allow_fetch, true)
           ) do
        {:ok, q} -> q
        _ -> %{}
      end

    enriched_holdings =
      Enum.map(summary.holdings, fn h ->
        ticker_up = if h.ticker, do: String.upcase(h.ticker)
        quote = if ticker_up, do: Map.get(quotes, ticker_up)

        if quote && h.is_active do
          current_value = Decimal.mult(h.net_qty, quote.price)
          gain_loss = Decimal.sub(current_value, h.cost_basis)

          gain_loss_pct =
            if Decimal.compare(h.cost_basis, 0) != :eq,
              do:
                h.cost_basis
                |> then(&Decimal.div(gain_loss, &1))
                |> Decimal.mult(100)
                |> Decimal.round(2),
              else: nil

          Map.merge(h, %{
            current_price: quote.price,
            current_value: current_value,
            gain_loss: gain_loss,
            gain_loss_pct: gain_loss_pct,
            change_pct: quote.change_pct,
            logo_url: quote.logo_url
          })
        else
          current_value = if h.is_active, do: h.cost_basis, else: Decimal.new(0)

          Map.merge(h, %{
            current_price: nil,
            current_value: current_value,
            gain_loss: Decimal.new(0),
            gain_loss_pct: nil,
            change_pct: nil,
            logo_url: nil
          })
        end
      end)

    market_value =
      enriched_holdings
      |> Enum.filter(& &1.is_active)
      |> Enum.reduce(Decimal.new(0), fn h, acc -> Decimal.add(acc, h.current_value) end)

    total_gain_loss = Decimal.sub(market_value, summary.cost_basis_total)

    total_gain_loss_pct =
      if Decimal.compare(summary.cost_basis_total, 0) != :eq,
        do:
          summary.cost_basis_total
          |> then(&Decimal.div(total_gain_loss, &1))
          |> Decimal.mult(100)
          |> Decimal.round(2),
        else: nil

    has_quotes = map_size(quotes) > 0

    # Recalculate by_asset_type using current_value (market prices when available)
    by_asset_type =
      enriched_holdings
      |> Enum.filter(& &1.is_active)
      |> Enum.group_by(& &1.type)
      |> Enum.map(fn {type, items} ->
        total =
          Enum.reduce(items, Decimal.new(0), fn h, acc -> Decimal.add(acc, h.current_value) end)

        %{asset_type: type, total: total, count: length(items)}
      end)
      |> Enum.sort_by(fn %{total: t} -> Decimal.to_float(t) end, :desc)

    Map.merge(summary, %{
      holdings: enriched_holdings,
      market_value: market_value,
      total_gain_loss: total_gain_loss,
      total_gain_loss_pct: total_gain_loss_pct,
      has_quotes: has_quotes,
      by_asset_type: by_asset_type,
      by_asset_individual:
        enriched_holdings
        |> Enum.filter(fn h -> h.is_active and Decimal.compare(h.current_value, 0) == :gt end)
        |> Enum.sort_by(fn h -> Decimal.to_float(h.current_value) end, :desc)
    })
  end

  @doc """
  Portfolio summary - accumulated totals up to a given date (or all time).
  Uses SQL aggregation for performance instead of loading all transactions.
  """
  def portfolio_summary(user_id, opts \\ []) do
    base = build_transactions_query(user_id, opts) |> exclude(:preload) |> exclude(:order_by)

    # 1. Global totals (single SQL query)
    totals =
      base
      |> select([t], %{
        total_bought:
          coalesce(
            sum(
              fragment(
                "CASE WHEN ? = 'compra' THEN ABS(?) ELSE 0 END",
                t.operation,
                t.total_amount
              )
            ),
            0
          ),
        total_sold:
          coalesce(
            sum(
              fragment(
                "CASE WHEN ? = 'venda' THEN ABS(?) ELSE 0 END",
                t.operation,
                t.total_amount
              )
            ),
            0
          ),
        dividends:
          coalesce(
            sum(
              fragment(
                "CASE WHEN ? IN ('dividendo', 'jcp', 'rendimento', 'amortizacao') THEN ABS(?) ELSE 0 END",
                t.operation,
                t.total_amount
              )
            ),
            0
          ),
        total_fees: coalesce(sum(t.fees), 0),
        transaction_count: count(t.id)
      })
      |> Repo.one()

    # 2. Holdings grouped by normalized ticker/name (SQL)
    holdings_raw =
      base
      |> where([t], t.operation in ^Constants.buy_sell_ops())
      |> group_by(
        [t],
        fragment("COALESCE(UPPER(TRIM(?)), TRIM(?))", t.asset_ticker, t.asset_name)
      )
      |> select([t], %{
        ticker: fragment("COALESCE(UPPER(TRIM(?)), TRIM(?))", t.asset_ticker, t.asset_name),
        name: min(t.asset_name),
        type: min(t.asset_type),
        institution_id: min(t.institution_id),
        bought_qty:
          coalesce(
            sum(fragment("CASE WHEN ? = 'compra' THEN ? ELSE 0 END", t.operation, t.quantity)),
            0
          ),
        sold_qty:
          coalesce(
            sum(fragment("CASE WHEN ? = 'venda' THEN ? ELSE 0 END", t.operation, t.quantity)),
            0
          ),
        bought_total:
          coalesce(
            sum(
              fragment(
                "CASE WHEN ? = 'compra' THEN ABS(?) ELSE 0 END",
                t.operation,
                t.total_amount
              )
            ),
            0
          ),
        sold_total:
          coalesce(
            sum(
              fragment(
                "CASE WHEN ? = 'venda' THEN ABS(?) ELSE 0 END",
                t.operation,
                t.total_amount
              )
            ),
            0
          )
      })
      |> Repo.all()

    # Load all institutions referenced by any transaction in scope
    inst_ids =
      base
      |> select([t], t.institution_id)
      |> distinct(true)
      |> Repo.all()
      |> Enum.reject(&is_nil/1)

    institutions_map =
      if inst_ids != [] do
        Institution |> where([i], i.id in ^inst_ids) |> Repo.all() |> Map.new(&{&1.id, &1})
      else
        %{}
      end

    holdings =
      holdings_raw
      |> Enum.map(fn h ->
        net_qty = Decimal.sub(h.bought_qty, h.sold_qty)
        net_total = Decimal.sub(h.bought_total, h.sold_total)
        inst = Map.get(institutions_map, h.institution_id)
        inst_logo = if inst, do: Institution.logo_url(inst)

        # Cost basis of the REMAINING position. For quantity-based assets this is
        # average purchase price × remaining quantity — NOT bought_total − sold_total,
        # which wrongly nets sale proceeds (revenue) against purchase cost and
        # distorts gain/loss on partial sales. Quantity-less assets (e.g. fixed
        # income) keep net_total.
        cost_basis = remaining_cost_basis(h.bought_qty, h.bought_total, net_qty, net_total)

        is_active =
          Decimal.compare(net_qty, 0) == :gt or
            (Decimal.compare(h.bought_qty, 0) == :eq and
               Decimal.compare(h.sold_qty, 0) == :eq and
               Decimal.compare(net_total, 0) == :gt)

        %{
          ticker: h.ticker,
          name: h.name,
          type: h.type,
          institution_logo: inst_logo,
          bought_qty: h.bought_qty,
          sold_qty: h.sold_qty,
          net_qty: net_qty,
          bought_total: h.bought_total,
          sold_total: h.sold_total,
          net_total: net_total,
          cost_basis: cost_basis,
          is_active: is_active
        }
      end)
      |> Enum.sort_by(fn %{net_total: t} -> Decimal.to_float(t) end, :desc)

    # Net position only from active holdings
    net_position =
      holdings
      |> Enum.filter(& &1.is_active)
      |> Enum.reduce(Decimal.new(0), fn h, acc -> Decimal.add(acc, h.net_total) end)

    # Cost basis of held positions (avg cost × remaining qty). This is the correct
    # denominator for gain/loss against market value.
    cost_basis_total =
      holdings
      |> Enum.filter(& &1.is_active)
      |> Enum.reduce(Decimal.new(0), fn h, acc -> Decimal.add(acc, h.cost_basis) end)

    # By asset type
    by_asset_type =
      holdings
      |> Enum.filter(& &1.is_active)
      |> Enum.group_by(& &1.type)
      |> Enum.map(fn {type, items} ->
        total = Enum.reduce(items, Decimal.new(0), fn h, acc -> Decimal.add(acc, h.net_total) end)
        %{asset_type: type, total: total, count: length(items)}
      end)
      |> Enum.sort_by(fn %{total: t} -> Decimal.to_float(t) end, :desc)

    # 3. By institution (SQL)
    by_institution_raw =
      base
      |> where([t], t.operation == "compra")
      |> group_by([t], t.institution_id)
      |> select([t], %{
        institution_id: t.institution_id,
        total: coalesce(sum(fragment("ABS(?)", t.total_amount)), 0),
        count: count(t.id)
      })
      |> Repo.all()

    by_institution =
      by_institution_raw
      |> Enum.map(fn row ->
        inst = Map.get(institutions_map, row.institution_id)
        %{institution: inst, total: row.total, count: row.count}
      end)
      |> Enum.sort_by(fn %{total: t} -> Decimal.to_float(t) end, :desc)

    # 4. Dividends by asset (SQL)
    dividend_by_asset_raw =
      base
      |> where([t], t.operation in ^Constants.dividend_ops())
      |> group_by(
        [t],
        fragment("COALESCE(UPPER(TRIM(?)), TRIM(?))", t.asset_ticker, t.asset_name)
      )
      |> select([t], %{
        ticker: fragment("COALESCE(UPPER(TRIM(?)), TRIM(?))", t.asset_ticker, t.asset_name),
        name: min(t.asset_name),
        type: min(t.asset_type),
        institution_id: min(t.institution_id),
        total: coalesce(sum(fragment("ABS(?)", t.total_amount)), 0),
        count: count(t.id)
      })
      |> Repo.all()

    dividend_by_asset =
      dividend_by_asset_raw
      |> Enum.map(fn d ->
        inst = Map.get(institutions_map, d.institution_id)
        inst_logo = if inst, do: Institution.logo_url(inst)

        %{
          ticker: d.ticker,
          name: d.name,
          type: d.type,
          institution_logo: inst_logo,
          total: d.total,
          count: d.count
        }
      end)
      |> Enum.sort_by(fn %{total: t} -> Decimal.to_float(t) end, :desc)

    # 5. Proventos by asset (SQL): dividends + max(vendas - compras, 0)
    proventos_by_asset_raw =
      base
      |> where([t], t.operation in ^Constants.proventos_ops())
      |> group_by(
        [t],
        fragment("COALESCE(UPPER(TRIM(?)), TRIM(?))", t.asset_ticker, t.asset_name)
      )
      |> select([t], %{
        ticker: fragment("COALESCE(UPPER(TRIM(?)), TRIM(?))", t.asset_ticker, t.asset_name),
        name: min(t.asset_name),
        type: min(t.asset_type),
        institution_id: min(t.institution_id),
        sold:
          coalesce(
            sum(
              fragment(
                "CASE WHEN ? = 'venda' THEN ABS(?) ELSE 0 END",
                t.operation,
                t.total_amount
              )
            ),
            0
          ),
        bought:
          coalesce(
            sum(
              fragment(
                "CASE WHEN ? = 'compra' THEN ABS(?) ELSE 0 END",
                t.operation,
                t.total_amount
              )
            ),
            0
          ),
        divs:
          coalesce(
            sum(
              fragment(
                "CASE WHEN ? IN ('dividendo', 'jcp', 'rendimento', 'amortizacao') THEN ABS(?) ELSE 0 END",
                t.operation,
                t.total_amount
              )
            ),
            0
          ),
        count: count(t.id)
      })
      |> Repo.all()

    # Lucro realizado por ativo via preço médio (método BR), em vez de
    # vendas-compras agregado, que distorce o resultado em compras/vendas múltiplas.
    realized_map = realized_profit_by_ticker(base)

    proventos_by_asset =
      proventos_by_asset_raw
      |> Enum.map(fn p ->
        realized_profit = Map.get(realized_map, p.ticker, Decimal.new(0))
        total = Decimal.add(Decimal.max(realized_profit, Decimal.new(0)), p.divs)
        inst = Map.get(institutions_map, p.institution_id)
        inst_logo = if inst, do: Institution.logo_url(inst)

        %{
          ticker: p.ticker,
          name: p.name,
          type: p.type,
          institution_logo: inst_logo,
          total: total,
          realized_profit: realized_profit,
          dividends: p.divs,
          count: p.count
        }
      end)
      |> Enum.filter(fn %{total: t} -> Decimal.compare(t, 0) == :gt end)
      |> Enum.sort_by(fn %{total: t} -> Decimal.to_float(t) end, :desc)

    proventos =
      proventos_by_asset
      |> Enum.reduce(Decimal.new(0), fn %{total: t}, acc -> Decimal.add(acc, t) end)

    # Assets that have dividends but no buy/sell holdings
    holding_keys = holdings |> Enum.map(& &1.ticker) |> MapSet.new()

    dividend_only_assets =
      dividend_by_asset
      |> Enum.reject(fn d -> MapSet.member?(holding_keys, d.ticker) end)

    %{
      total_bought: totals.total_bought,
      total_sold: totals.total_sold,
      dividends: totals.dividends,
      total_fees: totals.total_fees,
      net_position: net_position,
      cost_basis_total: cost_basis_total,
      proventos: proventos,
      holdings: holdings,
      by_asset_type: by_asset_type,
      by_institution: by_institution,
      dividend_by_asset: dividend_by_asset,
      proventos_by_asset: proventos_by_asset,
      dividend_only_assets: dividend_only_assets,
      transaction_count: totals.transaction_count
    }
  end

  # Lucro realizado por ticker, calculado por preço médio (custo médio ponderado).
  # Processa compras/vendas em ordem cronológica; em cada venda realiza
  # (preço de venda − custo médio) × qtd vendida. Ativos sem quantidade
  # (renda fixa) caem no método de fluxo (vendas − compras).
  defp realized_profit_by_ticker(base) do
    base
    |> exclude(:preload)
    |> exclude(:order_by)
    |> where([t], t.operation in ["compra", "venda"])
    |> order_by([t], asc: t.date, asc: t.id)
    |> select([t], %{
      ticker: fragment("COALESCE(UPPER(TRIM(?)), TRIM(?))", t.asset_ticker, t.asset_name),
      operation: t.operation,
      quantity: t.quantity,
      total: fragment("ABS(?)", t.total_amount)
    })
    |> Repo.all()
    |> Enum.group_by(& &1.ticker)
    |> Map.new(fn {ticker, txns} -> {ticker, realized_for_asset(txns)} end)
  end

  defp realized_for_asset(txns) do
    zero = Decimal.new(0)
    has_qty = Enum.any?(txns, fn t -> Decimal.compare(t.quantity, 0) == :gt end)

    if has_qty do
      {realized, _qty, _cost} =
        Enum.reduce(txns, {zero, zero, zero}, fn t, {realized, qty, cost} ->
          case t.operation do
            "compra" ->
              {realized, Decimal.add(qty, t.quantity), Decimal.add(cost, t.total)}

            "venda" ->
              if Decimal.compare(qty, 0) == :gt do
                avg = Decimal.div(cost, qty)
                sell_qty = Decimal.min(t.quantity, qty)

                unit_price =
                  if Decimal.compare(t.quantity, 0) == :gt,
                    do: Decimal.div(t.total, t.quantity),
                    else: zero

                proceeds = Decimal.mult(unit_price, sell_qty)
                cost_of_sold = Decimal.mult(avg, sell_qty)

                {Decimal.add(realized, Decimal.sub(proceeds, cost_of_sold)),
                 Decimal.sub(qty, sell_qty), Decimal.sub(cost, cost_of_sold)}
              else
                {realized, qty, cost}
              end

            _ ->
              {realized, qty, cost}
          end
        end)

      realized
    else
      sold = sum_op(txns, "venda")
      bought = sum_op(txns, "compra")
      Decimal.sub(sold, bought)
    end
  end

  defp sum_op(txns, op) do
    txns
    |> Enum.filter(&(&1.operation == op))
    |> Enum.reduce(Decimal.new(0), fn t, acc -> Decimal.add(acc, t.total) end)
  end

  # Average-cost basis of the remaining quantity. Falls back to net cash flow for
  # quantity-less assets (bought_qty == 0), and to 0 for fully-closed positions.
  defp remaining_cost_basis(bought_qty, bought_total, net_qty, net_total) do
    cond do
      Decimal.compare(bought_qty, 0) != :gt ->
        net_total

      Decimal.compare(net_qty, 0) != :gt ->
        Decimal.new(0)

      true ->
        bought_total
        |> Decimal.div(bought_qty)
        |> Decimal.mult(net_qty)
    end
  end

  @doc """
  Returns active tickers (with net quantity > 0) for a specific user.
  Filters to valid B3 ticker format (e.g. PETR4, HGLG11).
  """
  def all_active_tickers(user_id) do
    Transaction
    |> where([t], t.operation in ["compra", "venda"] and t.user_id == ^user_id)
    |> group_by([t], fragment("UPPER(TRIM(?))", t.asset_ticker))
    |> having(
      [t],
      fragment(
        "COALESCE(SUM(CASE WHEN ? = 'compra' THEN ? ELSE 0 END), 0) - COALESCE(SUM(CASE WHEN ? = 'venda' THEN ? ELSE 0 END), 0) > 0",
        t.operation,
        t.quantity,
        t.operation,
        t.quantity
      )
    )
    |> select([t], fragment("UPPER(TRIM(?))", t.asset_ticker))
    |> Repo.all()
    |> Enum.filter(&(&1 && String.match?(&1, ~r/^[A-Z]{4}\d{1,2}$/i)))
  end

  @doc """
  Returns all distinct active tickers (with net quantity > 0) across ALL users.
  Intended only for global cache warming (e.g. QuoteFetcher cron job).
  Filters to valid B3 ticker format (e.g. PETR4, HGLG11).
  """
  def all_active_tickers_global do
    Transaction
    |> where([t], t.operation in ["compra", "venda"])
    |> group_by([t], fragment("UPPER(TRIM(?))", t.asset_ticker))
    |> having(
      [t],
      fragment(
        "COALESCE(SUM(CASE WHEN ? = 'compra' THEN ? ELSE 0 END), 0) - COALESCE(SUM(CASE WHEN ? = 'venda' THEN ? ELSE 0 END), 0) > 0",
        t.operation,
        t.quantity,
        t.operation,
        t.quantity
      )
    )
    |> select([t], fragment("UPPER(TRIM(?))", t.asset_ticker))
    |> Repo.all()
    |> Enum.filter(&(&1 && String.match?(&1, ~r/^[A-Z]{4}\d{1,2}$/i)))
  end
end
