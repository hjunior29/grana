defmodule Grana.Banking.CardPaymentsTest do
  use ExUnit.Case, async: true

  alias Grana.Banking.CardPayments

  @nubank_bill {1, "fatura", "nubank"}
  @bradesco_bill {2, "fatura", "bradesco"}
  @nubank_account {3, "extrato", "nubank"}
  @bradesco_account {4, "extrato", "bradesco"}

  @bills [
    {"nubank", ~D[2026-01-03], ~D[2026-02-02]},
    {"bradesco", ~D[2026-01-05], ~D[2026-02-04]}
  ]

  defp txn(id, {statement_id, statement_type, bank}, date, amount, description) do
    %{
      id: id,
      date: date,
      amount: Decimal.new(amount),
      type: if(String.starts_with?(amount, "-"), do: "debit", else: "credit"),
      description: description,
      statement_id: statement_id,
      statement_type: statement_type,
      bank: bank
    }
  end

  defp internal(transactions, bills \\ @bills),
    do: transactions |> CardPayments.internal_ids(bills) |> Enum.sort()

  test "a payment on the bill is never income; a refund stays a credit" do
    transactions = [
      txn(1, @nubank_bill, ~D[2026-01-09], "3150.40", "Pagamento recebido"),
      txn(2, @bradesco_bill, ~D[2026-01-10], "2875.60", "PAGTO. POR DEB EM C/C"),
      txn(3, @nubank_bill, ~D[2026-01-12], "9.90", ~s(Estorno de "Streaming Exemplo")),
      txn(4, @bradesco_bill, ~D[2026-01-14], "21.50", "AMAZON BR"),
      txn(5, @nubank_bill, ~D[2026-01-15], "-39.90", "Streaming Exemplo")
    ]

    assert internal(transactions) == [1, 2]
  end

  test "pairs each payment with the debit that paid it, from any account" do
    transactions = [
      txn(1, @nubank_bill, ~D[2026-01-09], "3150.40", "Pagamento recebido"),
      txn(2, @bradesco_account, ~D[2026-01-09], "-3150.40", "Pagto Cobranca - nu Pagamentos sa"),
      txn(3, @nubank_bill, ~D[2026-01-20], "120.30", "Pagamento recebido"),
      txn(4, @bradesco_account, ~D[2026-01-19], "-120.30", "Pix Qrcode Est - nu Pagamentos S/a"),
      txn(5, @bradesco_bill, ~D[2026-01-10], "2875.60", "PAGTO. POR DEB EM C/C"),
      txn(6, @bradesco_account, ~D[2026-01-10], "-2875.60", "Gasto c Credito"),
      txn(7, @bradesco_account, ~D[2026-01-10], "-2875.60", "Pix Enviado - Loja de Moveis")
    ]

    assert internal(transactions) == [1, 2, 3, 4, 5, 6]
  end

  test "a debit of the same amount that does not name the payment needs the same day" do
    transactions = [
      txn(1, @nubank_bill, ~D[2026-01-26], "50.00", "Pagamento recebido"),
      txn(
        2,
        @nubank_account,
        ~D[2026-01-28],
        "-50.00",
        "Transferência enviada pelo Pix - Fulano"
      ),
      txn(3, @nubank_bill, ~D[2026-01-27], "80.00", "Pagamento recebido"),
      txn(
        4,
        @nubank_account,
        ~D[2026-01-27],
        "-80.00",
        "Transferência enviada pelo Pix - Ciclano"
      )
    ]

    assert internal(transactions) == [1, 3, 4]
  end

  test "an account payment without its bill credit counts when a bill of the issuer was imported" do
    transactions = [
      # paid right after the January bill closed; its credit would be on February's bill
      txn(1, @nubank_account, ~D[2026-02-05], "-1540.10", "Pagamento de fatura"),
      # long before any imported bill: the only record of that month's spending
      txn(2, @nubank_account, ~D[2025-10-05], "-1270.45", "Pagamento de fatura"),
      txn(3, @bradesco_account, ~D[2026-02-06], "-655.80", "Pagto Cobranca - nu Pagamentos sa"),
      txn(4, @bradesco_account, ~D[2026-02-10], "-930.75", "Gasto c Credito")
    ]

    assert internal(transactions) == [1, 3, 4]
    assert internal(transactions, [{"nubank", ~D[2026-01-03], ~D[2026-02-02]}]) == [1, 3]
  end

  test "a Pix on credit: the card's money is never income, the Pix is spent on the bill" do
    funding =
      "Valor adicionado na conta por cartão de crédito - Valor adicionado para Pix no Crédito"

    transactions = [
      txn(1, @nubank_account, ~D[2026-01-26], "20.00", funding),
      txn(
        2,
        @nubank_account,
        ~D[2026-01-26],
        "-20.00",
        "Transferência enviada pelo Pix - Fulano"
      ),
      # before the imported bills: the Pix is the only record of the purchase
      txn(3, @nubank_account, ~D[2025-06-10], "85.00", funding),
      txn(
        4,
        @nubank_account,
        ~D[2025-06-10],
        "-106.00",
        "Transferência enviada pelo Pix - Ciclano"
      )
    ]

    assert internal(transactions) == [1, 2, 3]
  end

  test "bill_credit?/1 and account_payment?/1" do
    for description <- ["Pagamento recebido", "PAGTO. POR DEB EM C/C", "PAGAMENTO EFETUADO"] do
      assert CardPayments.bill_credit?(description), description
    end

    for description <- [~s(Estorno de "Pg *Loja Exemplo"), "PAG*JoseDaSilva", "AMAZON BR"] do
      refute CardPayments.bill_credit?(description), description
    end

    for description <- [
          "Pagamento de fatura",
          "Pagamento da fatura - Cartão Nubank",
          "Gasto c Credito",
          "PAGTO ELETRON COBRANCA - NU PAGAMENTOS SA",
          "Pagamento de boleto efetuado - NU PAGAMENTOS SA"
        ] do
      assert CardPayments.account_payment?(description), description
    end

    for description <- [
          "Transferência enviada pelo Pix - Fulano - NU PAGAMENTOS - IP (0260) Agência: 1",
          "Pagto Cobranca - Plano de Saude Exemplo Ltda"
        ] do
      refute CardPayments.account_payment?(description), description
    end
  end
end
