defmodule Grana.Banking.CardPaymentDetectionTest do
  use Grana.DataCase

  import Grana.AccountsFixtures

  alias Grana.Banking

  setup do
    user = user_fixture()
    Banking.ensure_default_categories(user.id)
    category = Banking.get_uncategorized_category(user.id)

    statement = fn bank, type, period ->
      {:ok, statement} =
        Banking.create_statement(%{
          bank: bank,
          filename: "#{bank}-#{type}.csv",
          statement_type: type,
          period_start: period && elem(period, 0),
          period_end: period && elem(period, 1),
          user_id: user.id
        })

      statement
    end

    %{
      user: user,
      category: category,
      nubank_bill: statement.("nubank", "fatura", {~D[2026-01-03], ~D[2026-02-02]}),
      bradesco_bill: statement.("bradesco", "fatura", {~D[2026-01-05], ~D[2026-02-04]}),
      bradesco_account: statement.("bradesco", "extrato", nil)
    }
  end

  defp insert(ctx, statement, rows) do
    Banking.bulk_insert_transactions(
      for {date, amount, description} <- rows do
        amount = Decimal.new(amount)

        %{
          date: date,
          amount: amount,
          type: if(Decimal.negative?(amount), do: "debit", else: "credit"),
          description: description,
          bank_statement_id: statement.id,
          user_id: ctx.user.id,
          category_id: ctx.category.id
        }
      end
    )
  end

  test "card bill payments are no income, and a bill refund discounts the spending", ctx do
    insert(ctx, ctx.nubank_bill, [
      {~D[2026-01-09], "3150.40", "Pagamento recebido"},
      {~D[2026-01-10], "-300.00", "Supermercado"}
    ])

    insert(ctx, ctx.bradesco_bill, [
      {~D[2026-01-10], "2875.60", "PAGTO. POR DEB EM C/C"},
      {~D[2026-01-12], "-200.00", "Posto"},
      {~D[2026-01-20], "21.50", "AMAZON BR"}
    ])

    insert(ctx, ctx.bradesco_account, [
      {~D[2026-01-05], "5000.00", "Pix Recebido - Empresa Exemplo Ltda"},
      {~D[2026-01-09], "-3150.40", "Pagto Cobranca - nu Pagamentos sa"},
      {~D[2026-01-10], "-2875.60", "Gasto c Credito"}
    ])

    assert :ok = Banking.detect_internal_transfers(ctx.user.id)

    internal =
      ctx.user.id
      |> Banking.list_transactions()
      |> Enum.filter(& &1.is_internal_transfer)
      |> Enum.map(& &1.description)
      |> Enum.sort()

    assert internal == [
             "Gasto c Credito",
             "PAGTO. POR DEB EM C/C",
             "Pagamento recebido",
             "Pagto Cobranca - nu Pagamentos sa"
           ]

    summary = Banking.monthly_summary(ctx.user.id, 2026, 1)
    assert Decimal.equal?(summary.total_income, Decimal.new("5000.00"))
    assert Decimal.equal?(summary.total_expenses, Decimal.new("478.50"))
  end

  test "the user's choice wins over the detection", ctx do
    insert(ctx, ctx.nubank_bill, [{~D[2026-01-09], "3150.40", "Pagamento recebido"}])
    [payment] = Banking.list_transactions(ctx.user.id)

    {:ok, :single} = Banking.set_transaction_internal(ctx.user.id, payment.id, false)
    assert :ok = Banking.detect_internal_transfers(ctx.user.id)

    refute Banking.get_transaction!(payment.id, ctx.user.id).is_internal_transfer
  end
end
