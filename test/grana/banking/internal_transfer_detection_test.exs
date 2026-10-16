defmodule Grana.Banking.InternalTransferDetectionTest do
  use Grana.DataCase

  import Grana.AccountsFixtures

  alias Grana.Accounts
  alias Grana.Banking
  alias Grana.Banking.Transaction

  @self_pix "Transferência enviada pelo Pix - Ana Costa Ramos - •••.555.444-•• - Nubank (0260) Agência: 1 Conta: 11112222-3"
  @other_pix "Transferência enviada pelo Pix - Joao Pereira Souza - •••.999.888-•• - BANCO INTER (0077) Agência: 1 Conta: 1-0"
  @other_pix2 "Transferência recebida pelo Pix - Joao Pereira Souza - •••.999.888-•• - BANCO C6 (0336) Agência: 1 Conta: 2-0"

  setup do
    user = user_fixture()

    {:ok, user} =
      Accounts.update_user_identity(user, %{name: "Ana Costa Ramos", cpf: "123.555.444-45"})

    Banking.ensure_default_categories(user.id)
    cat = Banking.get_uncategorized_category(user.id)

    {:ok, stmt} =
      Banking.create_statement(%{
        bank: "nubank",
        filename: "ext.csv",
        statement_type: "extrato",
        user_id: user.id
      })

    %{user: user, cat: cat, stmt: stmt}
  end

  defp insert_txn(ctx, desc, type) do
    {1, _} =
      Banking.bulk_insert_transactions([
        %{
          date: ~D[2026-02-10],
          description: desc,
          amount: Decimal.new("-100.00"),
          type: type,
          bank_statement_id: ctx.stmt.id,
          user_id: ctx.user.id,
          category_id: ctx.cat.id,
          is_internal_transfer: false
        }
      ])

    Repo.get_by!(Transaction, description: desc, user_id: ctx.user.id)
  end

  defp internal?(id, user_id), do: Banking.get_transaction!(id, user_id).is_internal_transfer

  test "identidade marca transferência do próprio titular como interna", ctx do
    mine = insert_txn(ctx, @self_pix, "debit")
    other = insert_txn(ctx, @other_pix, "debit")

    assert :ok = Banking.detect_internal_transfers(ctx.user.id)

    assert internal?(mine.id, ctx.user.id)
    refute internal?(other.id, ctx.user.id)
  end

  test "marcação manual aprende regra por contraparte e vale pras próximas", ctx do
    other = insert_txn(ctx, @other_pix, "debit")
    assert {:ok, :rule} = Banking.set_transaction_internal(ctx.user.id, other.id, true)
    assert internal?(other.id, ctx.user.id)

    # Outra transação da MESMA contraparte (mesmo CPF do meio) entra interna.
    other2 = insert_txn(ctx, @other_pix2, "credit")
    assert :ok = Banking.detect_internal_transfers(ctx.user.id)
    assert internal?(other2.id, ctx.user.id)
  end

  test "override externo do usuário vence a heurística de identidade", ctx do
    mine = insert_txn(ctx, @self_pix, "debit")
    assert :ok = Banking.detect_internal_transfers(ctx.user.id)
    assert internal?(mine.id, ctx.user.id)

    # Usuário diz que NÃO é interna → regra external sobrepõe a heurística.
    assert {:ok, :rule} = Banking.set_transaction_internal(ctx.user.id, mine.id, false)
    refute internal?(mine.id, ctx.user.id)

    # Re-rodar a detecção mantém externo (a regra continua vencendo).
    assert :ok = Banking.detect_internal_transfers(ctx.user.id)
    refute internal?(mine.id, ctx.user.id)
  end

  test "marcação manual sem contraparte (:single) sobrevive a novas detecções", ctx do
    # TED sem nome ou CPF da contraparte extraível
    txn = insert_txn(ctx, "TED ENVIADA 1234", "debit")
    assert :ok = Banking.detect_internal_transfers(ctx.user.id)
    refute internal?(txn.id, ctx.user.id)

    # Marca manualmente como interna -> :single
    assert {:ok, :single} = Banking.set_transaction_internal(ctx.user.id, txn.id, true)
    assert internal?(txn.id, ctx.user.id)

    # Nova importação / sync re-executa detect_internal_transfers -> marcação é mantida!
    assert :ok = Banking.detect_internal_transfers(ctx.user.id)
    assert internal?(txn.id, ctx.user.id)

    # Se desmarcar manualmente como externa -> :single
    assert {:ok, :single} = Banking.set_transaction_internal(ctx.user.id, txn.id, false)
    refute internal?(txn.id, ctx.user.id)

    # Nova detecção não volta a marcar
    assert :ok = Banking.detect_internal_transfers(ctx.user.id)
    refute internal?(txn.id, ctx.user.id)
  end
end
