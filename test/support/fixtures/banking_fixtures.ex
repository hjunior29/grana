defmodule Grana.BankingFixtures do
  @moduledoc """
  Helpers de fixture para o contexto Banking.
  Usa diretamente Banking/Repo — não mexe em lib/.
  """

  alias Grana.Banking
  alias Grana.Repo

  def category_fixture(user, attrs \\ %{}) do
    Banking.ensure_default_categories(user.id)
    attrs = Map.merge(%{name: "Cat-#{System.unique_integer()}", user_id: user.id}, attrs)

    {:ok, cat} = Banking.create_category(attrs)
    cat
  end

  def uncategorized_category(user) do
    Banking.ensure_default_categories(user.id)
    Banking.get_uncategorized_category(user.id)
  end

  def statement_fixture(user, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          bank: "nubank",
          filename: "fixture-#{System.unique_integer()}.csv",
          statement_type: "extrato",
          user_id: user.id
        },
        attrs
      )

    {:ok, stmt} = Banking.create_statement(attrs)
    stmt
  end

  def transaction_fixture(user, attrs \\ %{}) do
    Banking.ensure_default_categories(user.id)
    category = Banking.get_uncategorized_category(user.id)
    stmt = statement_fixture(user)

    date = Map.get(attrs, :date, ~D[2026-01-15])

    row = %{
      date: date,
      description: Map.get(attrs, :description, "Transação #{System.unique_integer()}"),
      amount: Decimal.new(Map.get(attrs, :amount, "-50.00")),
      type: Map.get(attrs, :type, "debit"),
      bank_statement_id: Map.get(attrs, :bank_statement_id, stmt.id),
      user_id: user.id,
      category_id: Map.get(attrs, :category_id, category.id)
    }

    {1, _} = Banking.bulk_insert_transactions([row])

    user.id
    |> Banking.list_transactions(
      search: row.description,
      date_from: date,
      date_to: date
    )
    |> List.first()
  end

  def transactions_fixture(user, rows) when is_list(rows) do
    Banking.ensure_default_categories(user.id)
    category = Banking.get_uncategorized_category(user.id)
    stmt = statement_fixture(user)

    prepared =
      Enum.map(rows, fn attrs ->
        %{
          date: Map.get(attrs, :date, ~D[2026-01-15]),
          description: Map.get(attrs, :description, "Txn #{System.unique_integer()}"),
          amount: Decimal.new(to_string(Map.get(attrs, :amount, "-50.00"))),
          type: Map.get(attrs, :type, "debit"),
          bank_statement_id: Map.get(attrs, :bank_statement_id, stmt.id),
          user_id: user.id,
          category_id: Map.get(attrs, :category_id, category.id)
        }
      end)

    {_n, _} = Banking.bulk_insert_transactions(prepared)
    Banking.list_transactions(user.id)
  end

  def goal_fixture(user, attrs \\ %{}) do
    base = %{
      type: "expense_limit",
      target_value: "1000.00",
      user_id: user.id
    }

    attrs = Map.merge(base, attrs)
    changeset = Grana.Banking.FinancialGoal.changeset(%Grana.Banking.FinancialGoal{}, attrs)
    {:ok, goal} = Repo.insert(changeset)
    goal
  end

  def category_rule_fixture(user, category, attrs \\ %{}) do
    base = %{
      pattern: "fixture-#{System.unique_integer()}",
      category_id: category.id,
      user_id: user.id
    }

    attrs = Map.merge(base, attrs)
    changeset = Grana.Banking.CategoryRule.changeset(%Grana.Banking.CategoryRule{}, attrs)
    {:ok, rule} = Repo.insert(changeset)
    rule
  end
end
