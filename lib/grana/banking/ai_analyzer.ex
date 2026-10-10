defmodule Grana.Banking.AIAnalyzer do
  alias Grana.Accounts
  alias Grana.Banking
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

    # ── Top despesas ── (pré-computadas em build_summary; até 15)
    top_expenses =
      summary.top_expenses
      |> Enum.map(fn t ->
        cat = if t.category, do: t.category.name, else: "Sem Categoria"
        desc = PromptSanitizer.sanitize_description(t.description)
        "- #{desc}: R$ #{fmt(Decimal.abs(t.amount))} (#{cat})"
      end)
      |> Enum.join("\n")

    # ── Top receitas ──
    top_income =
      summary.top_income
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
    finish = Provider.finish_reason(response_body)

    json_text =
      case Regex.run(~r/\{.*\}/s, text) do
        [match] -> match
        _ -> text
      end

    case Jason.decode(json_text) do
      {:ok, result} when is_map(result) ->
        if valid_analysis?(result),
          do: {:ok, result},
          else: {:error, "Formato de resposta inesperado da IA"}

      _ ->
        {:error, decode_error_message(finish)}
    end
  end

  # Valida o contrato mínimo de saída: campos presentes e com os tipos que a UI
  # consome (pontos precisa ser lista; nota um número ou string numérica).
  defp valid_analysis?(%{"titulo" => titulo, "resumo" => resumo, "pontos" => pontos} = result)
       when is_binary(titulo) and is_binary(resumo) and is_list(pontos) do
    case Map.get(result, "nota") do
      n when is_number(n) -> true
      n when is_binary(n) -> match?({_, _}, Float.parse(n))
      _ -> false
    end
  end

  defp valid_analysis?(_), do: false

  defp decode_error_message("MAX_TOKENS"),
    do:
      "A resposta da IA foi cortada por exceder o limite de tokens. Reduza o período analisado ou seja mais específico na pergunta."

  defp decode_error_message("SAFETY"),
    do: "A IA bloqueou a resposta por filtros de segurança. Reformule a pergunta."

  defp decode_error_message("RECITATION"),
    do: "A IA interrompeu a resposta (conteúdo recitado). Tente novamente com outra pergunta."

  defp decode_error_message(_),
    do: "Falha ao processar resposta da IA"
end
