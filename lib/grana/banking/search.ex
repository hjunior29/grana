defmodule Grana.Banking.Search do
  @moduledoc """
  Pesquisa avançada de transações, com a sintaxe das bases científicas (PubMed, Scopus, BVS):
  operadores booleanos, parênteses, aspas, truncamento e campos.

      (uber OR 99 OR cabify) AND category:transporte NOT bank:nubank
      description:pix* AND amount >= 100 AND date:2026-01..2026-03

  `parse/1` valida e compila a busca; `filter/3` aplica em transações já carregadas com
  `:category` e `:bank_statement`. Texto é comparado sem maiúsculas e sem acentos, por isso a
  busca roda em Elixir e não no SQLite (o `LIKE` de lá só ignora maiúsculas em ASCII).

  Campos e valores seguem o banco (`description`, `amount`, `type:debit`, `statement_type:fatura`).
  Precedência: `NOT` antes de `AND`, que vem antes de `OR`. Termos lado a lado valem `AND`.
  Os operadores só valem em maiúsculas, como no PubMed, para que "and" e "or" sigam sendo texto.
  """

  defstruct source: "", ast: nil, canonical: ""

  @type t :: %__MODULE__{source: String.t(), ast: term(), canonical: String.t()}

  @max_length 500

  @fields %{
    "description" => :description,
    "desc" => :description,
    "category" => :category,
    "cat" => :category,
    "bank" => :bank,
    "statement_type" => :statement_type,
    "source" => :source,
    "type" => :type,
    "amount" => :amount,
    "date" => :date,
    "year" => :year,
    "month" => :month,
    "day" => :day,
    "internal" => :internal,
    "is_internal_transfer" => :internal,
    "installments" => :installments,
    "installment_total" => :installments,
    "recurrence" => :recurrence
  }

  @text_fields [:description, :category, :bank]
  @enum_fields [:type, :statement_type, :source, :internal, :recurrence]

  # `credit` e `debit` são a coluna; `income`, `expense` e `investment` seguem os totais da
  # tela (despesa sem investimento; investimento pela categoria).
  @types %{
    "credit" => :credit,
    "debit" => :debit,
    "income" => :income,
    "expense" => :expense,
    "investment" => :investment
  }

  @statement_types %{"extrato" => "extrato", "fatura" => "fatura"}
  @sources %{"upload" => "upload", "open_finance" => "open_finance"}
  @booleans %{"true" => true, "false" => false}
  @recurrences %{"fixed" => "fixed", "variable" => "variable"}

  # Nomes de mês em inglês e as abreviações em português que diferem.
  @months %{
    "jan" => 1,
    "january" => 1,
    "feb" => 2,
    "february" => 2,
    "fev" => 2,
    "mar" => 3,
    "march" => 3,
    "apr" => 4,
    "april" => 4,
    "abr" => 4,
    "may" => 5,
    "mai" => 5,
    "jun" => 6,
    "june" => 6,
    "jul" => 7,
    "july" => 7,
    "aug" => 8,
    "august" => 8,
    "ago" => 8,
    "sep" => 9,
    "september" => 9,
    "set" => 9,
    "oct" => 10,
    "october" => 10,
    "out" => 10,
    "nov" => 11,
    "november" => 11,
    "dec" => 12,
    "december" => 12,
    "dez" => 12
  }

  @doc """
  Valida e compila a busca. Busca vazia casa com tudo. Devolve `{:error, mensagem}` com o
  motivo em português quando a sintaxe não fecha.
  """
  @spec parse(String.t() | nil) :: {:ok, t()} | {:error, String.t()}
  def parse(nil), do: parse("")

  def parse(query) when is_binary(query) do
    source = String.trim(query)

    cond do
      String.length(source) > @max_length ->
        {:error, "A busca passou de #{@max_length} caracteres."}

      source == "" ->
        {:ok, %__MODULE__{}}

      true ->
        do_parse(source)
    end
  end

  defp do_parse(source) do
    ast =
      source
      |> String.to_charlist()
      |> scan([])
      |> parse_query()

    {:ok, %__MODULE__{source: source, ast: ast, canonical: render(ast, :top)}}
  catch
    {:search_error, message} -> {:error, message}
  end

  @filter_timeout_ms 2_000

  @doc "Transações que casam com a busca, na ordem recebida."
  def filter(%__MODULE__{ast: nil}, transactions, _recurring), do: transactions

  def filter(%__MODULE__{ast: ast}, transactions, recurring) do
    task =
      Task.async(fn ->
        Enum.filter(transactions, &eval(ast, document(&1, recurring)))
      end)

    case Task.yield(task, @filter_timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _ -> []
    end
  end

  @doc "Se a busca usa `recurrence:` (que precisa da análise de fixas e variáveis)."
  def uses_recurrence?(%__MODULE__{ast: ast}), do: uses?(ast, :recurrence)

  @doc "Minúsculas, sem acentos e sem espaços nas pontas."
  def fold(nil), do: ""

  def fold(text) do
    text
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.trim()
  end

  # ── Leitura dos tokens ──

  defp scan([], acc), do: Enum.reverse(acc)
  defp scan([c | rest], acc) when c in [?\s, ?\t, ?\n, ?\r], do: scan(rest, acc)
  defp scan([?( | rest], acc), do: scan(rest, [:lparen | acc])
  defp scan([?) | rest], acc), do: scan(rest, [:rparen | acc])

  defp scan([?" | rest], acc) do
    case Enum.split_while(rest, &(&1 != ?")) do
      {text, [?" | rest]} -> scan(rest, [{:phrase, to_string(text)} | acc])
      {text, []} -> fail(~s(As aspas abertas em "#{text} não foram fechadas.))
    end
  end

  defp scan([?/ | rest], acc) do
    {source, rest} = take_regex(rest, [])
    scan(rest, [{:regex, source} | acc])
  end

  defp scan(chars, acc) do
    case field_prefix(chars) do
      {field, cmp, rest} ->
        scan(rest, [{:field, field, cmp} | acc])

      nil ->
        {word, rest} = Enum.split_while(chars, &word_char?/1)
        scan(rest, [word_token(to_string(word)) | acc])
    end
  end

  defp take_regex([?\\, ?/ | rest], acc), do: take_regex(rest, [?/ | acc])
  defp take_regex([?\\, c | rest], acc), do: take_regex(rest, [c, ?\\ | acc])
  defp take_regex([?/ | rest], acc), do: {acc |> Enum.reverse() |> to_string(), rest}
  defp take_regex([c | rest], acc), do: take_regex(rest, [c | acc])

  defp take_regex([], acc) do
    fail("Faltou fechar a expressão regular em /#{acc |> Enum.reverse() |> to_string()}.")
  end

  # `campo:`, `campo>=` etc. Um nome desconhecido seguido de ":" é erro (provável erro de
  # digitação no campo); texto com ":" de verdade vai entre aspas.
  defp field_prefix(chars) do
    case Enum.split_while(chars, &name_char?/1) do
      {[], _rest} ->
        nil

      {name, rest} ->
        name = to_string(name)

        case take_op(rest) || spaced_op(name, rest) do
          nil -> nil
          {cmp, rest} -> known_field(name, cmp, rest)
        end
    end
  end

  # `amount > 100`, como no SQL: espaço antes do operador só depois de um campo conhecido.
  defp spaced_op(name, rest) do
    if Map.has_key?(@fields, fold(name)),
      do: rest |> Enum.drop_while(&(&1 in [?\s, ?\t])) |> take_op()
  end

  defp known_field(name, cmp, rest) do
    case Map.fetch(@fields, fold(name)) do
      {:ok, field} ->
        {field, cmp, rest}

      :error when cmp == :eq ->
        fail(
          ~s(Campo desconhecido "#{name}". Veja os campos na sintaxe ou ponha o texto entre aspas.)
        )

      :error ->
        nil
    end
  end

  defp take_op([?: | rest]) do
    case take_op(rest) do
      {cmp, rest} when cmp != :eq -> {cmp, rest}
      _ -> {:eq, rest}
    end
  end

  defp take_op([?>, ?= | rest]), do: {:ge, rest}
  defp take_op([?<, ?= | rest]), do: {:le, rest}
  defp take_op([?> | rest]), do: {:gt, rest}
  defp take_op([?< | rest]), do: {:lt, rest}
  defp take_op([?= | rest]), do: {:eq, rest}
  defp take_op(_chars), do: nil

  defp name_char?(c), do: c in ?a..?z or c in ?A..?Z or c == ?_ or c in 0xC0..0x17F

  defp word_char?(c), do: c not in [?\s, ?\t, ?\n, ?\r, ?(, ?), ?"]

  defp word_token("AND"), do: {:op, :and, "AND"}
  defp word_token("OR"), do: {:op, :or, "OR"}
  defp word_token("NOT"), do: {:op, :not, "NOT"}
  defp word_token(word), do: {:word, word}

  # ── Gramática ──
  #
  #   busca   := ou
  #   ou      := e (OR e)*
  #   e       := nao ((AND)? nao)*
  #   nao     := NOT nao | termo
  #   termo   := "(" ou ")" | campo valor | campo ":(" ou ")" | valor

  defp parse_query(tokens) do
    case parse_or(tokens, nil) do
      {ast, []} -> ast
      {_ast, [:rparen | _]} -> fail(~s[Há um ")" sem parêntese aberto.])
    end
  end

  defp parse_or(tokens, ctx) do
    {left, rest} = parse_and(tokens, ctx)
    or_tail(left, rest, ctx)
  end

  defp or_tail(left, [{:op, :or, _} | rest], ctx) do
    {right, rest} = parse_and(rest, ctx)
    or_tail({:or, left, right}, rest, ctx)
  end

  defp or_tail(left, rest, _ctx), do: {left, rest}

  defp parse_and(tokens, ctx) do
    {left, rest} = parse_not(tokens, ctx)
    and_tail(left, rest, ctx)
  end

  defp and_tail(left, [{:op, :and, _} | rest], ctx) do
    {right, rest} = parse_not(rest, ctx)
    and_tail({:and, left, right}, rest, ctx)
  end

  defp and_tail(left, [token | _] = tokens, ctx) do
    if operand_start?(token) do
      {right, rest} = parse_not(tokens, ctx)
      and_tail({:and, left, right}, rest, ctx)
    else
      {left, tokens}
    end
  end

  defp and_tail(left, [], _ctx), do: {left, []}

  defp operand_start?({:op, op, _}), do: op == :not
  defp operand_start?(:rparen), do: false
  defp operand_start?(_token), do: true

  defp parse_not([{:op, :not, _} | rest], ctx) do
    {expr, rest} = parse_not(rest, ctx)
    {{:not, expr}, rest}
  end

  defp parse_not(tokens, ctx), do: parse_term(tokens, ctx)

  defp parse_term([:lparen, :rparen | _], _ctx), do: fail("Há parênteses vazios.")

  defp parse_term([:lparen | rest], ctx) do
    case parse_or(rest, ctx) do
      {expr, [:rparen | rest]} -> {expr, rest}
      _ -> fail("Faltou fechar um parêntese.")
    end
  end

  defp parse_term([{:field, field, :eq}, :lparen | _] = tokens, _ctx) do
    parse_term(tl(tokens), field)
  end

  defp parse_term([{:field, field, _cmp}, :lparen | _], _ctx) do
    fail(~s[Use ":" antes do parêntese, como #{field}:(a OR b).])
  end

  defp parse_term([{:field, field, cmp}, {kind, _} = value | rest], _ctx)
       when kind in [:word, :phrase, :regex] do
    {condition(field, cmp, value), rest}
  end

  defp parse_term([{:field, field, cmp} | _], _ctx) do
    fail(~s(Faltou o valor depois de "#{field}#{op_text(cmp)}".))
  end

  defp parse_term([{kind, _} = value | rest], ctx) when kind in [:word, :phrase, :regex] do
    {condition(ctx || :any, :eq, value), rest}
  end

  defp parse_term([{:op, _op, word} | _], _ctx), do: fail("Faltou um termo antes de #{word}.")
  defp parse_term([:rparen | _], _ctx), do: fail(~s[Há um ")" sem parêntese aberto.])
  defp parse_term([], _ctx), do: fail("A busca termina sem um termo depois do último operador.")

  # ── Condições ──

  defp condition(field, cmp, value),
    do: {:cond, label(field, cmp, value), spec(field, cmp, value)}

  defp label(:any, _cmp, value), do: value_text(value)
  defp label(field, cmp, value), do: "#{field}#{op_text(cmp)}#{value_text(value)}"

  defp value_text({:word, word}), do: word
  defp value_text({:phrase, phrase}), do: ~s("#{phrase}")
  defp value_text({:regex, source}), do: "/#{source}/"

  defp op_text(:eq), do: ":"
  defp op_text(:gt), do: ">"
  defp op_text(:ge), do: ">="
  defp op_text(:lt), do: "<"
  defp op_text(:le), do: "<="

  defp spec(:any, :eq, value) do
    {:any, [spec(:description, :eq, value), spec(:category, :eq, value)]}
  end

  defp spec(field, :eq, value) when field in @text_fields do
    {:text, field, text_matcher(field, value)}
  end

  defp spec(field, cmp, _value)
       when cmp != :eq and (field in @text_fields or field in @enum_fields) do
    fail(
      ~s("#{field}" só aceita ":". Comparações como > valem para amount, date, year, month, day e installments.)
    )
  end

  defp spec(field, _cmp, {:regex, _}) do
    fail(~s("#{field}" não aceita expressão regular.))
  end

  defp spec(:type, :eq, value) do
    {:type, enum_value(value, @types, "type aceita credit, debit, income, expense ou investment")}
  end

  defp spec(:statement_type, :eq, value) do
    {:enum, :statement_type,
     enum_value(value, @statement_types, "statement_type aceita extrato ou fatura")}
  end

  defp spec(:source, :eq, value) do
    {:enum, :source, enum_value(value, @sources, "source aceita upload ou open_finance")}
  end

  defp spec(:recurrence, :eq, value) do
    {:enum, :recurrence, enum_value(value, @recurrences, "recurrence aceita fixed ou variable")}
  end

  defp spec(:internal, :eq, value) do
    {:enum, :internal, enum_value(value, @booleans, "internal aceita true ou false")}
  end

  defp spec(field, cmp, value) do
    case constraints(field, cmp, raw_value(value)) do
      [{:ge, from}, {:le, to}] = bounds -> range_spec(field, bounds, compare(from, to))
      bounds -> {:range, field, bounds}
    end
  end

  # Mês e dia dão a volta: `month:dec..feb` é dezembro, janeiro e fevereiro.
  defp range_spec(field, [{:ge, from}, {:le, to}], :gt) when field in [:month, :day] do
    {:any, [{:range, field, [{:ge, from}]}, {:range, field, [{:le, to}]}]}
  end

  defp range_spec(field, _bounds, :gt),
    do: fail("O começo do intervalo vem depois do fim em #{field}.")

  defp range_spec(field, bounds, _order), do: {:range, field, bounds}

  defp raw_value({_kind, text}), do: String.trim(text)

  defp enum_value(value, options, hint) do
    case Map.fetch(options, value |> raw_value() |> fold()) do
      {:ok, option} -> option
      :error -> fail(~s(Valor "#{raw_value(value)}" inválido: #{hint}.))
    end
  end

  @max_regex_length 120

  defp text_matcher(_field, {:regex, source}) when byte_size(source) > @max_regex_length do
    fail("Expressão regular muito longa (máx. #{@max_regex_length} caracteres).")
  end

  defp text_matcher(_field, {:regex, source}) do
    if Regex.match?(~r/\([^)]*[*+{][^)]*\)[*+{?]/, source) do
      fail("Expressão regular contém repetições aninhadas não permitidas.")
    else
      case Regex.compile(source, "iu") do
        {:ok, regex} -> {:regex, regex}
        {:error, _} -> fail("Expressão regular inválida: /#{source}/.")
      end
    end
  end

  defp text_matcher(field, {:word, word}) do
    term = fold(word)

    cond do
      String.contains?(term, ["*", "?"]) -> {:pattern, wildcard(term)}
      field == :description -> {:contains, term}
      true -> {:equals, term}
    end
  end

  defp text_matcher(field, {:phrase, phrase}) do
    case {field, fold(phrase)} do
      {_field, ""} ->
        fail("Há aspas vazias.")

      {:description, term} ->
        {:pattern,
         Regex.compile!("(?<![\\p{L}\\p{N}])#{Regex.escape(term)}(?![\\p{L}\\p{N}])", "u")}

      {_field, term} ->
        {:equals, term}
    end
  end

  defp wildcard(term) do
    source =
      term
      |> String.replace(~r/\*+/, "*")
      |> String.graphemes()
      |> Enum.map_join(fn
        "*" -> ".*"
        "?" -> "."
        char -> Regex.escape(char)
      end)

    Regex.compile!("^#{source}$", "su")
  end

  # Número e data viram limites inclusivos: cada valor é um período `{primeiro, último}` (um
  # mês, um ano, um dia), e `>` compara com o fim do período, `>=` com o começo.
  defp constraints(field, cmp, text) do
    {cmp, text} = inline_op(cmp, text)

    case text |> String.split("..", parts: 2) |> Enum.map(&String.trim/1) do
      [single] ->
        bounds(cmp, period!(field, single))

      [from, to] when cmp == :eq ->
        range_bounds(field, from, to)

      _ ->
        fail(~s(Intervalo só vale com ":", como #{field}:10..20.))
    end
  end

  # Dentro de um grupo (`amount:(<10 OR >1000)`) o operador vem colado ao valor.
  defp inline_op(:eq, text) do
    case take_op(String.to_charlist(text)) do
      {cmp, rest} when cmp != :eq -> {cmp, rest |> to_string() |> String.trim()}
      _ -> {:eq, text}
    end
  end

  defp inline_op(cmp, text), do: {cmp, text}

  defp bounds(:eq, {first, last}), do: [{:ge, first}, {:le, last}]
  defp bounds(:gt, {_first, last}), do: [{:gt, last}]
  defp bounds(:ge, {first, _last}), do: [{:ge, first}]
  defp bounds(:lt, {first, _last}), do: [{:lt, first}]
  defp bounds(:le, {_first, last}), do: [{:le, last}]

  defp range_bounds(field, "", ""),
    do: fail("Intervalo vazio em #{field}:.. (falta o começo ou o fim).")

  defp range_bounds(field, "", to), do: bounds(:le, period!(field, to))
  defp range_bounds(field, from, ""), do: bounds(:ge, period!(field, from))

  defp range_bounds(field, from, to) do
    bounds(:ge, period!(field, from)) ++ bounds(:le, period!(field, to))
  end

  defp period!(:amount, text) do
    case parse_amount(text) do
      {:ok, amount} ->
        {amount, amount}

      :error ->
        fail(~s("amount" espera um número sem sinal, como amount>100 ou amount:49,90..200.))
    end
  end

  defp period!(:date, text) do
    case parse_date_period(fold(text)) do
      {:ok, period} ->
        period

      :error ->
        fail(~s(Data "#{text}" inválida. Use 2026-03-15, 15/03/2026, 2026-03, 2026 ou today-30d.))
    end
  end

  defp period!(:year, text),
    do: int_period(text, 1900..2999, ~s("year" espera um ano, como year:2026.))

  defp period!(:day, text),
    do: int_period(text, 1..31, ~s("day" espera um dia do mês, de 1 a 31.))

  defp period!(:installments, text),
    do:
      int_period(
        text,
        1..999,
        ~s("installments" espera o número de parcelas, como installments>1.)
      )

  defp period!(:month, text) do
    case Map.fetch(@months, fold(text)) do
      {:ok, month} -> {month, month}
      :error -> int_period(text, 1..12, ~s("month" espera um mês, como month:12 ou month:dec.))
    end
  end

  defp int_period(text, range, message) do
    case Integer.parse(text) do
      {n, ""} -> if n in range, do: {n, n}, else: fail(message)
      _ -> fail(message)
    end
  end

  defp parse_amount(text) do
    cleaned =
      text
      |> String.downcase()
      |> String.replace_prefix("r$", "")
      |> String.trim()

    cleaned =
      if String.contains?(cleaned, ","),
        do: cleaned |> String.replace(".", "") |> String.replace(",", "."),
        else: cleaned

    case Decimal.parse(cleaned) do
      {amount, ""} -> finite_positive(amount)
      _ -> :error
    end
  end

  defp finite_positive(amount) do
    if Decimal.inf?(amount) or Decimal.nan?(amount) or Decimal.negative?(amount),
      do: :error,
      else: {:ok, amount}
  end

  defp parse_date_period("today"), do: {:ok, day_period(Date.utc_today())}
  defp parse_date_period("yesterday"), do: {:ok, day_period(Date.add(Date.utc_today(), -1))}

  defp parse_date_period(text) do
    cond do
      match = Regex.run(~r/^today([+-])(\d{1,4})([dwmy])$/, text) -> relative_period(match)
      match = Regex.run(~r/^(\d{4})-(\d{1,2})-(\d{1,2})$/, text) -> ymd_period(match, [1, 2, 3])
      match = Regex.run(~r/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/, text) -> ymd_period(match, [3, 2, 1])
      match = Regex.run(~r/^(\d{4})-(\d{1,2})$/, text) -> month_period(match, 1, 2)
      match = Regex.run(~r/^(\d{1,2})\/(\d{4})$/, text) -> month_period(match, 2, 1)
      match = Regex.run(~r/^(\d{4})$/, text) -> year_period(match)
      true -> :error
    end
  end

  defp relative_period([_, sign, amount, unit]) do
    n = String.to_integer(amount) * if(sign == "-", do: -1, else: 1)

    shift =
      case unit do
        "d" -> [day: n]
        "w" -> [week: n]
        "m" -> [month: n]
        "y" -> [year: n]
      end

    {:ok, day_period(Date.shift(Date.utc_today(), shift))}
  end

  defp ymd_period(match, order) do
    [y, m, d] = Enum.map(order, &(match |> Enum.at(&1) |> String.to_integer()))

    case Date.new(y, m, d) do
      {:ok, date} -> {:ok, day_period(date)}
      _ -> :error
    end
  end

  defp month_period(match, year_at, month_at) do
    year = match |> Enum.at(year_at) |> String.to_integer()
    month = match |> Enum.at(month_at) |> String.to_integer()

    case Date.new(year, month, 1) do
      {:ok, first} -> {:ok, {first, Date.end_of_month(first)}}
      _ -> :error
    end
  end

  defp year_period([_, year]) do
    year = String.to_integer(year)
    {:ok, {Date.new!(year, 1, 1), Date.new!(year, 12, 31)}}
  end

  defp day_period(date), do: {date, date}

  defp fail(message), do: throw({:search_error, message})

  # ── Avaliação ──

  defp eval({:and, left, right}, doc), do: eval(left, doc) and eval(right, doc)
  defp eval({:or, left, right}, doc), do: eval(left, doc) or eval(right, doc)
  defp eval({:not, expr}, doc), do: not eval(expr, doc)
  defp eval({:cond, _label, spec}, doc), do: check(spec, doc)

  defp check({:any, specs}, doc), do: Enum.any?(specs, &check(&1, doc))

  defp check({:text, field, matcher}, doc) do
    doc |> Map.fetch!(field) |> Enum.any?(&text_match?(matcher, &1))
  end

  defp check({:range, field, bounds}, doc) do
    value = Map.fetch!(doc, field)
    Enum.all?(bounds, fn {op, bound} -> compare(value, bound) in allowed(op) end)
  end

  defp check({:type, type}, doc) when type in [:credit, :income], do: doc.type == "credit"
  defp check({:type, :debit}, doc), do: doc.type == "debit"
  defp check({:type, :investment}, doc), do: doc.category_kind == "investment"

  defp check({:type, :expense}, doc),
    do: doc.type == "debit" and doc.category_kind != "investment"

  defp check({:enum, field, expected}, doc), do: Map.fetch!(doc, field) == expected

  defp text_match?({:contains, term}, {_raw, folded}), do: String.contains?(folded, term)
  defp text_match?({:equals, term}, {_raw, folded}), do: folded == term
  defp text_match?({:pattern, regex}, {_raw, folded}), do: Regex.match?(regex, folded)

  defp text_match?({:regex, regex}, {raw, folded}) do
    safe_match?(regex, raw) or safe_match?(regex, folded)
  end

  defp safe_match?(regex, subject) when is_binary(subject) do
    case :re.run(subject, regex.re_pattern, [
           {:capture, :none},
           {:match_limit, 50_000},
           {:match_limit_recursion, 5_000}
         ]) do
      :match -> true
      _ -> false
    end
  end

  defp safe_match?(_regex, _subject), do: false

  defp allowed(:gt), do: [:gt]
  defp allowed(:ge), do: [:gt, :eq]
  defp allowed(:lt), do: [:lt]
  defp allowed(:le), do: [:lt, :eq]

  defp compare(%Decimal{} = a, b), do: Decimal.compare(a, b)
  defp compare(%Date{} = a, b), do: Date.compare(a, b)
  defp compare(a, b) when a > b, do: :gt
  defp compare(a, b) when a < b, do: :lt
  defp compare(_a, _b), do: :eq

  defp document(txn, recurring) do
    statement = txn.bank_statement
    category = txn.category

    %{
      description: Enum.uniq(texts([txn.description, txn.original_description])),
      category: texts([if(category, do: category.name, else: "Sem Categoria")]),
      bank: texts([statement && statement.bank]),
      amount: Decimal.abs(txn.amount),
      date: txn.date,
      year: txn.date.year,
      month: txn.date.month,
      day: txn.date.day,
      type: txn.type,
      category_kind: category && category.kind,
      statement_type: statement && statement.statement_type,
      source: statement && statement.source,
      internal: txn.is_internal_transfer == true,
      installments: txn.installment_total || 1,
      recurrence: recurring |> Map.get(txn.id, %{}) |> Map.get(:status)
    }
  end

  defp texts(values) do
    for value <- values, is_binary(value), value != "", do: {value, fold(value)}
  end

  defp uses?({op, left, right}, field) when op in [:and, :or],
    do: uses?(left, field) or uses?(right, field)

  defp uses?({:not, expr}, field), do: uses?(expr, field)
  defp uses?({:cond, _label, {:enum, kind, _}}, field), do: kind == field
  defp uses?(_ast, _field), do: false

  # ── Forma canônica ("como o Grana leu") ──

  defp render({:or, left, right}, parent) do
    wrap("#{render(left, :or)} OR #{render(right, :or)}", parent in [:and, :not])
  end

  defp render({:and, left, right}, parent) do
    wrap("#{render(left, :and)} AND #{render(right, :and)}", parent in [:or, :not])
  end

  defp render({:not, expr}, _parent), do: "NOT #{render(expr, :not)}"
  defp render({:cond, label, _spec}, _parent), do: label

  defp wrap(text, true), do: "(#{text})"
  defp wrap(text, false), do: text
end
