defmodule Grana.Banking.MovementRulesTest do
  use Grana.DataCase

  import Grana.AccountsFixtures

  alias Grana.Banking

  setup do
    user = user_fixture()
    categories = Map.new(Banking.ensure_default_categories(user.id), &{&1.name, &1.id})

    {:ok, account} =
      Banking.create_statement(%{
        bank: "nubank",
        filename: "extrato.csv",
        statement_type: "extrato",
        user_id: user.id
      })

    %{user: user, categories: categories, account: account}
  end

  defp insert(ctx, rows) do
    Banking.bulk_insert_transactions(
      for {date, amount, description, category, identifier} <- rows do
        amount = Decimal.new(amount)

        %{
          date: date,
          amount: amount,
          type: if(Decimal.negative?(amount), do: "debit", else: "credit"),
          description: description,
          identifier: identifier,
          bank_statement_id: ctx.account.id,
          user_id: ctx.user.id,
          category_id: ctx.categories[category]
        }
      end
    )
  end

  test "money back from an investment nets the investments instead of being income", ctx do
    insert(ctx, [
      {~D[2026-03-02], "5000.00", "Transferência Recebida - Empresa Exemplo", "Salário", nil},
      {~D[2026-03-05], "-1000.00", "Aplicação RDB", "Investimentos", nil},
      {~D[2026-03-20], "300.00", "Resgate RDB", "Investimentos", nil}
    ])

    summary = Banking.monthly_summary(ctx.user.id, 2026, 3)
    assert Decimal.equal?(summary.total_income, 5000)
    assert Decimal.equal?(summary.total_investments, 700)
    assert summary.investment_count == 2
    assert Decimal.equal?(summary.balance, 4300)
  end

  test "money given back is a refund, written with or without accents", ctx do
    insert(ctx, [
      {~D[2026-03-02], "5000.00", "Transferência Recebida - Empresa Exemplo", "Salário", nil},
      {~D[2026-03-03], "-30.00", "Transferência enviada - Corretora Exemplo", "Compras", nil},
      {~D[2026-03-03], "30.00", "Transferência devolvida - Corretora Exemplo", "Compras", nil},
      {~D[2026-03-04], "-90.48", "Pix Qrcode Est - Cinema Centro", "Lazer", nil},
      {~D[2026-03-06], "90.48", "Devolucao Pix - Cinema Centro", "Lazer", nil},
      {~D[2026-03-07], "-50.00", "Compra no débito - Mercado", "Alimentação", nil},
      {~D[2026-03-07], "2.35", "Ajuste de compra no débito", "Alimentação", nil}
    ])

    summary = Banking.monthly_summary(ctx.user.id, 2026, 3)
    assert Decimal.equal?(summary.total_income, 5000)
    assert Decimal.equal?(summary.total_expenses, Decimal.new("47.65"))
  end

  test "an operation and its reversal under the same identifier are left out, a Pix on credit is not",
       ctx do
    reversed = "00000000-0000-4000-8000-000000000002"
    pix_on_credit = "00000000-0000-4000-8000-000000000001"

    insert(ctx, [
      {~D[2026-03-02], "-187.20", "Transferência enviada pelo Pix - Orgao Exemplo", "Transporte",
       reversed},
      {~D[2026-03-02], "187.20", "Estorno - Transferência enviada pelo Pix - Orgao Exemplo",
       "Transporte", reversed},
      {~D[2026-03-05], "75.00",
       "Valor adicionado na conta por cartão de crédito - Valor adicionado para Pix no Crédito",
       "Transferências", pix_on_credit},
      {~D[2026-03-05], "-75.00", "Transferência enviada pelo Pix - Fulano", "Compras",
       pix_on_credit}
    ])

    assert :ok = Banking.detect_internal_transfers(ctx.user.id)

    internal =
      ctx.user.id
      |> Banking.list_transactions()
      |> Map.new(&{&1.description, &1.is_internal_transfer})

    assert internal["Transferência enviada pelo Pix - Orgao Exemplo"]
    assert internal["Estorno - Transferência enviada pelo Pix - Orgao Exemplo"]

    assert internal[
             "Valor adicionado na conta por cartão de crédito - Valor adicionado para Pix no Crédito"
           ]

    refute internal["Transferência enviada pelo Pix - Fulano"]
  end
end
