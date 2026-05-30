defmodule Grana.InvestmentsTest do
  use Grana.DataCase

  alias Grana.Investments

  import Grana.AccountsFixtures

  setup do
    user = user_fixture()
    institution = ensure_test_institution(user.id)
    %{user: user, institution: institution}
  end

  defp ensure_test_institution(user_id) do
    Investments.ensure_b3_institution(user_id)
  end

  describe "delete_statements/2 authorization" do
    test "delete_statements with correct user_id deletes the statements", %{
      user: user,
      institution: institution
    } do
      {:ok, stmt} =
        Investments.create_statement(%{
          filename: "test.csv",
          user_id: user.id,
          institution_id: institution.id
        })

      assert {1, _} = Investments.delete_statements([stmt.id], user.id)
      assert Investments.list_statements(user.id) == []
    end

    test "delete_statements with wrong user_id does not delete the statements", %{
      user: user,
      institution: institution
    } do
      other_user = user_fixture()

      {:ok, stmt} =
        Investments.create_statement(%{
          filename: "test.csv",
          user_id: user.id,
          institution_id: institution.id
        })

      assert {0, _} = Investments.delete_statements([stmt.id], other_user.id)
      assert length(Investments.list_statements(user.id)) == 1
    end

    test "get_statement! with wrong user_id raises", %{user: user, institution: institution} do
      other_user = user_fixture()

      {:ok, stmt} =
        Investments.create_statement(%{
          filename: "test.csv",
          user_id: user.id,
          institution_id: institution.id
        })

      assert_raise Ecto.NoResultsError, fn ->
        Investments.get_statement!(stmt.id, other_user.id)
      end
    end

    test "get_statement! with correct user_id returns the statement", %{
      user: user,
      institution: institution
    } do
      {:ok, stmt} =
        Investments.create_statement(%{
          filename: "test.csv",
          user_id: user.id,
          institution_id: institution.id
        })

      found = Investments.get_statement!(stmt.id, user.id)
      assert found.id == stmt.id
    end
  end

  describe "lucro realizado (preço médio)" do
    test "usa custo médio ponderado, não vendas-compras agregado", %{
      user: user,
      institution: institution
    } do
      {:ok, stmt} =
        Investments.create_statement(%{
          filename: "t.csv",
          user_id: user.id,
          institution_id: institution.id
        })

      base = %{
        user_id: user.id,
        statement_id: stmt.id,
        institution_id: institution.id,
        asset_name: "PETR4",
        asset_ticker: "PETR4",
        asset_type: "acao"
      }

      Investments.bulk_insert_transactions([
        Map.merge(base, %{
          date: ~D[2026-01-01],
          operation: "compra",
          quantity: Decimal.new(10),
          unit_price: Decimal.new(10),
          total_amount: Decimal.new(100)
        }),
        Map.merge(base, %{
          date: ~D[2026-02-01],
          operation: "compra",
          quantity: Decimal.new(10),
          unit_price: Decimal.new(20),
          total_amount: Decimal.new(200)
        }),
        Map.merge(base, %{
          date: ~D[2026-03-01],
          operation: "venda",
          quantity: Decimal.new(10),
          unit_price: Decimal.new(25),
          total_amount: Decimal.new(250)
        })
      ])

      summary = Investments.portfolio_summary(user.id)
      asset = Enum.find(summary.proventos_by_asset, &(&1.ticker == "PETR4"))

      # custo médio = 15; venda de 10 @ 25 → lucro realizado (25-15)*10 = 100
      assert asset
      assert Decimal.equal?(asset.realized_profit, Decimal.new(100))
    end
  end
end
