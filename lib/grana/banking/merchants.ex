defmodule Grana.Banking.Merchants do
  @moduledoc """
  The user's merchants and counterparties, aggregated from the transaction descriptions
  (same normalization as the fixed-expenses detection). Lets the AI specialists learn
  what the user actually pays for, like which health plan or which delivery apps, instead
  of guessing from category names.
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
      name:
        txns
        |> Enum.frequencies_by(&merchant_part(&1.description))
        |> Enum.max_by(&elem(&1, 1))
        |> elem(0),
      category: latest.category && latest.category.name,
      count: length(txns),
      total:
        txns |> Enum.map(&Decimal.abs(&1.amount)) |> Enum.reduce(Decimal.new(0), &Decimal.add/2),
      last_date: latest.date
    }
  end

  # "Transferência enviada pelo Pix - JOAO SILVA" -> "JOAO SILVA".
  defp merchant_part(description) do
    description |> String.split(" - ") |> List.last() |> String.trim()
  end
end
