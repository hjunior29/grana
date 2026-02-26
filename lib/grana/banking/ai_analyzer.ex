defmodule Grana.Banking.AIAnalyzer do
  alias Grana.Accounts
  alias Grana.Banking
  alias Grana.Investments
  alias Grana.AI.Provider

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

        filter_desc = build_filter_desc(bank, type, statement_type)
        prompt = build_prompt(summary, period, filter_desc, custom_prompt)
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

    opts =
      []
      |> maybe_add(:institution_id, institution_id)
      |> maybe_add(:asset_type, asset_type)

    period_opts =
      case month do
        m when m in [nil, 0] ->
          [date_from: Date.new!(year, 1, 1), date_to: Date.new!(year, 12, 31)] ++ opts

        m ->
          date_start = Date.new!(year, m, 1)
          [date_from: date_start, date_to: Date.end_of_month(date_start)] ++ opts
      end

    summary = Investments.portfolio_summary(user_id, period_opts)

    case summary.transaction_count do
      0 ->
        {:error, "Nenhuma transação de investimento encontrada com os filtros selecionados"}

      _ ->
        period =
          case month do
            m when m in [nil, 0] -> "#{year}"
            m -> "#{Banking.month_name(m)}/#{year}"
          end

        filter_desc = build_inv_filter_desc(institution_id, asset_type)
        prompt = build_investment_prompt(summary, period, filter_desc, custom_prompt)
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

  defp build_prompt(summary, period, filter_desc, custom_prompt) do
    base = base_prompt_data(summary)

    custom_prompt =
      case custom_prompt do
        nil -> ""
        "" -> ""
        p -> "\nPERGUNTA/INSTRUÇÃO DO USUÁRIO (responda no campo \"resposta\" do JSON):\n#{p}\n"
      end

    has_prompt = custom_prompt != ""

    """
    Analise os dados financeiros de #{period} de um usuário brasileiro e forneça insights úteis.

    #{filter_desc}#{base}
    #{custom_prompt}
    #{json_format_instruction(has_prompt)}
    """
  end

  defp base_prompt_data(summary) do
    categories_text =
      summary.by_category
      |> Enum.map(fn item ->
        name = if item.category, do: item.category.name, else: "Sem Categoria"
        total = Decimal.to_string(item.total, :normal)
        "- #{name}: R$ #{total} (#{item.count} transações)"
      end)
      |> Enum.join("\n")

    top_expenses =
      summary.transactions
      |> Enum.filter(&(&1.type == "debit"))
      |> Enum.sort_by(fn t -> Decimal.to_float(Decimal.abs(t.amount)) end, :desc)
      |> Enum.take(15)
      |> Enum.map(fn t ->
        cat = if t.category, do: t.category.name, else: "Sem Categoria"
        "- #{t.description}: R$ #{Decimal.to_string(Decimal.abs(t.amount), :normal)} (#{cat})"
      end)
      |> Enum.join("\n")

    """
    RESUMO:
    - Receitas: R$ #{Decimal.to_string(summary.total_income, :normal)}
    - Despesas: R$ #{Decimal.to_string(summary.total_expenses, :normal)}
    - Saldo: R$ #{Decimal.to_string(summary.balance, :normal)}
    - Total de transações: #{summary.transaction_count}

    DESPESAS POR CATEGORIA:
    #{categories_text}

    MAIORES DESPESAS:
    #{top_expenses}
    """
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

  defp build_investment_prompt(summary, period, filter_desc, custom_prompt) do
    holdings_text =
      summary.holdings
      |> Enum.filter(& &1.is_active)
      |> Enum.take(20)
      |> Enum.map(fn h ->
        "- #{h.ticker || h.name} (#{inv_asset_type_label(h.type)}): R$ #{Decimal.to_string(h.net_total, :normal)} investido, #{Decimal.to_string(h.net_qty)} unidades"
      end)
      |> Enum.join("\n")

    by_type_text =
      summary.by_asset_type
      |> Enum.map(fn item ->
        "- #{inv_asset_type_label(item.asset_type)}: R$ #{Decimal.to_string(item.total, :normal)} (#{item.count} ativos)"
      end)
      |> Enum.join("\n")

    proventos_text =
      summary.proventos_by_asset
      |> Enum.take(10)
      |> Enum.map(fn r ->
        "- #{r.ticker || r.name}: R$ #{Decimal.to_string(r.total, :normal)}"
      end)
      |> Enum.join("\n")

    custom_part =
      case custom_prompt do
        nil -> ""
        "" -> ""
        p -> "\nPERGUNTA/INSTRUÇÃO DO USUÁRIO (responda no campo \"resposta\" do JSON):\n#{p}\n"
      end

    has_prompt = custom_part != ""

    """
    Analise os dados de investimentos de #{period} de um investidor brasileiro e forneça insights úteis.

    #{filter_desc}RESUMO DA CARTEIRA:
    - Total Comprado: R$ #{Decimal.to_string(summary.total_bought, :normal)}
    - Total Vendido: R$ #{Decimal.to_string(summary.total_sold, :normal)}
    - Posição Líquida: R$ #{Decimal.to_string(summary.net_position, :normal)}
    - Proventos Recebidos: R$ #{Decimal.to_string(summary.proventos, :normal)}
    - Taxas Pagas: R$ #{Decimal.to_string(summary.total_fees, :normal)}
    - Total de Transações: #{summary.transaction_count}

    CARTEIRA POR TIPO DE ATIVO:
    #{by_type_text}

    HOLDINGS (posições ativas):
    #{holdings_text}

    MAIORES PAGADORES DE PROVENTOS:
    #{proventos_text}
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

  defp inv_asset_type_label("acao"), do: "Ações"
  defp inv_asset_type_label("fii"), do: "FII"
  defp inv_asset_type_label("etf"), do: "ETF"
  defp inv_asset_type_label("bdr"), do: "BDR"
  defp inv_asset_type_label("renda_fixa"), do: "Renda Fixa"
  defp inv_asset_type_label("tesouro"), do: "Tesouro"
  defp inv_asset_type_label("cripto"), do: "Cripto"
  defp inv_asset_type_label("fundo"), do: "Fundo"
  defp inv_asset_type_label("nota_fiscal"), do: "Nota Fiscal"
  defp inv_asset_type_label("debenture"), do: "Debênture"
  defp inv_asset_type_label("precatorio"), do: "Precatório"
  defp inv_asset_type_label("recebiveis"), do: "Receb. Judiciais"
  defp inv_asset_type_label("cri"), do: "CRI"
  defp inv_asset_type_label("cra"), do: "CRA"
  defp inv_asset_type_label("op_estruturada"), do: "Op. Estruturada"
  defp inv_asset_type_label("outro"), do: "Outro"
  defp inv_asset_type_label(type), do: String.capitalize(to_string(type))

  # ── AI Call ──

  defp call_ai(prompt, config) do
    ai_config = Map.merge(config, %{temperature: 0.3, max_output_tokens: 2048})

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
