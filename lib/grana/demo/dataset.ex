defmodule Grana.Demo.Dataset do
  @moduledoc """
  Os dados 100% fictícios da demonstração: um ano na vida financeira de uma pessoa
  inventada (`Grana.Demo.holder_name/0`), com salário e contas no Bradesco, conta e
  cartão no Nubank.

  Os extratos e faturas saem nos formatos de exportação dos dois bancos, com datas
  relativas a hoje, e entram pelo mesmo caminho de um upload (`StatementProcessor`, que
  lê CSV sem IA): parcelas, pagamento de fatura, transferências entre as próprias
  contas, investimentos, estornos e reembolsos aparecem como num uso real. Os valores
  variam de mês a mês, mas sem sorteio: o mesmo dia gera sempre os mesmos dados.
  """

  alias Grana.Banking
  alias Grana.Banking.StatementProcessor

  @months 12
  @holder "MARINA ALVES DUARTE"
  @masked_cpf "•••.444.777-••"
  @bradesco_account "Ag: 1234 | Conta: 98765-4"
  @bradesco_opening 423_000

  @doc "Importa a base na conta da demonstração e completa com regras, metas e buscas."
  def seed!(user, today) do
    seed_rules(user.id)

    for statement <- statements(today) do
      {:ok, _} =
        StatementProcessor.process(
          statement.content,
          statement.bank,
          statement.type,
          user.id,
          statement.filename
        )
    end

    seed_goals(user.id)
    seed_saved_searches(user.id)
    Grana.Demo.Examples.seed!(user, today)
  end

  @doc "Os arquivos da base: `%{bank, type, filename, content}`, na ordem de importação."
  def statements(today) do
    months = months(today)

    bradesco_files(months, today) ++
      nubank_account_files(months, today) ++ nubank_bill_files(months, today)
  end

  # ── Calendário ──

  defp months(today) do
    first = Date.beginning_of_month(today)
    for offset <- -(@months - 1)..0, do: {offset, Date.shift(first, month: offset)}
  end

  defp on(month, day), do: %{month | day: min(day, Date.days_in_month(month))}

  # Sem sorteio: cada valor sai do hash da sua chave (mês, item, ocorrência).
  defp pick(key, lo..hi//1), do: lo + :erlang.phash2(key, hi - lo + 1)

  defp keep_past(events, today), do: Enum.filter(events, &(Date.compare(&1.date, today) != :gt))

  # ── Bradesco: salário, contas da casa, investimento ──

  defp bradesco_events({offset, month}) do
    salary = if offset < -5, do: 785_000, else: 824_000

    [
      ev(on(month, 5), "CRED SALARIO VERTICE SOLUCOES LTDA", salary),
      ev(on(month, 6), "TRANSFERENCIA PIX DES: #{@holder} #{ddmm(on(month, 6))}", -320_000),
      ev(on(month, 7), "PIX DES: IMOBILIARIA HORIZONTE #{ddmm(on(month, 7))}", -215_000),
      ev(
        on(month, 10),
        "PAGTO ELETRON COBRANCA ENERGIA LITORAL",
        -pick({offset, :energy}, 16_000..29_000)
      ),
      ev(on(month, 12), "PAGTO ELETRON COBRANCA INTERNET FIBRA VELOZ", -11_990),
      ev(on(month, 15), "PAGTO COBRANCA VIDA PLENA SAUDE", -48_900),
      ev(on(month, 16), "APLICACAO CDB DI", -pick({offset, :cdb}, 4..9) * 10_000),
      ev(on(month, 20), "TARIFA BANCARIA CESTA CLASSIC", -3_490)
    ] ++
      if(offset in [-8, -2], do: [ev(on(month, 18), "RESGATE CDB DI", 150_000)], else: []) ++
      if(offset == -3,
        do: [ev(on(month, 22), "PIX REM: CARLOS EDUARDO DIAS #{ddmm(on(month, 22))}", 25_000)],
        else: []
      )
  end

  defp bradesco_files(months, today) do
    months
    |> Enum.chunk_every(3)
    |> Enum.map_reduce(@bradesco_opening, fn chunk, balance ->
      events =
        chunk
        |> Enum.flat_map(&bradesco_events/1)
        |> keep_past(today)
        |> Enum.sort_by(& &1.date, Date)

      {rows, balance} =
        Enum.map_reduce(events, balance, fn event, balance ->
          balance = balance + event.cents
          {bradesco_row(event, balance), balance}
        end)

      {_offset, last_month} = List.last(chunk)
      last_day = Enum.min([Date.end_of_month(last_month), today], Date)

      file = %{
        bank: "bradesco",
        type: "extrato",
        filename: "Bradesco_#{Calendar.strftime(last_day, "%d-%m-%Y")}.csv",
        content:
          "Extrato de: #{@bradesco_account};;;;;\n" <>
            "Data;Histórico;Docto.;Crédito (R$);Débito (R$);Saldo (R$)\n" <>
            Enum.join(rows, "\n") <> "\n"
      }

      {file, balance}
    end)
    |> elem(0)
  end

  defp bradesco_row(event, balance) do
    docto = 1_000_000 + :erlang.phash2({event.date, event.description}, 8_999_999)
    date = Calendar.strftime(event.date, "%d/%m/%Y")

    {credit, debit} =
      if event.cents >= 0, do: {br(event.cents), " "}, else: {" ", br(-event.cents)}

    Enum.join([date, event.description, docto, credit, debit, br(balance)], ";")
  end

  # ── Nubank: conta (recebe do Bradesco, paga a fatura, Pix e débito) ──

  defp nubank_account_events({offset, month}) do
    first_month? = offset == -(@months - 1)

    [
      ev(
        on(month, 6),
        "Transferência recebida pelo Pix - #{@holder} - #{@masked_cpf} - BCO BRADESCO S.A. (0237) Agência: 1234 Conta: 98765-4",
        320_000
      )
    ] ++
      if(first_month?,
        do: [],
        else: [ev(on(month, 9), "Pagamento de fatura", -bill_total(offset - 1, month))]
      ) ++
      repeat({offset, :bakery}, 2..5, fn i ->
        ev(
          on(month, pick({offset, :bakery, i}, 1..28)),
          "Compra no débito - PADARIA TRIGO DE OURO",
          -pick({offset, :bakery, i, :v}, 700..3_200)
        )
      end) ++
      repeat({offset, :cafe}, 1..3, fn i ->
        ev(
          on(month, pick({offset, :cafe, i}, 1..28)),
          "Compra no débito - CAFE DA PRACA",
          -pick({offset, :cafe, i, :v}, 600..1_800)
        )
      end) ++
      repeat({offset, :market}, 1..3, fn i ->
        ev(
          on(month, pick({offset, :market, i}, 1..28)),
          "Compra no débito - FEIRA DO PRODUTOR",
          -pick({offset, :market, i, :v}, 3_500..8_500)
        )
      end) ++
      repeat({offset, :friend}, 0..2, fn i ->
        ev(
          on(month, pick({offset, :friend, i}, 1..28)),
          "Transferência enviada pelo Pix - CARLOS EDUARDO DIAS - •••.222.333-•• - BANCO PRIMAVERA S.A. (0999) Agência: 1 Conta: 1234567-8",
          -pick({offset, :friend, i, :v}, 4_000..12_000)
        )
      end) ++
      if(rem(offset, 3) == 0,
        do: [
          ev(
            on(month, 24),
            "Transferência enviada pelo Pix - BEATRIZ LOPES MOURA - •••.555.666-•• - BANCO PRIMAVERA S.A. (0999) Agência: 10 Conta: 22334-5",
            -pick({offset, :gift}, 5_000..15_000)
          )
        ],
        else: []
      ) ++
      if(offset == -4,
        do: [
          ev(
            on(month, 14),
            "Reembolso recebido pelo Pix - SP LOJA AURORA - 12.345.678/0001-90 - BANCO PRIMAVERA S.A. (0999) Agência: 1 Conta: 11111-1",
            5_990
          )
        ],
        else: []
      )
  end

  defp nubank_account_files(months, today) do
    months
    |> Enum.chunk_every(3)
    |> Enum.map(fn chunk ->
      events =
        chunk
        |> Enum.flat_map(&nubank_account_events/1)
        |> keep_past(today)
        |> Enum.sort_by(& &1.date, Date)

      {_offset, first} = List.first(chunk)
      {_offset, last} = List.last(chunk)
      last_day = Enum.min([Date.end_of_month(last), today], Date)

      %{
        bank: "nubank",
        type: "extrato",
        filename: "Nubank_conta_#{Date.to_iso8601(first)}_#{Date.to_iso8601(last_day)}.csv",
        content: nubank_account_csv(events)
      }
    end)
  end

  defp nubank_account_csv(events) do
    rows =
      Enum.map(events, fn event ->
        Enum.join(
          [
            Calendar.strftime(event.date, "%d/%m/%Y"),
            dot(event.cents),
            uuid({event.date, event.description, event.cents}),
            event.description
          ],
          ","
        )
      end)

    "Data,Valor,Identificador,Descrição\n" <> Enum.join(rows, "\n") <> "\n"
  end

  # ── Nubank: cartão (compras do mês; a fatura fecha no dia 2 e vence no dia 9) ──

  @card [
    {:market, "Supermercado Vila Nova", 4..6, 8_000..26_000},
    {:bakery, "Padaria Trigo de Ouro", 2..4, 800..2_800},
    {:delivery,
     [
       "Delivery *Sushi Kaze",
       "Delivery *Pizzaria Forno a Lenha",
       "Delivery *Burger da Vila",
       "Delivery *Cantina da Nonna"
     ], 3..7, 3_500..9_500},
    {:ride, "Rota *Corrida", 4..9, 1_200..3_800},
    {:fuel, "Posto Avenida", 1..2, 15_000..23_000},
    {:pharmacy, "Farmácia Bem-Estar", 1..3, 2_500..12_000},
    {:restaurant, "Restaurante Sabor da Terra", 1..2, 7_000..16_000},
    {:cinema, "Cinema Estação", 0..2, 3_000..7_000},
    {:books, "Livraria Página Nova", 0..1, 4_500..12_000}
  ]

  defp purchases({offset, month}) do
    variable =
      Enum.flat_map(@card, fn {key, title, count, amount} ->
        repeat({offset, key}, count, fn i ->
          ev(
            on(month, pick({offset, key, i}, 1..28)),
            title(title, {offset, key, i}),
            pick({offset, key, i, :v}, amount)
          )
        end)
      end)

    fixed = [
      ev(on(month, 2), "Academia Movimento", 10_990),
      ev(on(month, 3), "Streaming Plus", 3_990),
      ev(on(month, 11), "Nuvem Fotos", 990)
    ]

    installments =
      installment(month, offset, -7, "Sp Loja Aurora", 10, 12_990) ++
        installment(month, offset, -3, "Eletro Mais", 12, 24_900)

    gifts =
      if month.month == 12,
        do:
          repeat({offset, :gifts}, 2..3, fn i ->
            ev(
              on(month, pick({offset, :gifts, i}, 10..23)),
              "Ateliê dos Presentes",
              pick({offset, :gifts, i, :v}, 8_000..25_000)
            )
          end),
        else: []

    refund =
      if offset == -5,
        do: [ev(on(month, 19), "Estorno de compra - Cinema Estação", -4_500)],
        else: []

    variable ++ fixed ++ installments ++ gifts ++ refund
  end

  defp title(titles, key) when is_list(titles),
    do: Enum.at(titles, :erlang.phash2({key, :title}, length(titles)))

  defp title(title, _key), do: title

  defp installment(month, offset, start, title, total, cents) do
    n = offset - start + 1

    if n in 1..total,
      do: [ev(on(month, 21), "#{title} - Parcela #{n}/#{total}", cents)],
      else: []
  end

  # Total da fatura das compras de um mês: o que a conta paga no dia 9 do mês seguinte.
  defp bill_total(offset, next_month) do
    month = Date.shift(next_month, month: -1)
    {offset, month} |> purchases() |> Enum.map(& &1.cents) |> Enum.sum()
  end

  defp nubank_bill_files(months, today) do
    Enum.map(months, fn {offset, month} = entry ->
      paid =
        if offset == -(@months - 1),
          do: [],
          else: [ev(on(month, 9), "Pagamento recebido", -bill_total(offset - 1, month))]

      events =
        (purchases(entry) ++ paid)
        |> keep_past(today)
        |> Enum.sort_by(& &1.date, {:desc, Date})

      closing = Date.shift(month, month: 1) |> on(2)

      %{
        bank: "nubank",
        type: "fatura",
        filename: "Nubank_#{Date.to_iso8601(closing)}.csv",
        content: nubank_bill_csv(events)
      }
    end)
  end

  defp nubank_bill_csv(events) do
    rows =
      Enum.map(events, fn event ->
        "#{Date.to_iso8601(event.date)},#{event.description},#{dot(event.cents)}"
      end)

    "date,title,amount\n" <> Enum.join(rows, "\n") <> "\n"
  end

  # ── Regras, metas e buscas da conta ──

  @rules [
    {"delivery", "Alimentação"},
    {"corrida", "Transporte"},
    {"streaming", "Assinaturas"},
    {"nuvem fotos", "Assinaturas"},
    {"academia", "Saúde"},
    {"vida plena", "Saúde"},
    {"energia", "Moradia"},
    {"fibra veloz", "Moradia"},
    {"cinema", "Lazer"},
    {"livraria", "Educação"},
    {"loja aurora", "Compras"},
    {"eletro mais", "Compras"},
    {"presentes", "Compras"}
  ]

  defp seed_rules(user_id) do
    categories = user_id |> Banking.ensure_default_categories() |> Map.new(&{&1.name, &1.id})

    for {pattern, category} <- @rules do
      {:ok, _} =
        Banking.create_category_rule(%{
          user_id: user_id,
          pattern: pattern,
          category_id: categories[category]
        })
    end
  end

  defp seed_goals(user_id) do
    categories = user_id |> Banking.list_categories() |> Map.new(&{&1.name, &1.id})

    goals = [
      %{type: "expense_limit", target_value: Decimal.new(6_500)},
      %{type: "investment_goal", target_value: Decimal.new(700)},
      %{
        type: "category_limit",
        target_value: Decimal.new(1_800),
        category_id: categories["Alimentação"]
      },
      %{
        type: "category_limit",
        target_value: Decimal.new(650),
        category_id: categories["Transporte"]
      },
      %{type: "category_limit", target_value: Decimal.new(250), category_id: categories["Lazer"]}
    ]

    for goal <- goals,
        do: {:ok, _} = Banking.create_financial_goal(Map.put(goal, :user_id, user_id))
  end

  defp seed_saved_searches(user_id) do
    searches = [
      %{name: "Delivery", query: "description:delivery*"},
      %{name: "Compras acima de R$ 200", query: "type:debit AND amount >= 200"},
      %{name: "Parceladas", query: "installments > 1"}
    ]

    for search <- searches, do: {:ok, _} = Banking.create_saved_search(user_id, search)
  end

  # ── Formatos ──

  defp ev(date, description, cents), do: %{date: date, description: description, cents: cents}

  defp repeat(key, count, fun) do
    case pick({key, :count}, count) do
      0 -> []
      n -> Enum.map(1..n, fun)
    end
  end

  defp ddmm(date), do: Calendar.strftime(date, "%d/%m")

  # 1234567 → "12.345,67"
  defp br(cents) do
    reais =
      cents
      |> div(100)
      |> Integer.to_string()
      |> String.reverse()
      |> String.graphemes()
      |> Enum.chunk_every(3)
      |> Enum.map_join(".", &Enum.join/1)
      |> String.reverse()

    "#{reais},#{cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  # -1234567 → "-12345.67"
  defp dot(cents) do
    sign = if cents < 0, do: "-", else: ""
    abs = abs(cents)

    "#{sign}#{div(abs, 100)}.#{abs |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp uuid(key) do
    <<a::binary-4, b::binary-2, c::binary-2, d::binary-2, e::binary-6>> =
      :crypto.hash(:md5, :erlang.term_to_binary(key))

    Enum.map_join([a, b, c, d, e], "-", &Base.encode16(&1, case: :lower))
  end
end
