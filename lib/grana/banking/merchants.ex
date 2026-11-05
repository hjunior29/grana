defmodule Grana.Banking.Merchants do
  @moduledoc """
  The user's merchants and counterparties, aggregated from the transaction descriptions
  (same normalization as the fixed-expenses detection). Lets the AI specialists learn
  what the user actually pays for, like which health plan or which delivery apps, instead
  of guessing from category names, and the dashboard show where the money of a period went.
  """

  import Ecto.Query

  alias Grana.Banking.RecurringExpenses
  alias Grana.Banking.Transaction
  alias Grana.Repo

  @default_limit 60

  @type merchant :: %{
          name: String.t(),
          category: String.t() | nil,
          count: non_neg_integer(),
          total: Decimal.t(),
          last_date: Date.t()
        }

  @doc """
  Merchants by frequency. Options: `:type` (`"credit"` or `"debit"`), `:months` (window
  until today) and `:limit` (default #{@default_limit}).
  """
  @spec list(pos_integer(), keyword()) :: [merchant()]
  def list(user_id, opts \\ []) do
    user_id
    |> transactions(opts)
    |> Enum.group_by(&RecurringExpenses.normalize(&1.description))
    |> Enum.reject(fn {key, _txns} -> key == "" end)
    |> Enum.map(fn {_key, txns} -> aggregate(txns) end)
    |> Enum.sort_by(&{-&1.count, Date.to_iso8601(&1.last_date)}, :asc)
    |> Enum.take(Keyword.get(opts, :limit, @default_limit))
  end

  @doc """
  Spending by merchant of already loaded transactions (with the category preloaded),
  biggest total first: the name, the most common category, purchase count, total and
  average ticket.
  """
  def spending(transactions) do
    transactions
    |> Enum.group_by(&(&1.description |> without_installment() |> RecurringExpenses.normalize()))
    |> Enum.reject(fn {key, _txns} -> key == "" end)
    |> Enum.map(fn {key, txns} ->
      total =
        txns |> Enum.map(&Decimal.abs(&1.amount)) |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

      %{
        key: key,
        name:
          txns |> Enum.map(&merchant_part(without_installment(&1.description))) |> most_common(),
        category: txns |> Enum.map(& &1.category) |> Enum.reject(&is_nil/1) |> most_common(),
        count: length(txns),
        total: total,
        average: total |> Decimal.div(length(txns)) |> Decimal.round(2)
      }
    end)
    |> Enum.sort_by(& &1.total, {:desc, Decimal})
  end

  # "MAGAZINE LUIZA 3/10" -> "MAGAZINE LUIZA": every installment of a purchase is one merchant.
  defp without_installment(description),
    do: String.replace(description, ~r/\s+\d{1,2}\s*\/\s*\d{1,2}\s*$/, "")

  defp most_common([]), do: nil

  defp most_common(values) do
    values |> Enum.frequencies() |> Enum.max_by(&elem(&1, 1)) |> elem(0)
  end

  @doc "Distinct names (merchant part of the descriptions), for the privacy mask."
  @spec names(pos_integer()) :: [String.t()]
  def names(user_id) do
    Transaction
    |> where([t], t.user_id == ^user_id)
    |> select([t], t.description)
    |> distinct(true)
    |> Repo.all()
    |> Enum.map(&merchant_part/1)
    |> Enum.uniq()
  end

  defp transactions(user_id, opts) do
    query =
      Transaction
      |> where([t], t.user_id == ^user_id and t.is_internal_transfer == false)
      |> preload(:category)

    query =
      case opts[:type] do
        type when type in ["credit", "debit"] -> where(query, [t], t.type == ^type)
        _ -> query
      end

    query =
      case opts[:months] do
        months when is_integer(months) and months > 0 ->
          where(query, [t], t.date >= ^Date.add(Date.utc_today(), -30 * months))

        _ ->
          query
      end

    Repo.all(query)
  end

  defp aggregate(txns) do
    latest = Enum.max_by(txns, & &1.date, Date)

    %{
      name: common_name(txns),
      category: latest.category && latest.category.name,
      count: length(txns),
      total:
        txns |> Enum.map(&Decimal.abs(&1.amount)) |> Enum.reduce(Decimal.new(0), &Decimal.add/2),
      last_date: latest.date
    }
  end

  defp common_name(txns) do
    txns
    |> Enum.frequencies_by(&merchant_part(&1.description))
    |> Enum.max_by(&elem(&1, 1))
    |> elem(0)
  end

  # "Transferência enviada pelo Pix - JOAO SILVA" -> "JOAO SILVA".
  defp merchant_part(description) do
    description |> String.split(" - ") |> List.last() |> String.trim()
  end
end
