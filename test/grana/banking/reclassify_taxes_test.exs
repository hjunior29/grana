defmodule Grana.Banking.ReclassifyTaxesTest do
  use Grana.DataCase

  import Grana.AccountsFixtures

  alias Grana.Banking
  alias Grana.Banking.Transaction

  setup do
    user = user_fixture()
    Banking.ensure_default_categories(user.id)
    cats = Banking.list_categories(user.id) |> Map.new(&{&1.name, &1})

    {:ok, stmt} =
      Banking.create_statement(%{
        bank: "nubank",
        filename: "ext.csv",
        statement_type: "extrato",
        user_id: user.id
      })

    %{user: user, cats: cats, stmt: stmt}
  end

  defp insert_txn(ctx, desc, cat) do
    {1, _} =
      Banking.bulk_insert_transactions([
        %{
          date: ~D[2026-02-10],
          description: desc,
          amount: Decimal.new("-50.00"),
          type: "debit",
          bank_statement_id: ctx.stmt.id,
          user_id: ctx.user.id,
          category_id: cat.id,
          is_internal_transfer: false
        }
      ])

    Repo.get_by!(Transaction, description: desc, user_id: ctx.user.id)
  end

  test "move impostos inequívocos para Impostos e Taxas e mantém o resto", ctx do
    uncat = ctx.cats["Sem Categoria"]
    impostos = ctx.cats["Impostos e Taxas"]

    iof = insert_txn(ctx, "IOF de Claude Ai", uncat)
    multa = insert_txn(ctx, "Multa de atraso", uncat)
    mercado = insert_txn(ctx, "Mercado Livre compra", ctx.cats["Compras"])

    assert {:ok, 2} = Banking.reclassify_taxes(ctx.user.id)

    assert Banking.get_transaction!(iof.id, ctx.user.id).category_id == impostos.id
    assert Banking.get_transaction!(multa.id, ctx.user.id).category_id == impostos.id
    assert Banking.get_transaction!(mercado.id, ctx.user.id).category_id == ctx.cats["Compras"].id

    # idempotente
    assert {:ok, 0} = Banking.reclassify_taxes(ctx.user.id)
  end
end
