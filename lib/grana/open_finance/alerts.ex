defmodule Grana.OpenFinance.Alerts do
  @moduledoc """
  Alertas do dia sobre as contas conectadas: só o que pede ação (fatura com valor
  a pagar vencendo em até 5 dias, saldo negativo). Alimenta o bloco "Hoje" do
  Resumo e o resumo diário por email.
  """

  alias Grana.Money
  alias Grana.OpenFinance.Account

  @doc "Lista `%{kind: atom, message: String.t()}` para as contas dadas."
  def list(accounts, today \\ Date.utc_today()) do
    Enum.flat_map(accounts, &alert(&1, today))
  end

  defp alert(account, today) do
    cond do
      invoice_due?(account, today) ->
        days = Date.diff(account.balance_due_date, today)
        when_text = if days == 0, do: "vence hoje", else: "vence em #{days} dia(s)"

        [
          %{
            kind: :invoice_due,
            message:
              "Fatura #{Account.card_name(account)} #{when_text}: #{Money.format(account.balance)}"
          }
        ]

      negative_balance?(account) ->
        [
          %{
            kind: :negative_balance,
            message: "Saldo negativo na #{String.downcase(Account.kind_label(account))}"
          }
        ]

      true ->
        []
    end
  end

  defp invoice_due?(account, today) do
    Account.credit_card?(account) and positive?(account.balance) and
      account.balance_due_date != nil and Date.diff(account.balance_due_date, today) in 0..5
  end

  defp negative_balance?(account) do
    not Account.credit_card?(account) and account.balance != nil and
      Decimal.negative?(account.balance)
  end

  defp positive?(%Decimal{} = value), do: Decimal.positive?(value)
  defp positive?(_value), do: false
end
