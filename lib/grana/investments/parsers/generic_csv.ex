defmodule Grana.Investments.Parsers.GenericCsv do
  @moduledoc """
  Parser genérico para extratos de investimentos em CSV de qualquer instituição.

  Detecta automaticamente as colunas baseado no header.
  Suporta formatos comuns de corretoras brasileiras.
  """

  def parse(csv_content) do
    lines =
      csv_content
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case lines do
      [header | rows] ->
        separator = detect_separator(header)
        header_cells = split_line(header, separator)
        columns = detect_columns(header_cells)

        if columns do
          rows
          |> Enum.map(&parse_row(&1, separator, columns))
          |> Enum.reject(&is_nil/1)
        else
          {:error, "Não foi possível detectar as colunas do CSV. Verifique o formato."}
        end

      _ ->
        {:error, "Arquivo CSV vazio"}
    end
  end

  defp detect_separator(header) do
    semicolons = header |> String.graphemes() |> Enum.count(&(&1 == ";"))
    commas = header |> String.graphemes() |> Enum.count(&(&1 == ","))
    tabs = header |> String.graphemes() |> Enum.count(&(&1 == "\t"))

    cond do
      semicolons >= commas and semicolons >= tabs -> ";"
      tabs >= commas -> "\t"
      true -> ","
    end
  end

  defp split_line(line, separator) do
    line
    |> parse_csv_line(separator)
    |> Enum.map(&String.trim/1)
  end

  defp parse_csv_line(line, separator) do
    # Handle quoted fields (e.g., "value with, comma")
    parse_csv_fields(line, separator, [], "", false)
  end

  defp parse_csv_fields("", _sep, acc, current, _in_quotes) do
    Enum.reverse([current | acc])
  end

  defp parse_csv_fields(<<"\"", rest::binary>>, sep, acc, current, false) do
    parse_csv_fields(rest, sep, acc, current, true)
  end

  defp parse_csv_fields(<<"\"\"", rest::binary>>, sep, acc, current, true) do
    parse_csv_fields(rest, sep, acc, current <> "\"", true)
  end

  defp parse_csv_fields(<<"\"", rest::binary>>, sep, acc, current, true) do
    parse_csv_fields(rest, sep, acc, current, false)
  end

  defp parse_csv_fields(<<char::binary-size(1), rest::binary>>, sep, acc, current, false)
       when char == sep do
    parse_csv_fields(rest, sep, [current | acc], "", false)
  end

  defp parse_csv_fields(<<char::utf8, rest::binary>>, sep, acc, current, in_quotes) do
    parse_csv_fields(rest, sep, acc, current <> <<char::utf8>>, in_quotes)
  end

  defp detect_columns(header) do
    header_normalized = Enum.map(header, &String.downcase/1)

    date_idx = find_column(header_normalized, ["data_de_operação", "data_de_operacao", "data de operação", "data de operacao", "data", "date", "data movimentação", "data movimentacao", "data operação"])
    name_idx = find_column(header_normalized, ["nome_da_operação", "nome_da_operacao", "nome da operação", "nome da operacao", "ativo", "produto", "descrição", "descricao", "nome", "papel", "movimentação", "movimentacao"])
    ticker_idx = find_column(header_normalized, ["ticker", "código", "codigo", "código ativo", "símbolo", "simbolo"])
    type_idx = find_column(header_normalized, ["tipo", "operação", "operacao", "entrada/saída", "entrada/saida", "tipo de movimentação"])
    qty_idx = find_column(header_normalized, ["quantidade", "qtde", "qtd"])
    price_idx = find_column(header_normalized, ["preço unitário", "preco unitario", "preço", "preco", "valor unitário"])
    total_idx = find_column(header_normalized, ["valor_da_operação", "valor_da_operacao", "valor da operação", "valor da operacao", "valor total", "valor", "valor operacao", "valor operação", "valor (r$)"])
    asset_type_idx = find_column(header_normalized, ["tipo ativo", "classe", "tipo produto", "tipo de ativo"])

    if date_idx && (total_idx || (qty_idx && price_idx)) do
      %{
        date: date_idx,
        name: name_idx || ticker_idx,
        ticker: ticker_idx,
        type: type_idx,
        quantity: qty_idx,
        price: price_idx,
        total: total_idx,
        asset_type: asset_type_idx
      }
    else
      nil
    end
  end

  defp find_column(header, patterns) do
    Enum.find_index(header, fn cell ->
      Enum.any?(patterns, fn pattern ->
        String.contains?(cell, pattern)
      end)
    end)
  end

  defp parse_row(line, separator, columns) do
    cells = split_line(line, separator)
    date = parse_date(Enum.at(cells, columns.date))

    total =
      if columns.total do
        parse_decimal(Enum.at(cells, columns.total))
      else
        qty = parse_decimal(Enum.at(cells, columns[:quantity]))
        price = parse_decimal(Enum.at(cells, columns[:price]))
        if qty && price, do: Decimal.mult(qty, price), else: nil
      end

    if date && total do
      name = clean_string(Enum.at(cells, columns.name))
      ticker = if columns.ticker, do: clean_string(Enum.at(cells, columns.ticker))
      type_raw = if columns.type, do: clean_string(Enum.at(cells, columns.type)), else: ""
      quantity = if columns.quantity, do: parse_decimal(Enum.at(cells, columns.quantity)), else: Decimal.new(0)
      price = if columns.price, do: parse_decimal(Enum.at(cells, columns.price)), else: Decimal.new(0)
      asset_type_raw = if columns.asset_type, do: clean_string(Enum.at(cells, columns.asset_type))

      # When there's no type column, detect operation from the name field
      operation_source = if type_raw == "", do: name || "", else: type_raw
      operation = detect_operation(operation_source, total)
      asset_type = detect_asset_type(asset_type_raw, ticker, name)

      %{
        date: date,
        asset_name: name || ticker || "N/A",
        asset_ticker: ticker,
        asset_type: asset_type,
        operation: operation,
        quantity: quantity,
        unit_price: price,
        total_amount: Decimal.abs(total),
        fees: Decimal.new(0),
        original_description: Enum.join(cells, " | ")
      }
    else
      nil
    end
  end

  defp detect_operation(type_str, total) do
    type = String.downcase(type_str || "")

    cond do
      String.contains?(type, "compra") or type in ["c", "buy"] -> "compra"
      String.contains?(type, "recompra") -> "compra"
      String.contains?(type, "venda") or type in ["v", "sell"] -> "venda"
      String.contains?(type, "dividend") or String.contains?(type, "provento") -> "dividendo"
      String.contains?(type, "jcp") or String.contains?(type, "juros sobre capital") -> "jcp"
      String.contains?(type, "rendimento") or String.contains?(type, "yield") -> "rendimento"
      String.contains?(type, "amortiza") -> "amortizacao"
      String.contains?(type, "taxa") or String.contains?(type, "emolumento") -> "taxa"
      String.contains?(type, "cashback") -> "rendimento"
      String.contains?(type, "liquidação") or String.contains?(type, "liquidacao") -> "venda"
      String.contains?(type, "valor resgatado") or String.contains?(type, "resgate") -> "venda"
      String.contains?(type, "valor aportado") or String.contains?(type, "aporte") -> "compra"
      String.contains?(type, "investimento") -> "compra"
      String.contains?(type, "credito") or String.contains?(type, "crédito") -> "rendimento"
      String.contains?(type, "debito") or String.contains?(type, "débito") -> "compra"
      String.contains?(type, "transferência") or String.contains?(type, "transferencia") ->
        if total && Decimal.compare(total, 0) == :lt, do: "compra", else: "rendimento"
      true ->
        if total && Decimal.compare(total, 0) == :lt, do: "compra", else: "rendimento"
    end
  end

  defp detect_asset_type(asset_type_raw, ticker, name) do
    raw = String.downcase(asset_type_raw || "")
    ticker_lower = String.downcase(ticker || "")
    name_lower = String.downcase(name || "")

    cond do
      String.contains?(raw, "fii") or String.contains?(raw, "fundo imobiliário") -> "fii"
      String.contains?(raw, "etf") -> "etf"
      String.contains?(raw, "bdr") -> "bdr"
      String.contains?(raw, "tesouro") -> "tesouro"
      String.contains?(raw, "renda fixa") or String.contains?(raw, "cdb") or String.contains?(raw, "lci") -> "renda_fixa"
      String.contains?(raw, "cripto") or String.contains?(raw, "bitcoin") -> "cripto"
      String.contains?(raw, "fundo") -> "fundo"
      String.contains?(raw, "ação") or String.contains?(raw, "acao") -> "acao"
      String.contains?(name_lower, "fii") or String.ends_with?(ticker_lower, "11") -> "fii"
      String.contains?(name_lower, "tesouro") -> "tesouro"
      String.contains?(name_lower, "cdb") or String.contains?(name_lower, "lci") or String.contains?(name_lower, "lca") -> "renda_fixa"
      String.contains?(name_lower, "debênture") or String.contains?(name_lower, "debenture") -> "renda_fixa"
      String.contains?(name_lower, "precatório") or String.contains?(name_lower, "precatorio") -> "renda_fixa"
      String.contains?(name_lower, "nota fiscal") or String.contains?(name_lower, "nota promissória") -> "renda_fixa"
      String.contains?(name_lower, "criptomoeda") or String.contains?(name_lower, "cripto") or String.contains?(name_lower, "bitcoin") -> "cripto"
      String.contains?(name_lower, "operação estruturada") or String.contains?(name_lower, "operacao estruturada") -> "fundo"
      String.contains?(name_lower, "inss") -> "renda_fixa"
      String.match?(ticker_lower, ~r/^[a-z]{4}\d{1,2}$/) -> "acao"
      true -> "outro"
    end
  end

  defp parse_date(nil), do: nil

  defp parse_date(val) when is_binary(val) do
    trimmed = String.trim(val)

    cond do
      String.match?(trimmed, ~r/^\d{2}\/\d{2}\/\d{4}$/) ->
        [d, m, y] = String.split(trimmed, "/")
        case Date.new(String.to_integer(y), String.to_integer(m), String.to_integer(d)) do
          {:ok, date} -> date
          _ -> nil
        end

      String.match?(trimmed, ~r/^\d{4}-\d{2}-\d{2}$/) ->
        case Date.from_iso8601(trimmed) do
          {:ok, date} -> date
          _ -> nil
        end

      String.match?(trimmed, ~r/^\d{2}-\d{2}-\d{4}$/) ->
        [d, m, y] = String.split(trimmed, "-")
        case Date.new(String.to_integer(y), String.to_integer(m), String.to_integer(d)) do
          {:ok, date} -> date
          _ -> nil
        end

      true ->
        parse_portuguese_date(trimmed)
    end
  end

  defp parse_date(_), do: nil

  @month_names %{
    "janeiro" => 1, "fevereiro" => 2, "março" => 3, "marco" => 3,
    "abril" => 4, "maio" => 5, "junho" => 6,
    "julho" => 7, "agosto" => 8, "setembro" => 9,
    "outubro" => 10, "novembro" => 11, "dezembro" => 12
  }

  defp parse_portuguese_date(str) do
    case Regex.run(~r/^(\d{1,2})\s+de\s+(\w+)\s+de\s+(\d{4})$/i, str) do
      [_, day_str, month_name, year_str] ->
        month = Map.get(@month_names, String.downcase(month_name))

        if month do
          case Date.new(String.to_integer(year_str), month, String.to_integer(day_str)) do
            {:ok, date} -> date
            _ -> nil
          end
        else
          nil
        end

      _ ->
        nil
    end
  end

  defp parse_decimal(nil), do: nil

  defp parse_decimal(val) when is_binary(val) do
    cleaned =
      val
      |> String.trim()
      |> String.replace("R$", "")
      |> String.replace(" ", "")
      |> String.trim()

    cleaned =
      if String.contains?(cleaned, ",") do
        cleaned |> String.replace(".", "") |> String.replace(",", ".")
      else
        cleaned
      end

    case Decimal.parse(cleaned) do
      {decimal, _} -> decimal
      :error -> nil
    end
  end

  defp parse_decimal(_), do: nil

  defp clean_string(nil), do: nil
  defp clean_string(val), do: String.trim(to_string(val))
end
