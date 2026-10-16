defmodule Grana.Agents.Analyst do
  @moduledoc """
  Financial analysis of a month or a year. All numbers are computed here, from the same
  queries as the dashboard, and the model only reads them and writes the insights.

  The answer keeps the JSON keys of the analyses already saved (`nota`, `titulo`,
  `resumo`, `pontos`, `alerta`, `resposta`), which the analysis screen renders.
  """

  @behaviour Grana.Agents.Specialist

  alias Grana.AI
  alias Grana.AI.ChatModel
  alias Grana.AI.LLM
  alias Grana.AI.PromptSanitizer
  alias Grana.Banking
  alias Grana.Money
  alias LangChain.Chains.LLMChain
  alias LangChain.Function
  alias LangChain.Message

  @impl true
  def key, do: "analysis"

  @doc """
  `filters` has `:year`, `:month` (0 or nil for the whole year) and optionally `:bank`,
  `:type` and `:statement_type`. Returns `{:ok, %{analysis:, ai_provider:, ai_model:}}`.
  """
  def run(user_id, filters, question \\ nil, choice \\ nil) do
    with {:ok, data} <- period_data(user_id, filters),
         {:ok, config} <- AI.resolve(user_id, key(), choice),
         {:ok, analysis} <- ask(prompt(data, question), config) do
      {:ok, %{analysis: analysis, ai_provider: config.name, ai_model: config.model}}
    end
  end

  @impl true
  def tool(%{user_id: user_id}) do
    Function.new!(%{
      name: "analyze_period",
      description:
        "Runs the financial analysis specialist on a month or a whole year: a health score " <>
          "from 0 to 10, a summary, positive and negative points, tips and alerts.",
      parameters_schema: %{
        type: "object",
        properties: %{
          year: %{type: "integer"},
          month: %{type: "integer", description: "1 to 12, or 0 for the whole year."},
          bank: %{type: "string", description: "A bank name, or all."},
          statement_type: %{type: "string", enum: ["all", "extrato", "fatura"]},
          type: %{type: "string", enum: ["all", "credit", "debit"]},
          question: %{type: "string", description: "Optional question to answer."}
        },
        required: ["year"]
      },
      function: fn args, _context ->
        filters = %{
          year: args["year"],
          month: args["month"] || 0,
          bank: args["bank"],
          statement_type: args["statement_type"],
          type: args["type"]
        }

        case run(user_id, filters, args["question"]) do
          {:ok, result} -> {:ok, Jason.encode!(result), result}
          {:error, :no_api_key} -> {:error, "No AI provider is configured."}
          {:error, reason} -> {:error, to_string(reason)}
        end
      end
    })
  end

  defp ask(prompt, config) do
    %{llm: ChatModel.new(config, temperature: 0.3, max_tokens: 4096)}
    |> LLMChain.new!()
    |> LLMChain.add_message(Message.new_user!(prompt))
    |> LLM.run()
    |> case do
      {:ok, chain} -> parse(LLM.last_text(chain))
      {:error, reason} -> {:error, reason}
    end
  end

  defp period_data(user_id, filters) do
    year = filters[:year]
    month = if filters[:month] in [nil, 0], do: nil, else: filters[:month]

    opts =
      for key <- [:bank, :type, :statement_type],
          value = filters[key],
          value not in [nil, "", "all"],
          do: {key, value}

    summary =
      if month,
        do: Banking.monthly_summary(user_id, year, month, opts),
        else: Banking.yearly_summary(user_id, year, opts)

    if summary.transaction_count == 0 do
      {:error, "Nenhuma transação encontrada com os filtros selecionados"}
    else
      years = Banking.available_years(user_id)

      monthly =
        if month,
          do: Banking.monthly_income_expenses(user_id, year, opts),
          else:
            Enum.flat_map(years, fn y ->
              user_id
              |> Banking.monthly_income_expenses(y, opts)
              |> Enum.map(&Map.put(&1, :year, y))
            end)

      installment_opts = if month, do: opts ++ [year: year, month: month], else: opts

      {:ok,
       %{
         summary: summary,
         year: year,
         month: month,
         filters: filters,
         years: years,
         monthly: monthly,
         daily: if(month, do: Banking.daily_spending(user_id, year, month, opts), else: []),
         installments: Banking.installment_projection_summary(user_id, installment_opts)
       }}
    end
  end

  defp prompt(data, question) do
    question_block = PromptSanitizer.wrap_custom_prompt(question)

    """
    Analyze the finances of a Brazilian user for #{period_label(data)} and give useful insights.
    #{filters_label(data.filters)}
    #{data_block(data)}
    #{question_block}
    #{answer_format(question_block != "")}
    """
  end

  defp period_label(%{month: nil, year: year}), do: "the year #{year}"
  defp period_label(%{month: month, year: year}), do: "#{Banking.month_name(month)}/#{year}"

  defp filters_label(filters) do
    parts =
      [
        filters[:bank] not in [nil, "", "all"] && "bank #{filters[:bank]}",
        filters[:statement_type] == "extrato" && "bank account statements only",
        filters[:statement_type] == "fatura" && "credit card bills only",
        filters[:type] == "credit" && "income only",
        filters[:type] == "debit" && "expenses only"
      ]
      |> Enum.filter(& &1)

    if parts == [], do: "", else: "Filters applied: #{Enum.join(parts, ", ")}."
  end

  defp data_block(%{summary: summary} = data) do
    """
    SUMMARY
    - Income: #{brl(summary.total_income)}
    - Expenses: #{brl(summary.total_expenses)}
    - Investments: #{brl(summary.total_investments)}
    - Free balance: #{brl(summary.balance)}
    - #{average_line(data)}
    - Transactions: #{summary.transaction_count}

    EXPENSES BY CATEGORY
    #{lines(summary.by_category, &"- #{category_name(&1)}: #{brl(&1.total)} (#{&1.count} transactions)")}
    #{daily_block(data.daily)}#{yearly_block(data)}#{monthly_block(data.monthly)}
    TOP EXPENSES
    #{lines(summary.top_expenses, &"- #{description(&1)}: #{brl(Decimal.abs(&1.amount))} (#{category_name(&1)})")}
    #{income_block(summary.top_income)}#{installments_block(data.installments)}
    """
  end

  defp average_line(%{month: nil, summary: summary, years: years}) do
    average =
      if years == [],
        do: Decimal.new(0),
        else: Decimal.div(summary.total_expenses, length(years))

    "Average expenses per year: #{brl(average)}"
  end

  defp average_line(%{month: month, year: year, summary: summary}) do
    days = Date.days_in_month(Date.new!(year, month, 1))
    "Average expenses per day: #{brl(Decimal.div(summary.total_expenses, days))}"
  end

  defp daily_block([]), do: ""

  defp daily_block(daily) do
    rows =
      daily
      |> Enum.sort_by(& &1.date, Date)
      |> lines(&"- #{Calendar.strftime(&1.date, "%d/%m")}: #{brl(&1.total)}")

    "\nDAILY EXPENSES\n#{rows}\n"
  end

  defp yearly_block(%{month: nil, monthly: monthly}) do
    rows =
      monthly
      |> Enum.group_by(& &1.year)
      |> Enum.sort_by(fn {year, _} -> year end)
      |> lines(fn {year, items} ->
        "- #{year}: #{brl(items |> Enum.map(& &1.expenses) |> Enum.reduce(Decimal.new(0), &Decimal.add/2))}"
      end)

    "\nEXPENSES PER YEAR\n#{rows}\n"
  end

  defp yearly_block(_data), do: ""

  defp monthly_block([]), do: ""

  defp monthly_block(monthly) do
    rows =
      lines(monthly, fn item ->
        label =
          case item[:year] do
            nil -> Banking.month_name_short(item.month)
            year -> "#{Banking.month_name_short(item.month)}/#{year}"
          end

        investments = Map.get(item, :investments, Decimal.new(0))

        "- #{label}: income #{brl(item.income)} | expenses #{brl(item.expenses)} | investments #{brl(investments)}"
      end)

    "\nINCOME VS EXPENSES PER MONTH\n#{rows}\n"
  end

  defp income_block([]), do: ""

  defp income_block(top_income) do
    rows =
      top_income
      |> Enum.take(10)
      |> lines(&"- #{description(&1)}: #{brl(&1.amount)} (#{category_name(&1)})")

    "\nTOP INCOME\n#{rows}\n"
  end

  defp installments_block(%{active_count: 0}), do: ""

  defp installments_block(installments) do
    rows =
      lines(installments.installments, fn txn ->
        remaining = txn.installment_total - txn.installment_current
        left = Decimal.mult(Decimal.abs(txn.amount), remaining)

        "- #{description(txn)}: #{brl(Decimal.abs(txn.amount))}/month " <>
          "(#{txn.installment_current}/#{txn.installment_total}), " <>
          "#{brl(left)} left (#{category_name(txn)})"
      end)

    """

    ACTIVE INSTALLMENTS (#{installments.active_count})
    - Monthly total: #{brl(installments.this_month_total)}
    - Total left: #{brl(installments.total_remaining)}
    #{rows}
    """
  end

  defp answer_format(with_question?) do
    answer =
      if with_question?,
        do: ~s("resposta": "Direct and specific answer to the user's question above"),
        else: ~s("resposta": null)

    """
    Reply in Brazilian Portuguese with exactly this JSON and nothing else:
    {
      "nota": <decimal from 0.0 to 10.0 for the overall financial health>,
      "titulo": "Short title for the analysis (at most 8 words)",
      "resumo": "Concise summary of the period in 2 or 3 sentences",
      "pontos": [
        {"tipo": "positivo", "texto": "Specific positive point with real numbers"},
        {"tipo": "negativo", "texto": "Negative or worrying point"},
        {"tipo": "neutro", "texto": "Relevant observation"},
        {"tipo": "dica", "texto": "Practical saving tip"}
      ],
      "alerta": "Important alert if something is worrying, or null",
      #{answer}
    }

    Rules:
    - "pontos": between 3 and 6 items, with the types positivo, negativo, neutro and dica.
    - "nota": positive balance and controlled spending raise it; excessive spending lowers it.
    - Be direct and use the real numbers above.
    - Money in the Brazilian format (R$ 5.550,09).
    """
  end

  defp parse(text) do
    json = with [match] <- Regex.run(~r/\{.*\}/s, text), do: match

    case Jason.decode(json || text) do
      {:ok, analysis} when is_map(analysis) ->
        if valid?(analysis),
          do: {:ok, analysis},
          else: {:error, "Formato de resposta inesperado da IA"}

      _ ->
        {:error, "Falha ao processar resposta da IA"}
    end
  end

  defp valid?(%{"titulo" => title, "resumo" => summary, "pontos" => points} = analysis)
       when is_binary(title) and is_binary(summary) and is_list(points) do
    case analysis["nota"] do
      score when is_number(score) -> true
      score when is_binary(score) -> match?({_, _}, Float.parse(score))
      _ -> false
    end
  end

  defp valid?(_analysis), do: false

  defp lines(items, fun), do: Enum.map_join(items, "\n", fun)

  defp category_name(%{category: %{name: name}}), do: name
  defp category_name(_item), do: "Sem Categoria"

  defp description(txn), do: PromptSanitizer.sanitize_description(txn.description)

  defp brl(decimal), do: Money.format(decimal)
end
