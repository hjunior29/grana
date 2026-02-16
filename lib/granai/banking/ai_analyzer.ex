defmodule Granai.Banking.AIAnalyzer do
  alias Granai.Banking

  def analyze_month(user_id, year, month) do
    api_key = Application.get_env(:granai, :gemini_api_key) || System.get_env("GEMINI_API_KEY")

    case api_key do
      nil -> {:error, "GEMINI_API_KEY not configured"}
      key -> do_analyze(user_id, year, month, key)
    end
  end

  def analyze_with_filters(user_id, filters, granaim_prompt \\ nil) do
    api_key = Application.get_env(:granai, :gemini_api_key) || System.get_env("GEMINI_API_KEY")

    case api_key do
      nil -> {:error, "GEMINI_API_KEY not configured"}
      key -> do_analyze_filtered(user_id, filters, granaim_prompt, key)
    end
  end

  defp do_analyze(user_id, year, month, api_key) do
    summary = Banking.monthly_summary(user_id, year, month)

    case summary.transaction_count do
      0 -> {:error, "Nenhuma transação encontrada neste período"}
      _ -> call_gemini(build_prompt(summary, year, month), api_key)
    end
  end

  defp do_analyze_filtered(user_id, filters, granaim_prompt, api_key) do
    month = filters[:month] || filters["month"]
    year = filters[:year] || filters["year"]
    bank = filters[:bank] || filters["bank"]
    type = filters[:type] || filters["type"]

    opts =
      []
      |> maybe_add(:bank, bank)
      |> maybe_add(:type, type)

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

        filter_desc = build_filter_desc(bank, type)
        prompt = build_filtered_prompt(summary, period, filter_desc, granaim_prompt)
        call_gemini(prompt, api_key)
    end
  end

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, _key, "all"), do: opts
  defp maybe_add(opts, _key, ""), do: opts
  defp maybe_add(opts, key, val), do: Keyword.put(opts, key, val)

  defp build_filter_desc(bank, type) do
    parts =
      []
      |> add_desc(bank, fn
        nil -> nil
        "all" -> nil
        b -> "Banco: #{String.capitalize(b)}"
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

  defp build_filtered_prompt(summary, period, filter_desc, granaim_prompt) do
    base = base_prompt_data(summary)

    granaim =
      case granaim_prompt do
        nil -> ""
        "" -> ""
        p -> "\nINSTRUÇÕES ADICIONAIS DO USUÁRIO:\n#{p}\n"
      end

    """
    Analise os dados financeiros de #{period} de um usuário brasileiro e forneça insights úteis.

    #{filter_desc}#{base}
    #{granaim}
    #{json_format_instruction()}
    """
  end

  defp build_prompt(summary, year, month) do
    base = base_prompt_data(summary)

    """
    Analise os dados financeiros de #{Banking.month_name(month)}/#{year} de um usuário brasileiro e forneça insights úteis.

    #{base}

    #{json_format_instruction()}
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

  defp json_format_instruction do
    """
    Responda em português brasileiro com exatamente este formato JSON:
    {
      "resumo": "Uma frase resumindo a saúde financeira do mês",
      "insights": [
        "Insight 1 sobre os gastos",
        "Insight 2 sobre padrões identificados",
        "Insight 3 sobre oportunidades de economia"
      ],
      "alerta": "Um alerta importante se houver algo preocupante, ou null se tudo estiver ok",
      "dica": "Uma dica prática de economia baseada nos dados"
    }

    Retorne APENAS o JSON, sem explicações adicionais. Seja direto e específico com números reais dos dados.
    IMPORTANTE: Formate todos os valores monetários no padrão brasileiro (ex: R$ 5.550,09 e não R$ 5550.09).
    """
  end

  defp call_gemini(prompt, api_key) do
    url =
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=#{api_key}"

    body = %{
      contents: [%{parts: [%{text: prompt}]}],
      generationConfig: %{temperature: 0.3, maxOutputTokens: 1024}
    }

    case Req.post(url, json: body) do
      {:ok, %{status: 200, body: response_body}} ->
        parse_response(response_body)

      {:ok, %{status: status, body: body}} ->
        {:error, "Gemini API error: #{status} - #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  defp parse_response(response_body) do
    text =
      response_body
      |> get_in(["candidates", Access.at(0), "content", "parts", Access.at(0), "text"])
      |> to_string()

    json_text =
      case Regex.run(~r/\{.*\}/s, text) do
        [match] -> match
        _ -> text
      end

    case Jason.decode(json_text) do
      {:ok, %{"resumo" => _, "insights" => _, "dica" => _} = result} ->
        {:ok, result}

      {:ok, _} ->
        {:error, "Formato de resposta inesperado da IA"}

      {:error, _} ->
        {:error, "Falha ao processar resposta da IA"}
    end
  end
end
