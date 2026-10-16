defmodule Grana.Agents.ChatTools do
  @moduledoc """
  Deterministic data tools of the chat coordinator. Every number the chat answers with
  comes from these queries (the same ones behind the dashboard), never from the model.
  Results are JSON with money already formatted in Brazilian reais.
  """

  alias Grana.Banking
  alias Grana.Banking.Search
  alias Grana.Money
  alias Grana.AI.PromptSanitizer
  alias LangChain.Function

  @search_limit 50

  @filters %{
    bank: %{type: "string", description: "A bank name from the overview. Omit for all."},
    statement_type: %{
      type: "string",
      enum: ["extrato", "fatura"],
      description: "extrato = bank account, fatura = credit card bill. Omit for both."
    }
  }

  def all(%{user_id: user_id}) do
    [
      overview(user_id),
      Grana.Agents.DataTools.list_merchants(user_id),
      period_summary(user_id),
      monthly_totals(user_id),
      search(user_id),
      fixed_expenses(user_id),
      installments(user_id),
      goals(user_id)
    ]
  end

  defp overview(user_id) do
    tool(
      "get_data_overview",
      "What data exists: years and months with transactions, banks, categories and today's date. Call it first when unsure about periods or names.",
      %{},
      [],
      fn _args ->
        months =
          user_id
          |> Banking.available_months()
          |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
          |> Map.new(fn {year, months} -> {year, Enum.sort(months)} end)

        %{
          today: Date.utc_today(),
          years: Banking.available_years(user_id),
          months_with_data: months,
          banks: Banking.available_banks(user_id),
          categories:
            user_id |> Banking.list_categories() |> Enum.map(&%{name: &1.name, kind: &1.kind})
        }
      end
    )
  end

  defp period_summary(user_id) do
    tool(
      "get_period_summary",
      "Totals of a month, a year or all time: income, expenses, investments, free balance, expenses by category and the largest expenses and incomes. Internal transfers and card bill payments are already excluded.",
      Map.merge(@filters, %{
        year: %{type: "integer", description: "Omit for all time."},
        month: %{type: "integer", description: "1 to 12. Omit for the whole year."},
        type: %{
          type: "string",
          enum: ["credit", "debit"],
          description: "Only income or only expenses."
        }
      }),
      [],
      fn args ->
        opts = filter_opts(args, [:bank, :statement_type, :type])

        summary =
          case args do
            %{"year" => year, "month" => month} when is_integer(year) and month in 1..12 ->
              Banking.monthly_summary(user_id, year, month, opts)

            %{"year" => year} when is_integer(year) ->
              Banking.yearly_summary(user_id, year, opts)

            _ ->
              Banking.all_time_summary(user_id, opts)
          end

        %{
          income: brl(summary.total_income),
          expenses: brl(summary.total_expenses),
          investments: brl(summary.total_investments),
          free_balance: brl(summary.balance),
          transactions: summary.transaction_count,
          expenses_by_category:
            Enum.map(
              summary.by_category,
              &%{category: category(&1), total: brl(&1.total), count: &1.count}
            ),
          largest_expenses: summary.top_expenses |> Enum.take(10) |> Enum.map(&transaction/1),
          largest_incomes: summary.top_income |> Enum.take(5) |> Enum.map(&transaction/1)
        }
      end
    )
  end

  defp monthly_totals(user_id) do
    tool(
      "get_monthly_totals",
      "Income, expenses and investments month by month in a year, to compare months or see trends.",
      Map.put(@filters, :year, %{type: "integer"}),
      ["year"],
      fn %{"year" => year} = args ->
        user_id
        |> Banking.monthly_income_expenses(year, filter_opts(args, [:bank, :statement_type]))
        |> Enum.map(fn row ->
          %{
            month: row.month,
            income: brl(row.income),
            expenses: brl(row.expenses),
            investments: brl(Map.get(row, :investments, Decimal.new(0)))
          }
        end)
      end
    )
  end

  defp search(user_id) do
    tool(
      "search_transactions",
      "Finds transactions with the advanced search syntax and returns how many, the totals and the most recent ones. Use it for questions about specific merchants, people, categories or values.\n\n" <>
        Grana.Agents.SearchBuilder.syntax_reference(),
      %{
        query: %{type: "string", description: "Query in the advanced search syntax."},
        limit: %{
          type: "integer",
          description: "How many transactions to list (max #{@search_limit})."
        }
      },
      ["query"],
      fn %{"query" => query} = args ->
        case Search.parse(query) do
          {:ok, search} ->
            found =
              Banking.search_transactions(user_id, search, sort_by: "date", sort_dir: "desc")

            {credits, debits} = Enum.split_with(found, &(&1.type == "credit"))
            limit = min(args["limit"] || 20, @search_limit)

            %{
              count: length(found),
              total_in: brl(sum(credits)),
              total_out: brl(sum(debits)),
              transactions: found |> Enum.take(limit) |> Enum.map(&transaction/1)
            }

          {:error, reason} ->
            {:error, "Invalid query: #{reason}"}
        end
      end
    )
  end

  defp fixed_expenses(user_id) do
    tool(
      "get_fixed_expenses",
      "Recurring (fixed) expenses detected in the last months, with the monthly averages of fixed and variable spending.",
      Map.put(@filters, :months, %{
        type: "integer",
        description: "Window in months: 6 (default) or 12."
      }),
      [],
      fn args ->
        analysis =
          Banking.recurring_analysis(
            user_id,
            [window: if(args["months"] == 12, do: 12, else: 6)] ++
              filter_opts(args, [:bank, :statement_type])
          )

        %{
          months_analyzed: analysis.total_months,
          average_fixed_per_month: brl(analysis.avg_fixed),
          average_variable_per_month: brl(analysis.avg_variable),
          fixed_expenses:
            Enum.map(analysis.fixed, fn item ->
              %{
                name: PromptSanitizer.sanitize_description(item.name),
                category: PromptSanitizer.sanitize_description(category(item)),
                average: brl(item.avg_amount),
                last: brl(item.last_amount),
                months_present: item.months_present,
                typical_day: item.typical_day
              }
            end)
        }
      end
    )
  end

  defp installments(user_id) do
    tool(
      "get_installments",
      "Active installment purchases: how much they take per month and how much is left.",
      %{},
      [],
      fn _args ->
        summary = Banking.installment_projection_summary(user_id)

        %{
          active: summary.active_count,
          per_month: brl(summary.this_month_total),
          left_to_pay: brl(summary.total_remaining),
          items:
            Enum.map(summary.installments, fn txn ->
              Map.merge(transaction(txn), %{
                installment: "#{txn.installment_current}/#{txn.installment_total}"
              })
            end)
        }
      end
    )
  end

  defp goals(user_id) do
    tool(
      "get_goals",
      "The user's financial goals and their progress in a month.",
      %{year: %{type: "integer"}, month: %{type: "integer"}},
      [],
      fn args ->
        today = Date.utc_today()

        user_id
        |> Banking.goals_progress(args["year"] || today.year, args["month"] || today.month)
        |> Enum.map(fn progress ->
          %{
            goal: progress.goal.type,
            category: progress.goal.category && progress.goal.category.name,
            target: brl(progress.target),
            current: brl(progress.current),
            percent: progress.pct,
            status: progress.status
          }
        end)
      end
    )
  end

  defp tool(name, description, properties, required, handler) do
    Function.new!(%{
      name: name,
      description: description,
      parameters_schema: %{type: "object", properties: properties, required: required},
      function: fn args, _context ->
        case handler.(args) do
          {:error, reason} -> {:error, reason}
          result -> {:ok, Jason.encode!(result)}
        end
      end
    })
  end

  defp filter_opts(args, keys) do
    for key <- keys,
        value = args[Atom.to_string(key)],
        value not in [nil, "", "all"],
        do: {key, value}
  end

  defp transaction(txn) do
    %{
      date: txn.date,
      description: PromptSanitizer.sanitize_description(txn.description),
      amount: brl(txn.amount),
      category: PromptSanitizer.sanitize_description(category(txn)),
      bank: bank(txn)
    }
  end

  defp category(%{category: %{name: name}}), do: name
  defp category(_item), do: "Sem Categoria"

  defp bank(%{bank_statement: %{bank: bank}}), do: bank
  defp bank(_txn), do: nil

  defp sum(transactions),
    do: Enum.reduce(transactions, Decimal.new(0), &Decimal.add(Decimal.abs(&1.amount), &2))

  defp brl(value), do: Money.format(value)
end
