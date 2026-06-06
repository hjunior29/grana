defmodule Grana.PlatformImportTest do
  use Grana.DataCase, async: true

  import Grana.AccountsFixtures

  alias Grana.Banking
  alias Grana.Banking.CsvExporter
  alias Grana.Investments
  alias Grana.Investments.CsvExporter, as: InvCsvExporter
  alias Grana.PlatformImport

  describe "banking round-trip" do
    test "export then import recreates transactions preserving bank and category" do
      source = user_fixture()
      Banking.ensure_default_categories(source.id)
      saude = find_category(source.id, "Saúde")

      {:ok, stmt} =
        Banking.create_statement(%{
          bank: "nubank",
          filename: "orig.csv",
          statement_type: "extrato",
          user_id: source.id
        })

      Banking.bulk_insert_transactions([
        %{
          date: ~D[2026-01-10],
          description: "DROGASIL",
          amount: Decimal.new("-28.72"),
          type: "debit",
          bank_statement_id: stmt.id,
          user_id: source.id,
          category_id: saude.id
        },
        %{
          date: ~D[2026-01-11],
          description: "SALARIO",
          amount: Decimal.new("5000.00"),
          type: "credit",
          bank_statement_id: stmt.id,
          user_id: source.id,
          category_id: nil
        }
      ])

      csv = source.id |> Banking.list_transactions() |> CsvExporter.generate()

      dest = user_fixture()
      assert {:ok, %{transaction_count: 2}} = PlatformImport.process(csv, dest.id, "export.csv")

      [drogasil, salario] = Banking.list_transactions(dest.id) |> Enum.sort_by(& &1.date)

      assert drogasil.description == "DROGASIL"
      assert drogasil.type == "debit"
      assert Decimal.equal?(Decimal.abs(drogasil.amount), Decimal.new("28.72"))
      assert drogasil.bank_statement.bank == "nubank"
      assert drogasil.bank_statement.statement_type == "extrato"
      assert drogasil.category.name == "Saúde"

      assert salario.type == "credit"
      assert Decimal.equal?(salario.amount, Decimal.new("5000.00"))
      assert salario.bank_statement.bank == "nubank"
    end

    test "re-importing the same export does not duplicate" do
      source = user_fixture()
      Banking.ensure_default_categories(source.id)

      {:ok, stmt} =
        Banking.create_statement(%{
          bank: "bradesco",
          filename: "orig.csv",
          statement_type: "fatura",
          user_id: source.id
        })

      Banking.bulk_insert_transactions([
        %{
          date: ~D[2026-02-01],
          description: "NETFLIX",
          amount: Decimal.new("-44.90"),
          type: "debit",
          bank_statement_id: stmt.id,
          user_id: source.id
        }
      ])

      csv = source.id |> Banking.list_transactions() |> CsvExporter.generate()
      dest = user_fixture()

      assert {:ok, %{transaction_count: 1}} = PlatformImport.process(csv, dest.id, "export.csv")
      assert {:ok, %{transaction_count: 0}} = PlatformImport.process(csv, dest.id, "export.csv")

      assert length(Banking.list_transactions(dest.id)) == 1
    end

    test "reads the old export format (no bank column) defaulting bank to importado" do
      csv = """
      Data;Descrição;Valor;Tipo;Categoria\r
      29/11/2025;DROGASIL 2515;28,72;Despesa;Saúde\r
      28/11/2025;Pagamento recebido;100,00;Receita;Pagamentos\r
      """

      dest = user_fixture()
      assert {:ok, %{transaction_count: 2}} = PlatformImport.process(csv, dest.id, "antigo.csv")

      txns = Banking.list_transactions(dest.id)
      assert Enum.all?(txns, &(&1.bank_statement.bank == "importado"))
      assert Enum.any?(txns, &(&1.type == "debit"))
      assert Enum.any?(txns, &(&1.type == "credit"))
    end
  end

  describe "investments round-trip" do
    test "export then import recreates investment transactions reversing labels" do
      source = user_fixture()
      {:ok, inst} = Investments.create_institution(%{name: "B3", slug: "b3", user_id: source.id})

      {:ok, stmt} =
        Investments.create_statement(%{
          filename: "inv.csv",
          user_id: source.id,
          institution_id: inst.id
        })

      Investments.bulk_insert_transactions([
        %{
          date: ~D[2026-03-05],
          asset_name: "PETROBRAS PN",
          asset_ticker: "PETR4",
          asset_type: "acao",
          operation: "compra",
          quantity: Decimal.new("100"),
          unit_price: Decimal.new("38.50"),
          total_amount: Decimal.new("3850.00"),
          fees: Decimal.new("1.20"),
          user_id: source.id,
          statement_id: stmt.id,
          institution_id: inst.id
        }
      ])

      csv = source.id |> Investments.list_transactions() |> InvCsvExporter.generate()

      dest = user_fixture()

      assert {:ok, %{transaction_count: 1}} =
               PlatformImport.process(csv, dest.id, "inv-export.csv")

      [t] = Investments.list_transactions(dest.id)
      assert t.asset_name == "PETROBRAS PN"
      assert t.asset_type == "acao"
      assert t.operation == "compra"
      assert t.institution.name == "B3"
      assert Decimal.equal?(t.total_amount, Decimal.new("3850.00"))
    end
  end

  defp find_category(user_id, name) do
    Banking.list_categories(user_id) |> Enum.find(&(&1.name == name))
  end
end
