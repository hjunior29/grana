defmodule Grana.Investments do
  import Ecto.Query
  alias Grana.Repo
  alias Grana.Investments.{Institution, Statement, Transaction}

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

  def delete_statements(ids) when is_list(ids) do
    Statement
    |> where([s], s.id in ^ids)
    |> Repo.delete_all()
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
          sum(fragment("CASE WHEN ? = 'compra' THEN ABS(?) ELSE 0 END", t.operation, t.total_amount)),
          0
        ),
      total_vendas:
        coalesce(
          sum(fragment("CASE WHEN ? = 'venda' THEN ABS(?) ELSE 0 END", t.operation, t.total_amount)),
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
          sum(fragment("CASE WHEN ? = 'taxa' THEN ABS(?) ELSE 0 END", t.operation, t.total_amount)),
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
    query = filter_by_date_range(query, Keyword.get(opts, :date_from), Keyword.get(opts, :date_to))
    query = filter_by_ticker(query, Keyword.get(opts, :ticker))
    query = filter_by_search(query, Keyword.get(opts, :search))
    query = filter_by_amount_min(query, Keyword.get(opts, :amount_min))
    query = filter_by_amount_max(query, Keyword.get(opts, :amount_max))
    filter_by_statement(query, Keyword.get(opts, :statement_id))
  end

  defp filter_by_institution(query, nil), do: query
  defp filter_by_institution(query, "all"), do: query
  defp filter_by_institution(query, id), do: where(query, [t], t.institution_id == ^id)

  defp filter_by_asset_type(query, nil), do: query
  defp filter_by_asset_type(query, "all"), do: query
  defp filter_by_asset_type(query, type), do: where(query, [t], t.asset_type == ^type)

  defp filter_by_operation(query, nil), do: query
  defp filter_by_operation(query, "all"), do: query
  defp filter_by_operation(query, op), do: where(query, [t], t.operation == ^op)

  defp filter_by_date_range(query, nil, nil), do: query
  defp filter_by_date_range(query, from, nil), do: where(query, [t], t.date >= ^from)
  defp filter_by_date_range(query, nil, to), do: where(query, [t], t.date <= ^to)
  defp filter_by_date_range(query, from, to), do: where(query, [t], t.date >= ^from and t.date <= ^to)

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
  defp filter_by_amount_min(query, min), do: where(query, [t], fragment("ABS(?)", t.total_amount) >= ^min)

  defp filter_by_statement(query, nil), do: query
  defp filter_by_statement(query, id), do: where(query, [t], t.statement_id == ^id)

  defp filter_by_amount_max(query, nil), do: query
  defp filter_by_amount_max(query, max), do: where(query, [t], fragment("ABS(?)", t.total_amount) <= ^max)

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
        |> Enum.reduce(Decimal.new(0), fn t, acc -> Decimal.add(acc, Decimal.abs(t.total_amount)) end)

      dividends =
        txns
        |> Enum.filter(&(&1.operation in ~w(dividendo jcp rendimento amortizacao)))
        |> Enum.reduce(Decimal.new(0), fn t, acc -> Decimal.add(acc, Decimal.abs(t.total_amount)) end)

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
        |> Enum.filter(&(&1.operation in ~w(dividendo jcp rendimento amortizacao)))
        |> Enum.reduce(Decimal.new(0), fn t, acc ->
          Decimal.add(acc, Decimal.abs(t.total_amount))
        end)

      nf_compras =
        group_txns
        |> Enum.filter(&(&1.operation == "compra" and &1.asset_type == "nota_fiscal"))
        |> Enum.reduce(Decimal.new(0), fn t, acc ->
          Decimal.add(acc, Decimal.abs(t.total_amount))
        end)

      nf_vendas =
        group_txns
        |> Enum.filter(&(&1.operation == "venda" and &1.asset_type == "nota_fiscal"))
        |> Enum.reduce(Decimal.new(0), fn t, acc ->
          Decimal.add(acc, Decimal.abs(t.total_amount))
        end)

      nf_profit = Decimal.max(Decimal.sub(nf_vendas, nf_compras), Decimal.new(0))
      proventos = Decimal.add(dividends, nf_profit)

      %{key: key, aportes: aportes, resgates: resgates, proventos: proventos}
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

    tickers =
      active
      |> Enum.map(& &1.ticker)
      |> Enum.filter(&(&1 && String.match?(&1, ~r/^[A-Z]{4}\d{1,2}$/i)))

    quotes =
      case Grana.Investments.QuoteProvider.get_quotes(tickers) do
        {:ok, q} -> q
        _ -> %{}
      end

    enriched_holdings =
      Enum.map(summary.holdings, fn h ->
        ticker_up = if h.ticker, do: String.upcase(h.ticker)
        quote = if ticker_up, do: Map.get(quotes, ticker_up)

        if quote && h.is_active do
          current_value = Decimal.mult(h.net_qty, quote.price)
          gain_loss = Decimal.sub(current_value, h.net_total)

          gain_loss_pct =
            if Decimal.compare(h.net_total, 0) == :gt,
              do: h.net_total |> then(&Decimal.div(gain_loss, &1)) |> Decimal.mult(100),
              else: Decimal.new(0)

          Map.merge(h, %{
            current_price: quote.price,
            current_value: current_value,
            gain_loss: gain_loss,
            gain_loss_pct: gain_loss_pct,
            change_pct: quote.change_pct,
            logo_url: quote.logo_url
          })
        else
          current_value = if h.is_active, do: h.net_total, else: Decimal.new(0)

          Map.merge(h, %{
            current_price: nil,
            current_value: current_value,
            gain_loss: Decimal.new(0),
            gain_loss_pct: Decimal.new(0),
            change_pct: nil,
            logo_url: nil
          })
        end
      end)

    market_value =
      enriched_holdings
      |> Enum.filter(& &1.is_active)
      |> Enum.reduce(Decimal.new(0), fn h, acc -> Decimal.add(acc, h.current_value) end)

    total_gain_loss = Decimal.sub(market_value, summary.net_position)

    total_gain_loss_pct =
      if Decimal.compare(summary.net_position, 0) == :gt,
        do: summary.net_position |> then(&Decimal.div(total_gain_loss, &1)) |> Decimal.mult(100),
        else: Decimal.new(0)

    has_quotes = map_size(quotes) > 0

    # Recalculate by_asset_type using current_value (market prices when available)
    by_asset_type =
      enriched_holdings
      |> Enum.filter(& &1.is_active)
      |> Enum.group_by(& &1.type)
      |> Enum.map(fn {type, items} ->
        total = Enum.reduce(items, Decimal.new(0), fn h, acc -> Decimal.add(acc, h.current_value) end)
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
  Shows the real portfolio state: total bought, sold, dividends received.
  """
  def portfolio_summary(user_id, opts \\ []) do
    transactions = list_transactions(user_id, opts)

    total_bought =
      transactions
      |> Enum.filter(&(&1.operation == "compra"))
      |> Enum.reduce(Decimal.new(0), fn t, acc -> Decimal.add(acc, Decimal.abs(t.total_amount)) end)

    total_sold =
      transactions
      |> Enum.filter(&(&1.operation == "venda"))
      |> Enum.reduce(Decimal.new(0), fn t, acc -> Decimal.add(acc, Decimal.abs(t.total_amount)) end)

    dividends =
      transactions
      |> Enum.filter(&(&1.operation in ~w(dividendo jcp rendimento amortizacao)))
      |> Enum.reduce(Decimal.new(0), fn t, acc -> Decimal.add(acc, Decimal.abs(t.total_amount)) end)

    nf_bought =
      transactions
      |> Enum.filter(&(&1.operation == "compra" and &1.asset_type == "nota_fiscal"))
      |> Enum.reduce(Decimal.new(0), fn t, acc -> Decimal.add(acc, Decimal.abs(t.total_amount)) end)

    nf_sold =
      transactions
      |> Enum.filter(&(&1.operation == "venda" and &1.asset_type == "nota_fiscal"))
      |> Enum.reduce(Decimal.new(0), fn t, acc -> Decimal.add(acc, Decimal.abs(t.total_amount)) end)

    nf_profit = Decimal.max(Decimal.sub(nf_sold, nf_bought), Decimal.new(0))

    total_fees =
      transactions
      |> Enum.reduce(Decimal.new(0), fn t, acc -> Decimal.add(acc, t.fees || Decimal.new(0)) end)

    # Holdings: group by asset_ticker, calculate net quantity
    holdings =
      transactions
      |> Enum.filter(&(&1.operation in ~w(compra venda)))
      |> Enum.group_by(&(&1.asset_ticker || &1.asset_name))
      |> Enum.map(fn {ticker, txns} ->
        bought_qty =
          txns
          |> Enum.filter(&(&1.operation == "compra"))
          |> Enum.reduce(Decimal.new(0), fn t, acc -> Decimal.add(acc, t.quantity) end)

        sold_qty =
          txns
          |> Enum.filter(&(&1.operation == "venda"))
          |> Enum.reduce(Decimal.new(0), fn t, acc -> Decimal.add(acc, t.quantity) end)

        bought_total =
          txns
          |> Enum.filter(&(&1.operation == "compra"))
          |> Enum.reduce(Decimal.new(0), fn t, acc -> Decimal.add(acc, Decimal.abs(t.total_amount)) end)

        sold_total =
          txns
          |> Enum.filter(&(&1.operation == "venda"))
          |> Enum.reduce(Decimal.new(0), fn t, acc -> Decimal.add(acc, Decimal.abs(t.total_amount)) end)

        net_qty = Decimal.sub(bought_qty, sold_qty)
        net_total = Decimal.sub(bought_total, sold_total)

        first = List.first(txns)

        # A holding is active if:
        # - net_qty > 0 AND net_total > 0 (shares still held with real value), OR
        # - qty was never tracked (both 0) but there's invested value with no sells (e.g. CDB)
        is_active =
          (Decimal.compare(net_qty, 0) == :gt and Decimal.compare(net_total, 0) == :gt) or
            (Decimal.compare(bought_qty, 0) == :eq and
               Decimal.compare(sold_qty, 0) == :eq and
               Decimal.compare(net_total, 0) == :gt)

        inst_logo = if first.institution, do: Institution.logo_url(first.institution)

        %{
          ticker: ticker,
          name: first.asset_name,
          type: first.asset_type,
          institution_logo: inst_logo,
          bought_qty: bought_qty,
          sold_qty: sold_qty,
          net_qty: net_qty,
          bought_total: bought_total,
          sold_total: sold_total,
          net_total: net_total,
          is_active: is_active
        }
      end)
      |> Enum.sort_by(fn %{net_total: t} -> Decimal.to_float(t) end, :desc)

    # Net position only from active holdings
    net_position =
      holdings
      |> Enum.filter(& &1.is_active)
      |> Enum.reduce(Decimal.new(0), fn h, acc -> Decimal.add(acc, h.net_total) end)

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

    # By institution
    by_institution =
      transactions
      |> Enum.filter(&(&1.operation == "compra"))
      |> Enum.group_by(& &1.institution)
      |> Enum.map(fn {inst, txns} ->
        total = Enum.reduce(txns, Decimal.new(0), fn t, acc -> Decimal.add(acc, Decimal.abs(t.total_amount)) end)
        %{institution: inst, total: total, count: length(txns)}
      end)
      |> Enum.sort_by(fn %{total: t} -> Decimal.to_float(t) end, :desc)

    # Dividends by asset
    dividend_by_asset =
      transactions
      |> Enum.filter(&(&1.operation in ~w(dividendo jcp rendimento amortizacao)))
      |> Enum.group_by(&(&1.asset_ticker || &1.asset_name))
      |> Enum.map(fn {ticker, txns} ->
        total = Enum.reduce(txns, Decimal.new(0), fn t, acc -> Decimal.add(acc, Decimal.abs(t.total_amount)) end)
        first = List.first(txns)
        inst_logo = if first.institution, do: Institution.logo_url(first.institution)
        %{ticker: ticker, name: first.asset_name, type: first.asset_type,
          institution_logo: inst_logo, total: total, count: length(txns)}
      end)
      |> Enum.sort_by(fn %{total: t} -> Decimal.to_float(t) end, :desc)

    # Proventos e Resultados: dividends + lucro líquido de notas fiscais
    proventos = Decimal.add(dividends, nf_profit)

    proventos_by_asset =
      transactions
      |> Enum.filter(&(&1.operation in ~w(compra venda dividendo jcp rendimento amortizacao)))
      |> Enum.group_by(&(&1.asset_ticker || &1.asset_name))
      |> Enum.map(fn {ticker, txns} ->
        first = List.first(txns)

        sold =
          txns
          |> Enum.filter(&(&1.operation == "venda"))
          |> Enum.reduce(Decimal.new(0), fn t, acc -> Decimal.add(acc, Decimal.abs(t.total_amount)) end)

        bought =
          txns
          |> Enum.filter(&(&1.operation == "compra"))
          |> Enum.reduce(Decimal.new(0), fn t, acc -> Decimal.add(acc, Decimal.abs(t.total_amount)) end)

        divs =
          txns
          |> Enum.filter(&(&1.operation in ~w(dividendo jcp rendimento amortizacao)))
          |> Enum.reduce(Decimal.new(0), fn t, acc -> Decimal.add(acc, Decimal.abs(t.total_amount)) end)

        # Para nota_fiscal: resultado = vendas - compras (lucro); para outros: resultado = vendas
        resultado =
          if first.asset_type == "nota_fiscal",
            do: Decimal.max(Decimal.sub(sold, bought), Decimal.new(0)),
            else: sold

        total = Decimal.add(resultado, divs)
        inst_logo = if first.institution, do: Institution.logo_url(first.institution)

        %{ticker: ticker, name: first.asset_name, type: first.asset_type,
          institution_logo: inst_logo, total: total, count: length(txns)}
      end)
      |> Enum.filter(fn %{total: t} -> Decimal.compare(t, 0) == :gt end)
      |> Enum.sort_by(fn %{total: t} -> Decimal.to_float(t) end, :desc)

    %{
      total_bought: total_bought,
      total_sold: total_sold,
      dividends: dividends,
      total_fees: total_fees,
      net_position: net_position,
      proventos: proventos,
      holdings: holdings,
      by_asset_type: by_asset_type,
      by_institution: by_institution,
      dividend_by_asset: dividend_by_asset,
      proventos_by_asset: proventos_by_asset,
      transaction_count: length(transactions)
    }
  end


end
