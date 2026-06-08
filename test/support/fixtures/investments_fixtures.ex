defmodule Grana.InvestmentsFixtures do
  @moduledoc """
  Helpers de fixture para o contexto Investments.
  Usa diretamente Investments/Repo — não mexe em lib/.
  """

  alias Grana.Investments

  def institution_fixture(user, attrs \\ %{}) do
    base = %{
      name: "Inst #{System.unique_integer()}",
      user_id: user.id
    }

    attrs = Map.merge(base, attrs)
    {:ok, inst} = Investments.create_institution(attrs)
    inst
  end

  def b3_institution(user), do: Investments.ensure_b3_institution(user.id)

  def statement_fixture(user, institution, attrs \\ %{}) do
    base = %{
      filename: "fixture-#{System.unique_integer()}.xlsx",
      status: "completed",
      user_id: user.id,
      institution_id: institution.id
    }

    attrs = Map.merge(base, attrs)
    {:ok, stmt} = Investments.create_statement(attrs)
    stmt
  end

  def transaction_fixture(user, attrs \\ %{}) do
    inst = b3_institution(user)
    stmt = statement_fixture(user, inst)

    date = Map.get(attrs, :date, ~D[2026-01-15])
    asset_name = Map.get(attrs, :asset_name, "ATIVO #{System.unique_integer()}")

    row = %{
      date: date,
      asset_name: asset_name,
      asset_ticker: Map.get(attrs, :asset_ticker),
      asset_type: Map.get(attrs, :asset_type, "acao"),
      operation: Map.get(attrs, :operation, "compra"),
      quantity: Decimal.new(to_string(Map.get(attrs, :quantity, "10"))),
      unit_price: Decimal.new(to_string(Map.get(attrs, :unit_price, "20.00"))),
      total_amount: Decimal.new(to_string(Map.get(attrs, :total_amount, "200.00"))),
      fees: Decimal.new(to_string(Map.get(attrs, :fees, "0"))),
      user_id: user.id,
      statement_id: Map.get(attrs, :statement_id, stmt.id),
      institution_id: inst.id
    }

    {1, _} = Investments.bulk_insert_transactions([row])

    user.id
    |> Investments.list_transactions(search: asset_name, date_from: date, date_to: date)
    |> List.first()
  end

  def transactions_fixture(user, rows) when is_list(rows) do
    inst = b3_institution(user)
    stmt = statement_fixture(user, inst)

    prepared =
      Enum.map(rows, fn attrs ->
        %{
          date: Map.get(attrs, :date, ~D[2026-01-15]),
          asset_name: Map.get(attrs, :asset_name, "ATIVO #{System.unique_integer()}"),
          asset_type: Map.get(attrs, :asset_type, "acao"),
          operation: Map.get(attrs, :operation, "compra"),
          quantity: Decimal.new(to_string(Map.get(attrs, :quantity, "10"))),
          unit_price: Decimal.new(to_string(Map.get(attrs, :unit_price, "20.00"))),
          total_amount: Decimal.new(to_string(Map.get(attrs, :total_amount, "200.00"))),
          fees: Decimal.new(to_string(Map.get(attrs, :fees, "0"))),
          user_id: user.id,
          statement_id: stmt.id,
          institution_id: inst.id
        }
      end)

    {_n, _} = Investments.bulk_insert_transactions(prepared)
    Investments.list_transactions(user.id)
  end
end
