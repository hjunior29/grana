defmodule Grana.Banking.Parsers.NubankFaturaTest do
  use ExUnit.Case, async: true

  alias Grana.Banking.Parsers.NubankFatura

  test "parses charges as debit" do
    csv = "date,title,amount\n2026-01-28,Google One,96.99\n"
    [txn] = NubankFatura.parse(csv)
    assert txn.type == "debit"
    assert Decimal.compare(txn.amount, Decimal.new("-96.99")) == :eq
  end

  test "parses payments as credit" do
    csv = "date,title,amount\n2026-01-26,Pagamento recebido,-100.00\n"
    [txn] = NubankFatura.parse(csv)
    assert txn.type == "credit"
    assert Decimal.compare(txn.amount, Decimal.new("100.00")) == :eq
  end

  test "parses ISO dates" do
    csv = "date,title,amount\n2026-01-15,Apple.Com/Bill,14.90\n"
    [txn] = NubankFatura.parse(csv)
    assert txn.date == ~D[2026-01-15]
  end

  test "strips parcela from description" do
    csv = "date,title,amount\n2026-01-10,Airbnb * Hmbep2hw9e - Parcela 1/2,468.89\n"
    [txn] = NubankFatura.parse(csv)
    assert txn.description == "Airbnb * Hmbep2hw9e"
    assert txn.original_description == "Airbnb * Hmbep2hw9e - Parcela 1/2"
  end

  test "handles quoted descriptions with escaped quotes" do
    csv = ~s(date,title,amount\n2026-01-21,"IOF de ""Replicate""",0.39\n)
    [txn] = NubankFatura.parse(csv)
    assert txn.description == ~s(IOF de "Replicate")
  end

  test "handles estornos as credit" do
    csv = ~s(date,title,amount\n2026-01-21,"Estorno de ""Mercadolivre*Rodautop""",-26.99\n)
    [txn] = NubankFatura.parse(csv)
    assert txn.type == "credit"
    assert Decimal.compare(txn.amount, Decimal.new("26.99")) == :eq
  end

  test "parses full example file" do
    content = File.read!("test/support/fixtures/examples/fatura-nubank.csv")
    result = NubankFatura.parse(content)
    assert length(result) == 8

    debits = Enum.filter(result, &(&1.type == "debit"))
    credits = Enum.filter(result, &(&1.type == "credit"))
    assert debits != []
    assert credits != []
  end

  test "skips zero rows" do
    csv =
      "date,title,amount\n2025-04-10,Encerramento de dívida,0.00\n2025-04-10,Juros de dívida encerrada,0.00\n2025-04-08,Pagamento recebido,-2410.55\n"

    assert [%{description: "Pagamento recebido"}] = NubankFatura.parse(csv)
  end
end
