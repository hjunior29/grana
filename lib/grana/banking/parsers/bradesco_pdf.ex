defmodule Grana.Banking.Parsers.BradescoPdf do
  @moduledoc """
  Parser **determinístico** de extratos (conta corrente) do Bradesco a partir
  do texto extraído por `pdftotext -layout` (ver `Grana.Banking.Parsers.PdfText`).

  Não usa IA — portanto não alucina. A estrutura do extrato é:

    * cada folha repete um cabeçalho
      `Data | Histórico | Docto. | Crédito (R$) | Débito (R$) | Saldo (R$)`;
    * as posições das colunas **mudam entre folhas**, então são detectadas a
      cada cabeçalho encontrado;
    * cada transação é um "bloco" de linhas separado por linhas em branco;
    * a descrição pode ocupar várias linhas (linha principal + continuação
      `DES:`/`REM:` com o nome da contraparte), todas ancoradas à esquerda da
      coluna Histórico;
    * a data pode estar ausente num bloco, herdando a do bloco anterior;
    * a folha "Últimos Lançamentos" re-lista transações já presentes nas folhas
      anteriores (mesmo Docto) — essas duplicatas são removidas por `parse/1`.

  A saída tem o mesmo formato dos demais parsers (CSV/IA): lista de mapas com
  `:date`, `:amount`, `:type`, `:description`, `:original_description`,
  `:identifier` (o Docto), `:installment_current`, `:installment_total` e
  `:installment_group_id`.
  """

  alias Grana.Banking.Parsers.InstallmentParser

  @money_regex ~r/\d[\d.]*,\d{2}/

  @doc """
  Parseia o texto layout-preservado do extrato e devolve a lista de transações
  (sem duplicatas da folha "Últimos Lançamentos"). Devolve `[]` quando nada
  reconhecível é encontrado (sinal para o chamador cair no fallback de IA).
  """
  def parse(text) when is_binary(text) do
    text
    |> events()
    |> Enum.flat_map(fn
      {:txn, txn, _saldo} -> [txn]
      _ -> []
    end)
    |> dedup_recap()
  end

  @doc """
  Confere a integridade dos valores extraídos contra o saldo impresso no
  extrato. Para cada segmento (delimitado por uma linha "COD. LANC.", que marca
  o saldo inicial daquela folha), o saldo corrente acumulado a partir dos
  movimentos extraídos deve bater com o saldo impresso em cada transação.

  Devolve `:ok` ou `{:error, discrepâncias}`, onde cada discrepância é um mapa
  `%{date:, description:, expected:, printed:}`. É uma rede de segurança: uma
  divergência indica que o parser leu um valor/tipo errado (ex.: o layout do
  banco mudou).
  """
  def reconcile(text) when is_binary(text) do
    text
    |> events()
    |> Enum.reduce({nil, []}, &check/2)
    |> case do
      {_running, []} -> :ok
      {_running, issues} -> {:error, Enum.reverse(issues)}
    end
  end

  # ---- Pipeline de eventos -----------------------------------------------

  # Converte o texto numa sequência ordenada de eventos:
  #   * `{:reset, saldo}`      — linha COD. LANC. (saldo inicial da folha)
  #   * `{:txn, txn, saldo}`   — uma transação e o saldo impresso ao lado dela
  defp events(text) do
    if signed_layout?(text), do: signed_events(text), else: column_events(text)
  end

  defp column_events(text) do
    text
    |> String.split("\n")
    # The page break would push the page's first line one column to the right.
    |> Enum.map(&String.replace_prefix(&1, "\f", ""))
    |> Enum.reduce(%{cols: nil, last_date: nil, block: [], events: []}, &handle_line/2)
    |> flush_block()
    |> Map.fetch!(:events)
    |> Enum.reverse()
  end

  defp handle_line(line, state) do
    cond do
      cols = detect_columns(line) ->
        # Novo cabeçalho de folha: fecha bloco pendente e atualiza as colunas.
        state |> flush_block() |> Map.put(:cols, cols) |> Map.put(:block, [])

      String.trim(line) == "" ->
        state |> flush_block() |> Map.put(:block, [])

      true ->
        Map.update!(state, :block, &[line | &1])
    end
  end

  defp flush_block(%{block: []} = state), do: state
  defp flush_block(%{cols: nil} = state), do: %{state | block: []}

  defp flush_block(%{block: block_rev, cols: cols, last_date: last_date, events: events} = state) do
    lines = Enum.reverse(block_rev)
    block_date = find_date(lines, cols)
    new_last_date = block_date || last_date

    event = classify_block(lines, cols, new_last_date)

    %{state | block: [], last_date: new_last_date, events: prepend(event, events)}
  end

  defp prepend(nil, events), do: events
  defp prepend(event, events), do: [event | events]

  defp classify_block(lines, cols, date) do
    description = build_description(lines, cols)
    saldo = saldo(lines, cols)

    cond do
      String.contains?(description, "COD. LANC") ->
        if saldo, do: {:reset, saldo}, else: nil

      true ->
        build_txn_event(lines, cols, date, description, saldo)
    end
  end

  defp build_txn_event(lines, cols, date, description, saldo) do
    with true <- date != nil,
         true <- description != "",
         false <- subtotal?(description),
         {amount, type} when not is_nil(amount) <- movement(lines, cols) do
      {:txn, new_txn(date, description, amount, type, docto(lines, cols)), saldo}
    else
      _ -> nil
    end
  end

  defp new_txn(date, description, amount, type, identifier) do
    {final_desc, inst_current, inst_total} = InstallmentParser.extract(description)
    group_id = InstallmentParser.generate_group_id(final_desc, inst_total)

    %{
      date: date,
      amount: if(type == "debit", do: Decimal.negate(amount), else: amount),
      type: type,
      identifier: identifier,
      description: final_desc,
      original_description: description,
      installment_current: inst_current,
      installment_total: inst_total,
      installment_group_id: group_id
    }
  end

  defp subtotal?(description) do
    String.starts_with?(description, "Total") or
      String.starts_with?(description, "SALDO ANTERIOR")
  end

  # Remove transações re-listadas na folha "Últimos Lançamentos": mesma data,
  # mesmo Docto, mesmo valor e mesma descrição = mesma transação. Mantém a
  # primeira ocorrência (ordem do documento).
  defp dedup_recap(txns) do
    Enum.uniq_by(txns, fn t ->
      {t.date, t.identifier, Decimal.to_string(t.amount), t.description}
    end)
  end

  # ---- Reconciliação -----------------------------------------------------

  defp check({:reset, saldo}, {_running, issues}), do: {saldo, issues}
  # transação antes de qualquer COD. LANC.: usa o saldo impresso como baseline
  defp check({:txn, _txn, saldo}, {nil, issues}), do: {saldo, issues}
  # sem saldo impresso (o Internet Banking só imprime o do último movimento do dia):
  # não dá pra conferir, mas o movimento entra no acumulado
  defp check({:txn, txn, nil}, {running, issues}), do: {Decimal.add(running, txn.amount), issues}

  defp check({:txn, txn, saldo}, {running, issues}) do
    expected = Decimal.add(running, txn.amount)

    if Decimal.equal?(expected, saldo) do
      {saldo, issues}
    else
      issue = %{date: txn.date, description: txn.description, expected: expected, printed: saldo}
      {saldo, [issue | issues]}
    end
  end

  # ---- Data --------------------------------------------------------------

  defp find_date(lines, cols) do
    Enum.find_value(lines, fn line ->
      line
      |> column(0, cols.hist)
      |> String.trim()
      |> parse_date()
    end)
  end

  # dd/mm/aaaa no Bradesco Celular, dd/mm/aa no Internet Banking.
  defp parse_date(str) do
    with [d, m, y] <- String.split(str, "/"),
         {day, ""} <- Integer.parse(d),
         {month, ""} <- Integer.parse(m),
         {year, ""} <- Integer.parse(y),
         {:ok, date} <- Date.new(if(year < 100, do: 2000 + year, else: year), month, day) do
      date
    else
      _ -> nil
    end
  end

  # ---- Docto / Saldo -----------------------------------------------------

  defp docto(lines, cols) do
    Enum.find_value(lines, fn line ->
      case Regex.run(~r/\d+/, column(line, cols.docto - 2, cols.credito)) do
        [d] -> d
        _ -> nil
      end
    end)
  end

  defp saldo(lines, cols) do
    Enum.find_value(lines, fn line ->
      line |> String.slice(cols.saldo, 999) |> extract_money()
    end)
  end

  # ---- Movimento (crédito/débito) ----------------------------------------

  # Procura, na(s) linha(s) do bloco, a coluna Crédito e Débito. A coluna onde
  # cai o valor define o tipo. Saldo (coluna mais à direita) é ignorado.
  defp movement(lines, cols) do
    Enum.find_value(lines, {nil, nil}, fn line ->
      credit = money_in(line, cols.credito, cols.debito)
      debit = money_in(line, cols.debito, cols.saldo)

      cond do
        positive?(credit) -> {credit, "credit"}
        positive?(debit) -> {debit, "debit"}
        true -> nil
      end
    end)
  end

  defp money_in(line, from, to) do
    line
    |> column(from, to)
    |> extract_money()
  end

  defp extract_money(slice) do
    case Regex.run(@money_regex, slice) do
      [match] -> parse_br_number(match)
      _ -> nil
    end
  end

  defp positive?(nil), do: false
  defp positive?(%Decimal{} = d), do: Decimal.compare(d, 0) == :gt

  defp parse_br_number(str) do
    str
    |> String.replace(".", "")
    |> String.replace(",", ".")
    |> Decimal.new()
  rescue
    _ -> nil
  end

  # ---- Descrição ---------------------------------------------------------

  # Junta os fragmentos de Histórico das linhas do bloco. Só conta uma linha
  # cujo texto esteja ancorado à esquerda da coluna Histórico (descarta linha
  # de valor, rodapé centralizado "Bradesco Celular", "Nome:", "Data:" etc.).
  defp build_description(lines, cols) do
    lines
    |> Enum.filter(&description_line?(&1, cols))
    |> Enum.map(&clean_fragment(column(&1, cols.hist - 1, cols.docto)))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" - ")
    |> String.trim()
  end

  defp description_line?(line, cols) do
    line
    |> column(cols.hist - 1, cols.hist + 1)
    |> String.trim()
    |> Kernel.!=("")
  end

  # Limpa um fragmento de descrição. Em blocos de linha única o nº do docto pode
  # vazar à direita; em linhas "DES:/REM:" remove o prefixo e a data final
  # (ex.: "DES: PADARIA EXEMPLO 06/02" -> "PADARIA EXEMPLO"). Remove "*" final.
  defp clean_fragment(fragment) do
    fragment
    |> String.replace(~r/\s{2,}\d+\s*$/, "")
    |> String.trim()
    |> String.replace(~r/^(DES|REM):\s*/i, "")
    |> String.replace(~r/\s+\d{2}\/\d{2}\s*$/, "")
    |> String.replace(~r/\*+\s*$/, "")
    |> String.trim()
  end

  # ---- Layout do Internet Banking ----------------------------------------

  # The Internet Banking export ("Bradesco Internet Banking", dates as dd/mm/yy) does not
  # keep the rows under the header columns, but it signs every debit ("- 60,00"), which
  # the Bradesco Celular one never does. There a block is read by its pieces (runs of
  # text apart by 2+ spaces): the first amount is the movement, a debit when signed, and
  # a second one is the balance printed on the day's last movement.
  @signed_money ~r/(?:^|\s)-\s\d[\d.]*,\d{2}/
  @piece_money ~r/^(-\s?)?\d{1,3}(\.\d{3})*,\d{2}$/

  defp signed_layout?(text), do: Regex.match?(@signed_money, text)

  defp signed_events(text) do
    text
    |> String.split("\n")
    |> Enum.drop_while(&is_nil(detect_columns(&1)))
    # The "Saldos Invest Fácil" table comes after the "Total" row, across pages.
    |> Enum.take_while(&(not String.contains?(&1, "Saldos Invest")))
    |> Enum.reject(&detect_columns/1)
    |> Enum.chunk_while([], &chunk_movement/2, &{:cont, Enum.reverse(&1), []})
    |> Enum.map(&read_block/1)
    |> Enum.reduce({nil, nil, []}, &signed_event/2)
    |> elem(2)
    |> Enum.reverse()
  end

  # Movements are apart by blank lines, but a new page ("\\f") may start right below the
  # previous page's last movement.
  defp chunk_movement(line, acc) do
    cond do
      String.trim(line) == "" ->
        if acc == [], do: {:cont, []}, else: {:cont, Enum.reverse(acc), []}

      String.starts_with?(line, "\f") and acc != [] ->
        {:cont, Enum.reverse(acc), [line]}

      true ->
        {:cont, [line | acc]}
    end
  end

  defp read_block(lines) do
    Enum.reduce(lines, %{date: nil, text: [], docto: nil, amounts: []}, fn line, block ->
      {date, rest} = split_date(line)
      pieces = String.split(rest, ~r/\s{2,}/, trim: true) |> Enum.map(&String.trim/1)
      {money, others} = Enum.split_with(pieces, &Regex.match?(@piece_money, &1))

      {doctos, words} =
        others |> Enum.flat_map(&unglue_docto/1) |> Enum.split_with(&Regex.match?(~r/^\d+$/, &1))

      # "20/07" alone is the Pix date of the line above, not a posting date.
      text =
        words
        |> Enum.reject(&(&1 == "" or Regex.match?(~r/^\d{2}\/\d{2}$/, &1)))
        |> Enum.join(" ")
        |> clean_fragment()

      %{
        block
        | date: block.date || date,
          text: if(text == "", do: block.text, else: block.text ++ [text]),
          docto: block.docto || List.first(doctos),
          amounts: block.amounts ++ Enum.map(money, &signed_amount/1)
      }
    end)
  end

  # "Des: Fulano 25/05 1000007": a long name leaves one space before the Docto. The letter
  # is checked apart: inside the regex (".*\p{L}.*") it backtracks quadratically on a
  # long line.
  defp unglue_docto(piece) do
    with [_, text, docto] <- Regex.run(~r/^(.+)\s(\d{6,})$/u, piece),
         true <- String.match?(text, ~r/\p{L}/u) do
      [text, docto]
    else
      _ -> [piece]
    end
  end

  defp split_date(line) do
    case Regex.run(~r/^\s*(\d{2}\/\d{2}\/\d{2}(?:\d{2})?)(?=\s|$)(.*)$/s, line) do
      [_, date, rest] -> {parse_date(date), rest}
      _ -> {nil, line}
    end
  end

  defp signed_amount(piece) do
    value = piece |> String.replace(~r/^-\s?/, "") |> parse_br_number()
    if String.starts_with?(piece, "-"), do: Decimal.negate(value), else: value
  end

  # A block with no amount is a movement's first lines cut by a page break: they go
  # in front of the next block.
  defp signed_event(%{amounts: []} = block, {last_date, _pending, events}),
    do: {block.date || last_date, block, events}

  defp signed_event(block, {last_date, pending, events}) do
    block =
      if pending,
        do: %{block | text: pending.text ++ block.text, date: block.date || pending.date},
        else: block

    date = block.date || last_date
    {date, nil, prepend(signed_txn(block, date), events)}
  end

  defp signed_txn(%{amounts: [movement | rest]} = block, date) do
    description = Enum.join(block.text, " - ")
    balance = List.first(rest)

    cond do
      String.starts_with?(description, "SALDO ANTERIOR") ->
        {:reset, movement}

      date == nil or description == "" or subtotal?(description) ->
        nil

      Decimal.negative?(movement) ->
        {:txn, new_txn(date, description, Decimal.negate(movement), "debit", block.docto),
         balance}

      true ->
        {:txn, new_txn(date, description, movement, "credit", block.docto), balance}
    end
  end

  # ---- Colunas -----------------------------------------------------------

  # Detecta o cabeçalho e devolve os índices (em graphemes) de cada coluna, ou
  # `nil` se a linha não for um cabeçalho. As posições são por-folha.
  defp detect_columns(line) do
    with data when is_integer(data) <- label_index(line, "Data"),
         hist when is_integer(hist) <- label_index(line, "Histórico"),
         docto when is_integer(docto) <- label_index(line, "Docto."),
         credito when is_integer(credito) <- label_index(line, "Crédito"),
         debito when is_integer(debito) <- label_index(line, "Débito"),
         saldo when is_integer(saldo) <- label_index(line, "Saldo") do
      %{data: data, hist: hist, docto: docto, credito: credito, debito: debito, saldo: saldo}
    else
      _ -> nil
    end
  end

  defp label_index(line, label) do
    case String.split(line, label, parts: 2) do
      [before, _] -> String.length(before)
      _ -> nil
    end
  end

  # Recorta uma coluna por índices de grapheme (consistente com o grid de
  # caracteres que o `pdftotext -layout` produz).
  defp column(line, from, to) when to > from do
    String.slice(line, from, to - from)
  end

  defp column(_line, _from, _to), do: ""
end
