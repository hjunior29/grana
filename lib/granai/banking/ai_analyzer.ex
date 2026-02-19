defmodule Grana.Banking.AIAnalyzer do
  alias Grana.Accounts
  alias Grana.Banking
  alias Grana.AI.Provider

  def analyze_with_filters(user_id, filters, granaim_prompt \\ nil) do
    case Accounts.get_user_ai_config(user_id) do
      {:error, :no_api_key} -> {:error, :no_api_key}
      {:ok, config} -> do_analyze_filtered(user_id, filters, granaim_prompt, config)
    end
  end

  defp do_analyze_filtered(user_id, filters, granaim_prompt, config) do
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
        prompt = build_prompt(summary, period, filter_desc, granaim_prompt)
        call_ai(prompt, config)
    end
  end

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, _key, "all"), do: opts
  defp maybe_add(opts, _key, ""), do: opts
  defp maybe_add(opts, key, val), do: Keyword.put(opts, key, val)

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

  defp build_prompt(summary, period, filter_desc, granaim_prompt) do
    base = base_prompt_data(summary)

    granaim =
      case granaim_prompt do
        nil -> ""
        "" -> ""
        p -> "\nPERGUNTA/INSTRUÇÃO DO USUÁRIO (responda no campo \"resposta\" do JSON):\n#{p}\n"
      end

    has_prompt = granaim != ""

    """
    Analise os dados financeiros de #{period} de um usuário brasileiro e forneça insights úteis.

    #{filter_desc}#{base}
    #{granaim}
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
