defmodule Grana.Banking.MerchantsTest do
  use Grana.DataCase, async: true

  import Grana.AccountsFixtures
  import Grana.BankingFixtures

  alias Grana.Banking.Merchants
  alias Grana.Banking.PrivateNames

  setup do
    user = user_fixture()

    transactions_fixture(user, [
      %{
        description: "Pagamento de boleto efetuado - UNIMED BH",
        amount: "-450.00",
        date: ~D[2026-03-05]
      },
      %{
        description: "Pagamento de boleto efetuado - UNIMED BH",
        amount: "-450.00",
        date: ~D[2026-04-05]
      },
      %{description: "DROGASIL 2515", amount: "-30.00", date: ~D[2026-04-10]},
      %{
        description: "Transferência recebida pelo Pix - EMPRESA X",
        amount: "5000.00",
        type: "credit",
        date: ~D[2026-04-01]
      },
      %{description: "AB", amount: "-1.00", date: ~D[2026-04-02]}
    ])

    %{user: user}
  end

  test "list/2 groups by merchant, most frequent first, with category and total", %{user: user} do
    assert [unimed | rest] = Merchants.list(user.id)

    assert %{name: "UNIMED BH", category: "Sem Categoria", count: 2, last_date: ~D[2026-04-05]} =
             unimed

    assert Decimal.equal?(unimed.total, Decimal.new("900.00"))
    assert "DROGASIL 2515" in Enum.map(rest, & &1.name)
  end

  test "list/2 filters by type, window and limit", %{user: user} do
    assert [%{name: "EMPRESA X"}] = Merchants.list(user.id, type: "credit")
    assert Merchants.list(user.id, limit: 1) |> length() == 1
    assert Merchants.list(user.id, months: 1) == []
  end

  test "list/2 belongs to the user", %{user: _user} do
    assert Merchants.list(user_fixture().id) == []
  end

  test "names/1 returns the merchant part of each description", %{user: user} do
    names = Merchants.names(user.id)
    assert "UNIMED BH" in names
    assert "EMPRESA X" in names
    refute Enum.any?(names, &String.contains?(&1, "Pagamento de boleto"))
  end

  test "PrivateNames.pattern/1 matches known names regardless of case; short ones are skipped", %{
    user: user
  } do
    pattern = PrivateNames.pattern(user.id)

    assert PrivateNames.split("Você pagou a Unimed BH e a Drogasil 2515 (AB).", pattern) == [
             {"Você pagou a ", false},
             {"Unimed BH", true},
             {" e a ", false},
             {"Drogasil 2515", true},
             {" (AB).", false}
           ]

    assert PrivateNames.split("Nada aqui", pattern) == [{"Nada aqui", false}]
    assert PrivateNames.split("x", nil) == [{"x", false}]
    assert PrivateNames.pattern(user_fixture().id) == nil
  end
end
