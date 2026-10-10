defmodule Grana.OpenFinance.AlertsTest do
  use ExUnit.Case, async: true

  alias Grana.Money
  alias Grana.OpenFinance.{Account, Alerts}

  @today ~D[2026-10-10]

  defp card(attrs) do
    struct!(
      %Account{
        type: "CREDIT",
        subtype: "CREDIT_CARD",
        name: "MASTERCARD BLACK",
        balance: Decimal.new("350.00"),
        balance_due_date: ~D[2026-10-12]
      },
      attrs
    )
  end

  test "fatura com valor vencendo em até 5 dias" do
    assert [%{kind: :invoice_due, message: message}] = Alerts.list([card(%{})], @today)
    assert message == "Fatura Mastercard Black vence em 2 dia(s): R$ 350,00"
  end

  test "vence hoje" do
    [%{message: message}] = Alerts.list([card(%{balance_due_date: @today})], @today)
    assert message =~ "vence hoje"
  end

  test "fatura longe, zerada ou sem vencimento não alerta" do
    assert Alerts.list([card(%{balance_due_date: ~D[2026-10-20]})], @today) == []
    assert Alerts.list([card(%{balance: Decimal.new(0)})], @today) == []
    assert Alerts.list([card(%{balance: nil})], @today) == []
    assert Alerts.list([card(%{balance_due_date: nil})], @today) == []
    assert Alerts.list([card(%{balance_due_date: ~D[2026-10-01]})], @today) == []
  end

  test "saldo negativo em conta corrente ou poupança" do
    checking = %Account{type: "BANK", subtype: "CHECKING_ACCOUNT", balance: Decimal.new("-1")}
    savings = %Account{type: "BANK", subtype: "SAVINGS_ACCOUNT", balance: Decimal.new("-1")}

    assert [%{kind: :negative_balance, message: "Saldo negativo na conta corrente"}] =
             Alerts.list([checking], @today)

    assert [%{message: "Saldo negativo na poupança"}] = Alerts.list([savings], @today)
  end

  test "saldo positivo ou nulo não alerta" do
    ok = %Account{type: "BANK", subtype: "CHECKING_ACCOUNT", balance: Decimal.new("5")}
    unknown = %Account{type: "BANK", subtype: "CHECKING_ACCOUNT", balance: nil}
    assert Alerts.list([ok, unknown], @today) == []
  end

  describe "Money.format/2" do
    test "formata em reais, com milhar e sinal" do
      assert Money.format(Decimal.new("1234567.8")) == "R$ 1.234.567,80"
      assert Money.format(Decimal.new("-5")) == "-R$ 5,00"
      assert Money.format(nil) == "—"
      assert Money.format(Decimal.new("10"), "USD") == "USD 10,00"
    end
  end
end
