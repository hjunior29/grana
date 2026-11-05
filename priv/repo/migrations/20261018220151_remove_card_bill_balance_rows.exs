defmodule Grana.Repo.Migrations.RemoveCardBillBalanceRows do
  use Ecto.Migration

  # Bill rows that were never movements: the previous bill's balance the Bradesco CSV
  # repeats ("SALDO ANTERIOR", read as spending) and Nubank's zero rows ("Encerramento
  # de dívida"). The parsers drop them now. The bill payments themselves turn into
  # internal transfers on the next detection (`Grana.Banking.detect_internal_transfers/1`).
  def up do
    execute """
    DELETE FROM transactions
    WHERE bank_statement_id IN (SELECT id FROM bank_statements WHERE statement_type = 'fatura')
      AND (description LIKE 'SALDO ANTERIOR%' OR amount = 0)
    """

    execute """
    UPDATE bank_statements
    SET total_transactions =
      (SELECT COUNT(*) FROM transactions t WHERE t.bank_statement_id = bank_statements.id)
    WHERE statement_type = 'fatura'
    """
  end

  def down, do: :ok
end
