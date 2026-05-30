defmodule Grana.Banking.AIAnalyzer do
  alias Grana.Accounts
  alias Grana.Banking
  alias Grana.Investments
  alias Grana.Investments.Constants
  alias Grana.AI.Provider
  alias Grana.AI.PromptSanitizer

  # ── Banking Analysis ──

  def analyze_with_filters(user_id, filters, custom_prompt \\ nil) do
    case Accounts.get_user_ai_config(user_id) do
      {:error, :no_api_key} -> {:error, :no_api_key}
      {:ok, config} -> do_analyze_filtered(user_id, filters, custom_prompt, config)
    end
  end

  defp do_analyze_filtered(user_id, filters, custom_prompt, config) do
    month = filters[:month] || filters["month"]
    year = filters[:year] || filters["year"]
    bank = filters[:bank] || filters["bank"]
    type = filters[:type] || filters["type"]
    statement_type = filters[:statement_type] || filters["statement_type"]

    opts =
      []
      |> maybe_add(:bank, bank)
      |> maybe_add(:type, type)
      |> maybe_add(:statement_type, statement_type)

    summary =
      case month do
        m when m in [nil, 0] -> Banking.yearly_summary(user_id, year, opts)
        m -> Banking.monthly_summary(user_id, year, m, opts)
      end

    case summary.transaction_count do
      0 ->
        {:error, "Nenhuma transação encontrada com os filtros selecionados"}

      _ ->
        period =
          case month do
            m when m in [nil, 0] -> "#{year}"
            m -> "#{Banking.month_name(m)}/#{year}"
          end

        available_years = Banking.available_years(user_id)

        daily =
          case month do
            m when m in [nil, 0] -> []
            m -> Banking.daily_spending(user_id, year, m, opts)
          end

        monthly_ie =
          case month do
            m when m in [nil, 0] ->
              available_years
              |> Enum.flat_map(fn y ->
                Banking.monthly_income_expenses(user_id, y, opts)
                |> Enum.map(&Map.put(&1, :year, y))
              end)

            _ ->
              Banking.monthly_income_expenses(user_id, year, opts)
          end

        yearly_spending =
          case month do
            m when m in [nil, 0] ->
              monthly_ie
              |> Enum.group_by(& &1.year)
              |> Enum.map(fn {yr, items} ->
                %{
                  year: yr,
                  expenses:
                    Enum.reduce(items, Decimal.new(0), fn i, acc ->
                      Decimal.add(acc, i.expenses)
                    end)
                }
              end)
              |> Enum.sort_by(& &1.year)

            _ ->
              []
          end

        installment_opts =
          case month do
            m when m in [nil, 0] -> opts
            m -> opts ++ [year: year, month: m]
          end

        installments = Banking.installment_projection_summary(user_id, installment_opts)

        extra = %{
          daily: daily,
          monthly_ie: monthly_ie,
          yearly_spending: yearly_spending,
          installments: installments,
          available_years: available_years
        }

        filter_desc = build_filter_desc(bank, type, statement_type)
        prompt = build_prompt(summary, period, filter_desc, custom_prompt, extra, year, month)
        call_ai(prompt, config)
    end
  end

  # ── Investment Analysis ──

  def analyze_investments_with_filters(user_id, filters, custom_prompt \\ nil) do
    case Accounts.get_user_ai_config(user_id) do
      {:error, :no_api_key} -> {:error, :no_api_key}
      {:ok, config} -> do_analyze_investments(user_id, filters, custom_prompt, config)
    end
  end

  defp do_analyze_investments(user_id, filters, custom_prompt, config) do
    year = filters[:year] || filters["year"]
    month = filters[:month] || filters["month"]
    institution_id = filters[:institution_id] || filters["institution_id"]
    asset_type = filters[:asset_type] || filters["asset_type"]

    view_mode =
      case month do
        m when m in [nil, 0] -> "year"
        _ -> "month"
      end

    filter_opts =
      []
      |> maybe_add(:institution_id, institution_id)
      |> maybe_add(:asset_type, asset_type)

    # Cumulative opts (same as dashboard load_inv_data)
    cumulative_opts =
      [date_to: Date.new!(year, 12, 31)] ++ filter_opts

    # Period opts
    period_opts =
      case month do
        m when m in [nil, 0] ->
          [date_from: Date.new!(year, 1, 1), date_to: Date.new!(year, 12, 31)] ++ filter_opts

        m ->
          date_start = Date.new!(year, m, 1)
          [date_from: date_start, date_to: Date.end_of_month(date_start)] ++ filter_opts
      end

    # Same data as the dashboard
    cumulative_summary = Investments.portfolio_with_market_data(user_id, cumulative_opts)
    period_summary = Investments.portfolio_summary(user_id, period_opts)
    activity = Investments.period_activity(user_id, view_mode, year, month, filter_opts)

    case period_summary.transaction_count do
      0 ->
        {:error, "Nenhuma transação de investimento encontrada com os filtros selecionados"}

      _ ->
        period =
          case month do
            m when m in [nil, 0] -> "#{year}"
            m -> "#{Banking.month_name(m)}/#{year}"
          end

        extra = %{
          cumulative: cumulative_summary,
          period: period_summary,
          activity: activity
        }

        filter_desc = build_inv_filter_desc(institution_id, asset_type)
        prompt = build_investment_prompt(extra, period, filter_desc, custom_prompt)
        call_ai(prompt, config)
    end
  end

  # ── Helpers ──

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, _key, "all"), do: opts
  defp maybe_add(opts, _key, ""), do: opts
  defp maybe_add(opts, key, val), do: Keyword.put(opts, key, val)

  # ── Banking Prompt ──

  defp build_filter_desc(bank, type, statement_type) do
    parts =
      []
      |> add_desc(bank, fn
        nil -> nil
        "all" -> nil
        b -> "Banco: #{String.capitalize(b)}"
      end)
      |> add_desc(statement_type, fn
        nil -> nil
        "all" -> nil
        "extrato" -> "Fonte: Extrato bancário"
        "fatura" -> "Fonte: Fatura de cartão"
        _ -> nil
      end)
      |> add_desc(type, fn
        nil -> nil
        "all" -> nil
        "credit" -> "Tipo: Receitas"
        "debit" -> "Tipo: Despesas"
        _ -> nil
      end)

    case parts do
      [] -> ""
      p -> "FILTROS APLICADOS: #{Enum.join(p, ", ")}\n\n"
    end
  end

  defp add_desc(parts, val, func) do
    case func.(val) do
      nil -> parts
      desc -> parts ++ [desc]
    end
  end

  defp build_prompt(summary, period, filter_desc, custom_prompt, extra, year, month) do
    base = base_prompt_data(summary, extra, year, month)

    custom_prompt_section = PromptSanitizer.wrap_custom_prompt(custom_prompt)
    has_prompt = custom_prompt_section != ""

    """
    Analise os dados financeiros de #{period} de um usuário brasileiro e forneça insights úteis.

    #{filter_desc}#{base}
    #{custom_prompt_section}
    #{json_format_instruction(has_prompt)}
    """
  end

  defp base_prompt_data(summary, extra, year, month) do
    %{
      daily: daily,
      monthly_ie: monthly_ie,
      yearly_spending: yearly_spending,
      installments: installments,
      available_years: available_years
    } = extra

    # ── Cards do resumo ──
    avg_line =
      case month do
        m when m in [nil, 0] ->
          avg = yearly_avg(summary, available_years)
          "- Média Anual de Despesas: R$ #{fmt(avg)}"

        m ->
          daily_avg = daily_avg(summary, year, m)

          "- Média Diária de Despesas: R$ #{fmt(daily_avg)} || Média Mensal de Despesas: R$ #{fmt(summary.total_expenses)}"
      end

    # ── Despesas por categoria ──
    categories_text =
      summary.by_category
      |> Enum.map(fn item ->
        name = if item.category, do: item.category.name, else: "Sem Categoria"
        "- #{name}: R$ #{fmt(item.total)} (#{item.count} transações)"
      end)
      |> Enum.join("\n")

    # ── Gastos diários (visão mês) ──
    daily_section =
      case daily do
        [] ->
          ""

        _ ->
          text =
            daily
            |> Enum.sort_by(& &1.date, Date)
            |> Enum.map(fn d ->
              "- #{Calendar.strftime(d.date, "%d/%m")}: R$ #{fmt(d.total)}"
            end)
            |> Enum.join("\n")

          "\nGASTOS DIÁRIOS:\n#{text}\n"
      end

    # ── Gastos por ano (visão total) ──
    yearly_section =
      case yearly_spending do
        [] ->
          ""

        _ ->
          text =
            yearly_spending
            |> Enum.map(fn item -> "- #{item.year}: R$ #{fmt(item.expenses)}" end)
            |> Enum.join("\n")

          "\nGASTOS POR ANO:\n#{text}\n"
      end

    # ── Receitas vs Despesas mensal ──
    ie_section =
      case monthly_ie do
        [] ->
          ""

        _ ->
          text =
            monthly_ie
            |> Enum.map(fn item ->
              label =
                case Map.get(item, :year) do
                  nil -> Banking.month_name_short(item.month)
                  y -> "#{Banking.month_name_short(item.month)}/#{y}"
                end

              inv = Map.get(item, :investments, Decimal.new(0))

              "- #{label}: Receita R$ #{fmt(item.income)} | Despesa R$ #{fmt(item.expenses)} | Invest. R$ #{fmt(inv)}"
            end)
            |> Enum.join("\n")

          "\nRECEITAS VS DESPESAS (mensal):\n#{text}\n"
      end

    # ── Top despesas ──
    top_expenses =
      summary.transactions
      |> Enum.filter(&(&1.type == "debit"))
      |> Enum.sort_by(fn t -> Decimal.to_float(Decimal.abs(t.amount)) end, :desc)
      |> Enum.take(15)
      |> Enum.map(fn t ->
        cat = if t.category, do: t.category.name, else: "Sem Categoria"
        desc = PromptSanitizer.sanitize_description(t.description)
        "- #{desc}: R$ #{fmt(Decimal.abs(t.amount))} (#{cat})"
      end)
      |> Enum.join("\n")

    # ── Top receitas ──
    top_income =
      summary.transactions
      |> Enum.filter(&(&1.type == "credit"))
      |> Enum.sort_by(fn t -> Decimal.to_float(t.amount) end, :desc)
      |> Enum.take(10)
      |> Enum.map(fn t ->
        cat = if t.category, do: t.category.name, else: "Sem Categoria"
        desc = PromptSanitizer.sanitize_description(t.description)
        "- #{desc}: R$ #{fmt(t.amount)} (#{cat})"
      end)
      |> Enum.join("\n")

    income_section =
      if top_income != "", do: "\nTOPS RECEITAS:\n#{top_income}\n", else: ""

    # ── Parcelas ativas ──
    installment_section =
      if installments.active_count > 0 do
        items =
          installments.installments
          |> Enum.map(fn txn ->
            cat = if txn.category, do: txn.category.name, else: "Sem Categoria"
            remaining = txn.installment_total - txn.installment_current
            remaining_value = Decimal.mult(Decimal.abs(txn.amount), remaining)

            desc = PromptSanitizer.sanitize_description(txn.description)

            "- #{desc}: R$ #{fmt(Decimal.abs(txn.amount))}/mês (#{txn.installment_current}/#{txn.installment_total}) - Restante: R$ #{fmt(remaining_value)} (#{cat})"
          end)
          |> Enum.join("\n")

        """

        PARCELAS ATIVAS (#{installments.active_count} parcelas):
        - Valor mensal total: R$ #{fmt(installments.this_month_total)}
        - Total restante: R$ #{fmt(installments.total_remaining)}
        #{items}
        """
      else
        ""
      end

    """
    RESUMO:
    - Receitas: R$ #{fmt(summary.total_income)}
    - Despesas: R$ #{fmt(summary.total_expenses)}
    - Investimentos: R$ #{fmt(summary.total_investments)}
    - Saldo Livre: R$ #{fmt(summary.balance)}
    #{avg_line}
    - Total de transações: #{summary.transaction_count}

    DESPESAS POR CATEGORIA:
    #{categories_text}
    #{daily_section}#{yearly_section}#{ie_section}
    TOPS DESPESAS:
    #{top_expenses}
    #{income_section}#{installment_section}
    """
  end

  defp fmt(decimal) do
    str =
      decimal
      |> Decimal.round(2)
      |> Decimal.to_string(:normal)

    {integer, dec} =
      case String.split(str, ".") do
        [int] -> {int, "00"}
        [int, d] -> {int, String.pad_trailing(d, 2, "0")}
      end

    {neg, integer} =
      if String.starts_with?(integer, "-"),
        do: {"-", String.trim_leading(integer, "-")},
        else: {"", integer}

    int_formatted =
      integer
      |> String.reverse()
      |> String.to_charlist()
      |> Enum.chunk_every(3)
      |> Enum.join(".")
      |> String.reverse()

    "#{neg}#{int_formatted},#{dec}"
  end

  defp daily_avg(summary, year, month) do
    days = Date.days_in_month(Date.new!(year, month, 1))
    Decimal.div(summary.total_expenses, days) |> Decimal.round(2)
  end

  defp yearly_avg(summary, available_years) do
    case length(available_years) do
      0 -> Decimal.new(0)
      n -> Decimal.div(summary.total_expenses, n) |> Decimal.round(2)
    end
  end

  defp json_format_instruction(has_user_prompt) do
    resposta_instruction =
      if has_user_prompt do
        "\"resposta\": \"Resposta direta e específica à pergunta/instrução do usuário acima\""
      else
        "\"resposta\": null"
      end

    """
    Responda em português brasileiro com exatamente este formato JSON:
    {
      "nota": <número decimal de 0.0 a 10.0 representando a saúde financeira geral>,
      "titulo": "Título curto e descritivo da análise (máximo 8 palavras)",
      "resumo": "Resumo conciso de 2-3 frases sobre a situação financeira do período",
      "pontos": [
        {"tipo": "positivo", "texto": "Ponto positivo específico com dados reais"},
        {"tipo": "negativo", "texto": "Ponto negativo ou preocupante"},
        {"tipo": "neutro", "texto": "Observação relevante"},
        {"tipo": "dica", "texto": "Sugestão prática de economia"}
      ],
      "alerta": "Alerta importante se houver algo preocupante, ou null se tudo estiver ok",
      #{resposta_instruction}
    }

    REGRAS:
    - Retorne APENAS o JSON, sem texto adicional
    - "pontos": inclua entre 3 e 6 pontos, usando os tipos: positivo, negativo, neutro, dica
    - "nota": baseie-se em: saldo positivo (+), controle de gastos (+), diversificação (-), gastos excessivos (-)
    - Seja direto e específico com números reais dos dados
    - Formate valores monetários no padrão brasileiro (R$ 5.550,09)
    """
  end

  # ── Investment Prompt ──

  defp build_inv_filter_desc(institution_id, asset_type) do
    parts =
      []
      |> then(fn p ->
        case institution_id do
          nil -> p
          "all" -> p
          id -> p ++ ["Instituição: #{id}"]
        end
      end)
      |> then(fn p ->
        case asset_type do
          nil -> p
          "all" -> p
          t -> p ++ ["Tipo: #{inv_asset_type_label(t)}"]
        end
      end)

    case parts do
      [] -> ""
      p -> "FILTROS APLICADOS: #{Enum.join(p, ", ")}\n\n"
    end
  end

  defp build_investment_prompt(extra, period, filter_desc, custom_prompt) do
    %{cumulative: cum, period: per, activity: activity} = extra

    active_count = Enum.count(cum.holdings, & &1.is_active)
    dividends = per.dividends
    realized = Decimal.sub(per.proventos, dividends)

    # ── Cards do resumo (mesmos do dashboard) ──
    summary_text = """
    RESUMO DA CARTEIRA:
    - Patrimônio: R$ #{fmt(cum.market_value)}#{if cum.has_quotes, do: " (preço ao vivo)", else: " (custo-base)"}
    - Total Investido: R$ #{fmt(cum.net_position)} (custo-base)
    - Ativos: #{active_count}#{if cum.by_asset_type != [], do: " (#{Enum.map_join(cum.by_asset_type, ", ", fn t -> "#{t.count} #{inv_asset_type_label(t.asset_type)}" end)})", else: ""}
    - Dividendos no Período: R$ #{fmt(dividends)}
    - Lucro em Vendas no Período: R$ #{fmt(realized)}
    - Rentabilidade: #{fmt(cum.total_gain_loss_pct)}% (R$ #{fmt(cum.total_gain_loss)})
    - Total de Transações no Período: #{per.transaction_count}
    """

    # ── Carteira por ativo (top 10) ──
    individual_section =
      case cum.by_asset_individual do
        [] ->
          ""

        assets ->
          text =
            assets
            |> Enum.take(10)
            |> Enum.map(fn h ->
              pct =
                if Decimal.compare(cum.market_value, 0) == :gt,
                  do:
                    cum.market_value
                    |> then(&Decimal.div(h.current_value, &1))
                    |> Decimal.mult(100)
                    |> Decimal.round(1),
                  else: Decimal.new(0)

              gain =
                if Decimal.compare(h.gain_loss, 0) != :eq,
                  do: " | Rent: #{fmt(h.gain_loss_pct)}%",
                  else: ""

              "- #{h.ticker || h.name} (#{inv_asset_type_label(h.type)}): R$ #{fmt(h.current_value)} (#{fmt(pct)}%)#{gain}"
            end)
            |> Enum.join("\n")

          "\nCARTEIRA POR ATIVO:\n#{text}\n"
      end

    # ── Patrimônio por tipo de ativo ──
    by_type_section =
      case cum.by_asset_type do
        [] ->
          ""

        types ->
          text =
            types
            |> Enum.map(fn item ->
              pct =
                if Decimal.compare(cum.market_value, 0) == :gt,
                  do:
                    cum.market_value
                    |> then(&Decimal.div(item.total, &1))
                    |> Decimal.mult(100)
                    |> Decimal.round(1),
                  else: Decimal.new(0)

              "- #{inv_asset_type_label(item.asset_type)}: R$ #{fmt(item.total)} (#{fmt(pct)}%, #{item.count} ativos)"
            end)
            |> Enum.join("\n")

          "\nPATRIMÔNIO POR TIPO DE ATIVO:\n#{text}\n"
      end

    # ── Dividendos e ganhos (gráfico de barras) ──
    proventos_section =
      case Enum.filter(activity, fn a -> Decimal.compare(a.proventos, 0) == :gt end) do
        [] ->
          ""

        items ->
          text =
            items
            |> Enum.map(fn a -> "- #{a.key}: R$ #{fmt(a.proventos)}" end)
            |> Enum.join("\n")

          "\nDIVIDENDOS E GANHOS POR PERÍODO:\n#{text}\n"
      end

    # ── Aportes (gráfico de barras) ──
    aportes_section =
      case Enum.filter(activity, fn a -> Decimal.compare(a.aportes, 0) == :gt end) do
        [] ->
          ""

        items ->
          text =
            items
            |> Enum.map(fn a -> "- #{a.key}: R$ #{fmt(a.aportes)}" end)
            |> Enum.join("\n")

          "\nAPORTES POR PERÍODO:\n#{text}\n"
      end

    # ── Holdings table (top 30 ativos ativos) ──
    holdings_section =
      case Enum.filter(cum.holdings, & &1.is_active) do
        [] ->
          ""

        holdings ->
          text =
            holdings
            |> Enum.take(30)
            |> Enum.map(fn h ->
              price = if h.current_price, do: "Preço: R$ #{fmt(h.current_price)} | ", else: ""

              "- #{h.ticker || h.name} (#{inv_asset_type_label(h.type)}): #{fmt(h.net_qty)} un | #{price}Valor: R$ #{fmt(h.current_value)} | Investido: R$ #{fmt(h.net_total)} | Rent: #{fmt(h.gain_loss_pct)}%"
            end)
            |> Enum.join("\n")

          "\nCARTEIRA DE ATIVOS:\n#{text}\n"
      end

    # ── Ganhos por ativo ──
    proventos_by_asset_section =
      case per.proventos_by_asset do
        [] ->
          ""

        items ->
          text =
            items
            |> Enum.take(20)
            |> Enum.map(fn r ->
              "- #{r.ticker || r.name} (#{inv_asset_type_label(r.type)}): R$ #{fmt(r.total)}"
            end)
            |> Enum.join("\n")

          "\nGANHOS POR ATIVO:\n#{text}\n"
      end

    custom_part = PromptSanitizer.wrap_custom_prompt(custom_prompt)
    has_prompt = custom_part != ""

    """
    Analise os dados de investimentos de #{period} de um investidor brasileiro e forneça insights úteis.

    #{filter_desc}#{summary_text}
    #{individual_section}#{by_type_section}#{proventos_section}#{aportes_section}#{holdings_section}#{proventos_by_asset_section}
    #{custom_part}
    #{investment_json_format_instruction(has_prompt)}
    """
  end

  defp investment_json_format_instruction(has_user_prompt) do
    resposta_instruction =
      if has_user_prompt do
        "\"resposta\": \"Resposta direta e específica à pergunta/instrução do usuário acima\""
      else
        "\"resposta\": null"
      end

    """
    Responda em português brasileiro com exatamente este formato JSON:
    {
      "nota": <número decimal de 0.0 a 10.0 representando a saúde da carteira de investimentos>,
      "titulo": "Título curto e descritivo da análise (máximo 8 palavras)",
      "resumo": "Resumo conciso de 2-3 frases sobre a situação da carteira no período",
      "pontos": [
        {"tipo": "positivo", "texto": "Ponto positivo específico com dados reais"},
        {"tipo": "negativo", "texto": "Ponto negativo ou preocupante"},
        {"tipo": "neutro", "texto": "Observação relevante"},
        {"tipo": "dica", "texto": "Sugestão prática de investimento"}
      ],
      "alerta": "Alerta importante se houver algo preocupante, ou null se tudo estiver ok",
      #{resposta_instruction}
    }

    REGRAS:
    - Retorne APENAS o JSON, sem texto adicional
    - "pontos": inclua entre 3 e 6 pontos, usando os tipos: positivo, negativo, neutro, dica
    - "nota": baseie-se em: diversificação (+), proventos (+), concentração excessiva (-), taxas altas (-)
    - Seja direto e específico com números reais dos dados
    - Formate valores monetários no padrão brasileiro (R$ 5.550,09)
    """
  end

  defp inv_asset_type_label(type), do: Constants.asset_type_label(type)

  # ── AI Call ──

  defp call_ai(prompt, config) do
    ai_config = Map.merge(config, %{temperature: 0.3, max_output_tokens: 2048})

    # require Logger

    # Logger.warning("""
    # === PROMPT ENVIADO AO GEMINI ===
    # Modelo: #{ai_config[:model]}
    # Temperature: #{ai_config[:temperature]}
    # Max tokens: #{ai_config[:max_output_tokens]}

    # #{prompt}
    # ================================
    # """)

    case Provider.generate_content(prompt, ai_config) do
      {:ok, response_body} -> parse_response(response_body)
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_response(response_body) do
    text = Provider.extract_text(response_body)

    json_text =
      case Regex.run(~r/\{.*\}/s, text) do
        [match] -> match
        _ -> text
      end

    case Jason.decode(json_text) do
      {:ok, %{"nota" => _, "titulo" => _, "resumo" => _, "pontos" => _} = result} ->
        {:ok, result}

      {:ok, _} ->
        {:error, "Formato de resposta inesperado da IA"}

      {:error, _} ->
        {:error, "Falha ao processar resposta da IA"}
    end
  end
end
