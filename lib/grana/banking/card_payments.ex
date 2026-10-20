defmodule Grana.Banking.CardPayments do
  @moduledoc """
  Credit card bill payments in the user's statements. A payment shows up twice, on the
  same day and with the same amount: as a credit on the bill ("Pagamento recebido",
  "PAGTO. POR DEB EM C/C") and as a debit on the account that paid it ("Pagamento de
  fatura", "Gasto c Credito", a boleto or a Pix to the issuer). Neither side is income
  nor spending, the spending is the purchases on the bill, so `internal_ids/2` hands both
  to `Grana.Banking.detect_internal_transfers/1`.

  The same goes for a Pix paid with the card ("Pix no Crédito"): the card puts the money
  in the account right before the Pix leaves it, and the bill charges the purchase.
  """

  # Issuers that receive the bill as a boleto or Pix from another bank, by how the
  # paying account names them.
  @issuers [{"nu pagamentos", "nubank"}, {"nubank", "nubank"}]

  @account_patterns [
    "pagamento de fatura",
    "pagamento da fatura",
    "pagto fatura",
    "pgto fatura",
    "pag fatura",
    "gasto c credito",
    "gastos cartao",
    "gastos cartoes",
    "gasto cartao",
    "gastos com cartao"
  ]

  @boleto_patterns ["pagto eletron", "pagto cobranca", "pagamento de boleto"]

  # A payment's two sides carry the same date; the margin covers a weekend between the
  # debit and the bill crediting it.
  @pair_days 3

  # How far the bill a payment settles can close before it (due date ~10 days after
  # closing, plus a late payment) or after it (an early payment of the open bill).
  @closed_before_days 40
  @closes_after_days 31

  @doc """
  Ids of the transactions that are card bill payments or Pix on credit. Takes every
  transaction of the user as maps with `:id`, `:date`, `:amount`, `:type`,
  `:description`, `:statement_id`, `:statement_type` and `:bank`, and the imported bills
  as `{bank, period_start, period_end}`.
  """
  def internal_ids(transactions, bills) do
    {bill_side, account_side} = Enum.split_with(transactions, &(&1.statement_type == "fatura"))
    {debits, credits} = Enum.split_with(account_side, &(&1.type == "debit"))

    bill_payments =
      Enum.filter(bill_side, &(&1.type == "credit" and bill_credit?(&1.description)))

    paid = pair(bill_payments, debits)
    unpaired = Enum.reject(debits, &MapSet.member?(paid, &1.id))

    Enum.map(bill_payments, & &1.id) ++
      MapSet.to_list(paid) ++
      for(debit <- unpaired, settles_imported_bill?(debit, bills), do: debit.id) ++
      pix_on_credit(credits, unpaired, bills)
  end

  @doc "A credit on a bill that pays it, unlike a refund (which discounts the spending)."
  def bill_credit?(description) do
    Regex.match?(~r/^(pagamento|pagto|pgto)\b/, normalize(description))
  end

  @doc "A debit on an account that pays a card bill, by its description alone."
  def account_payment?(description) do
    text = normalize(description)

    Enum.any?(@account_patterns, &String.contains?(text, &1)) or
      (Enum.any?(@boleto_patterns, &String.contains?(text, &1)) and issuer(text) != nil)
  end

  # Each bill payment takes the closest unused debit of the same amount, preferring one
  # that names the payment or the issuer. Without that, only the same or the next day
  # counts: an unrelated Pix of a round amount should not pass for the payment.
  defp pair(bill_payments, debits) do
    by_cents = Enum.group_by(debits, &cents(&1.amount))

    bill_payments
    |> Enum.sort_by(& &1.date, Date)
    |> Enum.reduce(MapSet.new(), fn payment, used ->
      by_cents
      |> Map.get(cents(payment.amount), [])
      |> Enum.reject(&MapSet.member?(used, &1.id))
      |> Enum.map(fn debit ->
        {debit, abs(Date.diff(debit.date, payment.date)), payment_like?(debit.description)}
      end)
      |> Enum.filter(fn {_debit, days, named?} -> days <= if(named?, do: @pair_days, else: 1) end)
      |> Enum.min_by(fn {_debit, days, named?} -> {not named?, days} end, fn -> nil end)
      |> case do
        nil -> used
        {debit, _days, _named?} -> MapSet.put(used, debit.id)
      end
    end)
  end

  # A payment whose bill-side credit was not imported (it sits on the next bill) is
  # still a transfer when a bill of its issuer was open then or had just closed: the
  # purchases on it are the spending.
  defp settles_imported_bill?(debit, bills) do
    issuer_bank = issuer(normalize(debit.description)) || debit.bank
    issuer_bills = Enum.filter(bills, &(elem(&1, 0) == issuer_bank))

    account_payment?(debit.description) and
      (bill_covers?(bills, issuer_bank, debit.date) or
         Enum.any?(issuer_bills, fn {_bank, _start, period_end} ->
           period_end != nil and
             Date.diff(debit.date, period_end) in -@closes_after_days..@closed_before_days
         end))
  end

  # "Valor adicionado na conta por cartão de crédito" is the card's money, never income.
  # The Pix it funded (same account, amount and day) is spending only until the bill
  # with the purchase is imported, which then charges it with the fees.
  defp pix_on_credit(credits, debits, bills) do
    fundings = Enum.filter(credits, &card_funding?(&1.description))

    pix_ids =
      for funding <- fundings,
          pix <- List.wrap(Enum.find(debits, &funded_by?(&1, funding))),
          bill_covers?(bills, funding.bank, pix.date),
          uniq: true,
          do: pix.id

    Enum.map(fundings, & &1.id) ++ pix_ids
  end

  @doc "Money the card put in the account for a Pix on credit (\"Pix no Crédito\")."
  def card_funding?(description),
    do: String.contains?(normalize(description), "adicionado na conta por cartao de credito")

  defp funded_by?(debit, funding) do
    debit.statement_id == funding.statement_id and cents(debit.amount) == cents(funding.amount) and
      abs(Date.diff(debit.date, funding.date)) <= 1
  end

  defp bill_covers?(bills, bank, date) do
    Enum.any?(bills, fn {bill_bank, period_start, period_end} ->
      bill_bank == bank and period_start != nil and period_end != nil and
        Date.compare(date, period_start) != :lt and Date.compare(date, period_end) != :gt
    end)
  end

  defp payment_like?(description) do
    account_payment?(description) or issuer(normalize(description)) != nil
  end

  defp issuer(text) do
    Enum.find_value(@issuers, fn {name, bank} -> if String.contains?(text, name), do: bank end)
  end

  defp cents(amount),
    do: amount |> Decimal.abs() |> Decimal.mult(100) |> Decimal.round() |> Decimal.to_integer()

  defp normalize(description) do
    description
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace(~r/\s+/, " ")
  end
end
