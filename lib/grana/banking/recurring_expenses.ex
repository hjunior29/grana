defmodule Grana.Banking.RecurringExpenses do
  @moduledoc """
  Classificação de despesas fixas (recorrentes) vs variáveis a partir de uma
  lista de transações de despesa.

  A ideia: uma despesa fixa é uma cobrança que se repete na **maioria dos
  meses**, ~1 vez por mês (assinatura, aluguel, internet, seguro, academia),
  tolerando pequenas variações de nome, de valor e do dia do débito. Tudo o que
  não recorre assim é tratado como despesa variável.

  Como funciona:

    1. **Normaliza** a descrição num "nome de comerciante" canônico (minúsculas,
       sem acento, sem pontuação/números, pegando a contraparte após " - ").
    2. **Agrupa** por nome exato e depois funde grupos com nomes parecidos via
       `String.jaro_distance/2` (tolera "NETFLIX.COM" ↔ "NETFLIX *BR"), exigindo
       ao menos um token significativo em comum (evita falsos positivos).
    3. **Classifica** um grupo como fixo quando aparece na maioria dos meses da
       janela e ~1x/mês (cobrança discreta, não consumo de alta frequência como
       iFood/Uber, que cai em variável).

  `analyze/2` é uma função pura: recebe a lista de despesas já filtrada (débitos,
  sem transferências internas, sem investimentos, sem parcelas) e devolve a
  análise sobre os meses presentes nessa lista. Regras de recorrência do usuário
  entram por cima da inferência, mas o resultado é sempre o estado efetivo:
  fixa ou variável.
  """

  @jaro_threshold 0.85
  @min_coverage 0.5
  @max_per_month 1.5

  @doc """
  Analisa as despesas e devolve um mapa com:

    * `:months`            — `[{ano, mês}]` ordenados (janela efetiva)
    * `:total_months`      — quantidade de meses na janela
    * `:fixed`             — lista de despesas fixas (ver `fixed_item/0`)
    * `:monthly`           — `[%{ym, fixed, variable}]` por mês (para o gráfico)
    * `:avg_fixed`         — média mensal das despesas fixas (Decimal)
    * `:avg_variable`      — média mensal das despesas variáveis (Decimal)
    * `:total_fixed`/`:total_variable` — somas na janela (Decimal)

  Cada item de `:fixed` é um mapa:
  `%{name, category, months_present, occurrences, avg_amount, last_amount, last_date,
     typical_day, pattern, patterns}`.
  """
  def analyze(transactions, opts \\ []) do
    rules = Keyword.get(opts, :rules, %{})
    bank_filter = Keyword.get(opts, :bank)
    source_filter = Keyword.get(opts, :source)

    # Classificação no conjunto INTEIRO (meses e fixo/variável globais).
    expenses = Enum.map(transactions, &normalize_txn/1)
    months = expenses |> Enum.map(& &1.ym) |> Enum.uniq() |> Enum.sort()
    total_months = length(months)

    classified =
      expenses
      |> cluster()
      |> Enum.map(fn c ->
        rule = rule_for_cluster(c, rules)
        {c, fixed_with_rule(fixed?(c, total_months), rule)}
      end)

    fixed_ids =
      classified
      |> Enum.filter(fn {_c, fixed?} -> fixed? end)
      |> Enum.flat_map(fn {c, _} -> c.ids end)
      |> MapSet.new()

    # Filtro de exibição (banco/fonte): só PARTICIONA o que já foi classificado.
    visible_ids =
      expenses
      |> Enum.filter(&visible?(&1, bank_filter, source_filter))
      |> MapSet.new(& &1.id)

    fixed =
      classified
      |> Enum.filter(fn {_c, fixed?} -> fixed? end)
      |> build_items("fixed", visible_ids, total_months)

    variable_candidates =
      classified
      |> Enum.reject(fn {_c, fixed?} -> fixed? end)
      |> Enum.filter(fn {c, _} -> c.months_present >= 2 end)
      |> build_items("variable", visible_ids, total_months)
      |> Enum.take(15)

    monthly =
      expenses
      |> Enum.filter(&MapSet.member?(visible_ids, &1.id))
      |> monthly_breakdown(fixed_ids, months)

    %{
      months: months,
      total_months: total_months,
      fixed: fixed,
      variable_candidates: variable_candidates,
      monthly: monthly,
      avg_fixed: average(Enum.map(monthly, & &1.fixed), total_months),
      avg_variable: average(Enum.map(monthly, & &1.variable), total_months),
      total_fixed: sum(Enum.map(monthly, & &1.fixed)),
      total_variable: sum(Enum.map(monthly, & &1.variable))
    }
  end

  # Casa banco/fonte selecionados ("all"/nil = não filtra).
  defp visible?(expense, bank_filter, source_filter) do
    (bank_filter in [nil, "all"] or expense.bank == bank_filter) and
      (source_filter in [nil, "all"] or expense.source == source_filter)
  end

  # Monta os itens da lista usando só as transações visíveis (do banco/fonte
  # filtrado) de cada cluster; clusters sem transação visível somem da lista.
  defp build_items(clusters, status, visible_ids, total_months) do
    clusters
    |> Enum.map(fn {c, _fixed?} ->
      {c, Enum.filter(c.txns, &MapSet.member?(visible_ids, &1.id))}
    end)
    |> Enum.reject(fn {_c, vtxns} -> vtxns == [] end)
    |> Enum.map(fn {c, vtxns} -> item(c, status, vtxns, total_months) end)
    |> sort_items()
  end

  defp rule_for_cluster(cluster, rules) do
    Enum.find_value(cluster.patterns, &Map.get(rules, &1))
  end

  defp fixed_with_rule(_inferred, "fixed"), do: true
  defp fixed_with_rule(_inferred, "variable"), do: false
  defp fixed_with_rule(inferred, _none), do: inferred

  # ---- Normalização da transação ----------------------------------------

  defp normalize_txn(t) do
    stmt = Map.get(t, :bank_statement)

    %{
      id: Map.get(t, :id),
      ym: {t.date.year, t.date.month},
      day: t.date.day,
      amount: Decimal.abs(t.amount),
      category: Map.get(t, :category),
      bank: stmt_field(stmt, :bank),
      source: stmt_field(stmt, :statement_type),
      raw: merchant(t.description),
      norm: normalize(t.description)
    }
  end

  defp stmt_field(stmt, key) when is_map(stmt), do: Map.get(stmt, key)
  defp stmt_field(_stmt, _key), do: nil

  @doc false
  # Nome de comerciante canônico para agrupamento. Público para teste.
  def normalize(description) do
    description
    |> merchant()
    |> String.downcase()
    |> strip_accents()
    |> String.replace(~r/[^a-z0-9 ]/u, " ")
    |> String.split()
    |> Enum.reject(&noise_token?/1)
    |> Enum.join(" ")
    |> String.trim()
  end

  # A contraparte/loja: nos extratos o parser monta "TIPO - CONTRAPARTE"; nas
  # faturas a descrição já é o comerciante.
  defp merchant(description) do
    case String.split(description, " - ") do
      [_ | _] = parts when length(parts) > 1 -> List.last(parts)
      _ -> description
    end
  end

  defp strip_accents(str) do
    str
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[\x{0300}-\x{036f}]/u, "")
  end

  @noise_tokens ~w(ltda me sa eireli epp mei the de da do das dos)
  # Remove sufixos de empresa e números longos (IDs/códigos/boletos), mas
  # preserva números curtos que fazem parte da marca (ex.: "99", "c6").
  defp noise_token?(token) do
    token in @noise_tokens or (Regex.match?(~r/^\d+$/, token) and String.length(token) >= 4)
  end

  # ---- Clusterização ------------------------------------------------------

  defp cluster(expenses) do
    by_norm =
      expenses
      |> Enum.reject(&(&1.norm == ""))
      |> Enum.group_by(& &1.norm)

    # Funde nomes parecidos. Processa os mais frequentes primeiro para que eles
    # virem os representantes dos clusters.
    norms_by_freq =
      by_norm
      |> Enum.sort_by(fn {_norm, txns} -> -length(txns) end)
      |> Enum.map(&elem(&1, 0))

    groups = Enum.reduce(norms_by_freq, [], &assign_to_cluster/2)

    Enum.map(groups, fn {_rep, norms} ->
      txns = Enum.flat_map(norms, &Map.fetch!(by_norm, &1))
      build_cluster(txns)
    end)
  end

  defp assign_to_cluster(norm, clusters) do
    case Enum.find_index(clusters, fn {rep, _} -> similar?(rep, norm) end) do
      nil -> [{norm, [norm]} | clusters]
      idx -> List.update_at(clusters, idx, fn {rep, norms} -> {rep, [norm | norms]} end)
    end
  end

  # Dois nomes são o mesmo comerciante se:
  #   * são idênticos; ou
  #   * são quase iguais (jaro) e compartilham um token significativo — pega
  #     variações de grafia/pontuação ("NETFLIX.COM" ↔ "NETFLIX *BR"); ou
  #   * os tokens de um contêm os do outro / há alta sobreposição — pega palavras
  #     extras como cidade/UF ("NETFLIX.COM" ↔ "NETFLIX.COM SAO PAULO").
  defp similar?(a, b) do
    a == b or jaro_match?(a, b) or token_match?(a, b)
  end

  defp jaro_match?(a, b) do
    String.jaro_distance(a, b) >= @jaro_threshold and shares_token?(a, b)
  end

  defp token_match?(a, b) do
    ta = significant_tokens(a)
    tb = significant_tokens(b)

    cond do
      MapSet.size(ta) == 0 or MapSet.size(tb) == 0 -> false
      MapSet.subset?(ta, tb) or MapSet.subset?(tb, ta) -> true
      true -> jaccard(ta, tb) >= 0.5
    end
  end

  defp jaccard(a, b) do
    inter = MapSet.size(MapSet.intersection(a, b))
    union = MapSet.size(MapSet.union(a, b))
    if union == 0, do: 0.0, else: inter / union
  end

  defp shares_token?(a, b) do
    not MapSet.disjoint?(significant_tokens(a), significant_tokens(b))
  end

  defp significant_tokens(str) do
    str |> String.split() |> Enum.filter(&(String.length(&1) >= 3)) |> MapSet.new()
  end

  defp build_cluster(txns) do
    months = txns |> Enum.map(& &1.ym) |> Enum.uniq()

    %{
      ids: Enum.map(txns, & &1.id),
      txns: txns,
      pattern: representative_norm(txns),
      patterns: representative_patterns(txns),
      months_present: length(months),
      occurrences: length(txns)
    }
  end

  # Norma mais frequente do cluster — vira o `pattern` principal da regra.
  defp representative_norm(txns) do
    txns
    |> Enum.frequencies_by(& &1.norm)
    |> Enum.max_by(&elem(&1, 1))
    |> elem(0)
  end

  defp representative_patterns(txns) do
    pattern = representative_norm(txns)

    txns
    |> Enum.map(& &1.norm)
    |> Enum.uniq()
    |> then(&Enum.uniq([pattern | &1]))
  end

  # ---- Classificação fixo/variável ---------------------------------------

  defp fixed?(cluster, total_months) do
    total_months >= 2 and
      cluster.months_present >= max(2, ceil(@min_coverage * total_months)) and
      cluster.occurrences / cluster.months_present <= @max_per_month
  end

  # ---- Item (despesa fixa ou candidata) ----------------------------------

  # `txns` é o subconjunto visível (banco/fonte filtrado) do cluster; valores e
  # contagens refletem só esse subconjunto. `status` é a classificação global.
  defp item(cluster, status, txns, total_months) do
    amounts = Enum.map(txns, & &1.amount)
    latest = Enum.max_by(txns, &Date.from_erl!({elem(&1.ym, 0), elem(&1.ym, 1), &1.day}), Date)
    months_present = txns |> Enum.map(& &1.ym) |> Enum.uniq() |> length()

    %{
      name: display_name(txns),
      pattern: cluster.pattern,
      patterns: cluster.patterns,
      status: status,
      category: most_common_category(txns),
      months_present: months_present,
      total_months: total_months,
      occurrences: length(txns),
      avg_amount: average(amounts, length(amounts)),
      last_amount: latest.amount,
      last_date: Date.new!(elem(latest.ym, 0), elem(latest.ym, 1), latest.day),
      typical_day: median_int(Enum.map(txns, & &1.day))
    }
  end

  @doc """
  The fixed expenses (`:fixed` of `analyze/2`) still to be charged in the month of `today`:
  charged last month but not yet in this one, by typical day.
  """
  def pending(fixed, today) do
    month_start = Date.beginning_of_month(today)
    previous_start = Date.shift(month_start, month: -1)

    fixed
    |> Enum.filter(fn item ->
      Date.before?(item.last_date, month_start) and
        not Date.before?(item.last_date, previous_start)
    end)
    |> Enum.sort_by(&(&1.typical_day || 32))
  end

  defp display_name(txns) do
    txns
    |> Enum.frequencies_by(& &1.raw)
    |> Enum.max_by(&elem(&1, 1))
    |> elem(0)
    |> String.trim()
  end

  defp most_common_category(txns) do
    txns
    |> Enum.map(& &1.category)
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
    |> case do
      map when map_size(map) == 0 -> nil
      map -> map |> Enum.max_by(&elem(&1, 1)) |> elem(0)
    end
  end

  # ---- Quebra mensal fixo/variável ---------------------------------------

  defp monthly_breakdown(expenses, fixed_ids, months) do
    by_month = Enum.group_by(expenses, & &1.ym)

    Enum.map(months, fn ym ->
      txns = Map.get(by_month, ym, [])
      {fixed_txns, var_txns} = Enum.split_with(txns, &MapSet.member?(fixed_ids, &1.id))

      %{
        ym: ym,
        fixed: sum(Enum.map(fixed_txns, & &1.amount)),
        variable: sum(Enum.map(var_txns, & &1.amount))
      }
    end)
  end

  defp sort_items(items) do
    Enum.sort_by(items, &Decimal.to_float(&1.avg_amount), :desc)
  end

  # ---- Helpers numéricos --------------------------------------------------

  defp sum(decimals), do: Enum.reduce(decimals, Decimal.new(0), &Decimal.add/2)

  defp average(_decimals, 0), do: Decimal.new(0)

  defp average(decimals, n) do
    decimals |> sum() |> Decimal.div(n) |> Decimal.round(2)
  end

  defp median_int([]), do: nil

  defp median_int(values) do
    sorted = Enum.sort(values)
    Enum.at(sorted, div(length(sorted), 2))
  end
end
