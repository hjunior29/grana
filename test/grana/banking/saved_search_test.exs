defmodule Grana.Banking.SavedSearchTest do
  use Grana.DataCase

  alias Grana.Banking
  alias Grana.Banking.{SavedSearch, Search}

  import Grana.AccountsFixtures
  import Grana.BankingFixtures

  setup do
    %{user: user_fixture()}
  end

  describe "search_transactions/3" do
    test "filtra as transações do usuário pela busca", %{user: user} do
      transactions_fixture(user, [
        %{description: "UBER TRIP", amount: "-20.00"},
        %{description: "99 POP", amount: "-15.00"},
        %{description: "PADARIA", amount: "-8.00"}
      ])

      other = user_fixture()
      transaction_fixture(other, %{description: "UBER DE OUTRO"})

      {:ok, search} = Search.parse("(uber OR 99) AND amount > 10")

      descriptions =
        user.id
        |> Banking.search_transactions(search, sort_by: "amount", sort_dir: "desc")
        |> Enum.map(& &1.description)

      assert descriptions == ["UBER TRIP", "99 POP"]
    end

    test "recurrence usa as regras de fixa e variável", %{user: user} do
      [aluguel, _mercado] =
        transactions_fixture(user, [
          %{description: "ALUGUEL", amount: "-1500.00"},
          %{description: "MERCADO", amount: "-300.00"}
        ])
        |> Enum.sort_by(& &1.description)

      {:ok, _rule} = Banking.set_transaction_recurring_mode(user.id, aluguel.id, "fixed")

      {:ok, fixa} = Search.parse("recurrence:fixed")
      {:ok, variavel} = Search.parse("recurrence:variable")

      assert Enum.map(Banking.search_transactions(user.id, fixa), & &1.description) == ["ALUGUEL"]

      assert Enum.map(Banking.search_transactions(user.id, variavel), & &1.description) == [
               "MERCADO"
             ]
    end
  end

  describe "buscas salvas" do
    test "cria, lista em ordem alfabética e remove", %{user: user} do
      {:ok, transporte} =
        Banking.create_saved_search(user.id, %{"name" => " Transporte ", "query" => " uber "})

      {:ok, _} = Banking.create_saved_search(user.id, %{"name" => "Água", "query" => "sabesp"})

      assert transporte.name == "Transporte"
      assert transporte.query == "uber"
      assert Enum.map(Banking.list_saved_searches(user.id), & &1.name) == ["Água", "Transporte"]

      {:ok, _} = Banking.delete_saved_search(transporte)
      assert Enum.map(Banking.list_saved_searches(user.id), & &1.name) == ["Água"]
    end

    test "o nome é único por usuário", %{user: user} do
      {:ok, _} = Banking.create_saved_search(user.id, %{"name" => "Uber", "query" => "uber"})

      assert {:error, changeset} =
               Banking.create_saved_search(user.id, %{"name" => "Uber", "query" => "99"})

      assert "já existe uma busca com esse nome" in errors_on(changeset).name

      other = user_fixture()

      assert {:ok, _} =
               Banking.create_saved_search(other.id, %{"name" => "Uber", "query" => "uber"})
    end

    test "não salva busca inválida nem sem nome", %{user: user} do
      assert {:error, changeset} =
               Banking.create_saved_search(user.id, %{"name" => "", "query" => "(uber"})

      errors = errors_on(changeset)
      assert errors.name != []
      assert "Faltou fechar um parêntese." in errors.query
    end

    test "atualiza a busca e só acha as do próprio usuário", %{user: user} do
      {:ok, saved} = Banking.create_saved_search(user.id, %{"name" => "Uber", "query" => "uber"})

      assert {:ok, %SavedSearch{query: "uber OR 99"}} =
               Banking.update_saved_search(saved, %{"query" => "uber OR 99"})

      assert Banking.get_saved_search(user.id, saved.id).query == "uber OR 99"
      assert Banking.get_saved_search(user_fixture().id, saved.id) == nil
    end

    test "change_saved_search/2 devolve um changeset" do
      assert %Ecto.Changeset{} = Banking.change_saved_search(%SavedSearch{}, %{"query" => "x"})
    end
  end
end
