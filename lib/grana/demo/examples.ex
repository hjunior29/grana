defmodule Grana.Demo.Examples do
  @moduledoc """
  O que a IA mostraria na demonstração, escrito de antemão: a análise do Painel (mês
  corrente e anterior) e uma conversa no Chat. Os textos são montados com os números dos
  próprios dados fictícios, para baterem com as telas; nenhuma chamada de IA acontece.
  """

  alias Grana.Banking
  alias Grana.Banking.AIAnalysis
  alias Grana.Chat
  alias Grana.Chat.Message
  alias Grana.Money
  alias Grana.Repo

  def seed!(user, today) do
    previous = Date.shift(Date.beginning_of_month(today), month: -1)

    for {date, partial?} <- [{previous, false}, {today, true}] do
      insert_analysis!(user.id, date, partial?)
    end

    insert_conversation!(user.id, previous, today)
  end

  # ── Análise do Painel ──

  defp insert_analysis!(user_id, date, partial?) do
    summary = Banking.monthly_summary(user_id, date.year, date.month)
    food = category_total(summary, "Alimentação")
    delivery = spending(user_id, date, "Delivery")
    month = month_label(date)

    balance = Decimal.sub(summary.total_income, summary.total_expenses)
    healthy? = Decimal.compare(balance, summary.total_investments) != :lt

    result = %{
      "nota" => if(healthy?, do: 8, else: 6),
      "titulo" =>
        if(healthy?,
          do: "#{String.capitalize(month)} no azul, com o delivery pedindo atenção",
          else: "#{String.capitalize(month)} apertado: os gastos encostaram na receita"
        ),
      "resumo" =>
        "#{if partial?, do: "Até agora, em", else: "Em"} #{month} entraram " <>
          "#{Money.format(summary.total_income)} e saíram #{Money.format(summary.total_expenses)} " <>
          "em gastos, além de #{Money.format(summary.total_investments)} investidos. " <>
          "Pagamentos de fatura e transferências entre as suas contas ficaram de fora das contas.",
      "pontos" => [
        %{
          "tipo" => "positivo",
          "texto" =>
            "O salário cobriu as despesas fixas (aluguel, energia, internet e plano de saúde) " <>
              "com folga, e sobrou para investir #{Money.format(summary.total_investments)}."
        },
        %{
          "tipo" => "negativo",
          "texto" =>
            "O delivery somou #{Money.format(delivery.total)} em #{delivery.count} pedidos, " <>
              "#{percent(delivery.total, food)} do que foi para Alimentação " <>
              "(#{Money.format(food)})."
        },
        %{
          "tipo" => "dica",
          "texto" =>
            "As parcelas da Sp Loja Aurora e da Eletro Mais levam R$ 378,90 por mês. " <>
              "Antes de uma compra parcelada nova, vale ver no simulador do Painel quando elas acabam."
        }
      ],
      "alerta" =>
        if(not healthy?,
          do: "Os gastos passaram do que entrou menos o investido: revise as compras do cartão.",
          else: nil
        )
    }

    Repo.insert!(%AIAnalysis{
      user_id: user_id,
      year: date.year,
      month: date.month,
      prompt: "Análise de #{month}.",
      filters_json: %{},
      result_json: result
    })
  end

  # ── Conversa do Chat ──

  defp insert_conversation!(user_id, previous, today) do
    delivery = spending(user_id, previous, "Delivery")

    food =
      category_total(
        Banking.monthly_summary(user_id, previous.year, previous.month),
        "Alimentação"
      )

    top =
      user_id
      |> Banking.merchant_spending({:month, today.year, today.month})
      |> Enum.take(3)

    question = "Quanto gastei com delivery no mês passado?"
    {:ok, conversation} = Chat.start_conversation(user_id, question)
    {:ok, _} = Chat.add_user_message(conversation, question)

    average =
      if delivery.count > 0,
        do: Decimal.div(delivery.total, delivery.count),
        else: Decimal.new(0)

    answer!(
      conversation,
      ~s|<p>Em #{month_label(previous)} foram <strong class="num">#{delivery.count} pedidos</strong> | <>
        ~s|de delivery, somando <span class="expense">#{Money.format(delivery.total)}</span>, | <>
        ~s|uma média de <span class="num">#{Money.format(average)}</span> por pedido.</p>| <>
        ~s|<p>Isso é <strong>#{percent(delivery.total, food)}</strong> do que você gastou com | <>
        ~s|Alimentação no mês (<span class="expense">#{Money.format(food)}</span>).</p>|
    )

    {:ok, _} = Chat.add_user_message(conversation, "E onde mais gastei este mês?")

    items =
      Enum.map_join(top, "", fn merchant ->
        ~s|<li><strong>#{merchant.name}</strong>: <span class="expense">#{Money.format(merchant.total)}</span> | <>
          ~s|em #{merchant.count} #{if merchant.count == 1, do: "compra", else: "compras"}</li>|
      end)

    answer!(
      conversation,
      "<p>Até agora, os maiores gastos do mês foram:</p><ul>#{items}</ul>" <>
        "<p>Pagamentos de fatura e transferências entre as suas contas não entram nessa conta.</p>"
    )
  end

  defp answer!(conversation, content) do
    %Message{conversation_id: conversation.id}
    |> Message.changeset(%{role: "assistant", content: content})
    |> Repo.insert!()
  end

  # ── Números ──

  defp category_total(summary, name) do
    Enum.find_value(summary.by_category, Decimal.new(0), fn %{category: category, total: total} ->
      if category && category.name == name, do: total
    end)
  end

  defp spending(user_id, date, prefix) do
    first = Date.beginning_of_month(date)

    transactions =
      user_id
      |> Banking.list_transactions(date_from: first, date_to: Date.end_of_month(first))
      |> Enum.filter(&(&1.type == "debit" and String.starts_with?(&1.description, prefix)))

    %{
      count: length(transactions),
      total:
        transactions
        |> Enum.map(&Decimal.abs(&1.amount))
        |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
    }
  end

  defp percent(part, whole) do
    if Decimal.gt?(whole, 0),
      do:
        "#{part |> Decimal.mult(100) |> Decimal.div(whole) |> Decimal.round(0) |> Decimal.to_string()}%",
      else: "0%"
  end

  defp month_label(date), do: "#{String.downcase(Banking.month_name(date.month))} de #{date.year}"
end
