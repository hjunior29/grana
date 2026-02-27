defmodule Grana.Investments.Parsers.B3Xlsx do
  @moduledoc """
  Parser para extratos da B3 em formato XLSX.

  Formato esperado (colunas):
  Entrada/Saída | Data | Movimentação | Produto | Instituição | Quantidade | Preço unitário | Valor da Operação
  """

  def parse(file_content) do
    tmp_path = Path.join(System.tmp_dir!(), "b3_#{:erlang.unique_integer([:positive])}.xlsx")
    File.write!(tmp_path, file_content)

    try do
      case Xlsxir.multi_extract(tmp_path) do
        results when is_list(results) ->
          table_ids =
            results
            |> Enum.flat_map(fn
              {:ok, tid} -> [tid]
              _ -> []
            end)

          {transactions, warnings} =
            table_ids
            |> Enum.reduce({[], []}, fn tid, {txns_acc, warns_acc} ->
              rows = Xlsxir.get_list(tid)
              {sheet_txns, sheet_warns} = parse_sheet(rows)
              {txns_acc ++ sheet_txns, warns_acc ++ sheet_warns}
            end)

          Enum.each(table_ids, &Xlsxir.close/1)

          case transactions do
            [] -> {:error, "Nenhuma transação encontrada no XLSX da B3"}
            _ -> {transactions, warnings}
          end

        {:error, reason} ->
          {:error, "Erro ao ler XLSX: #{inspect(reason)}"}
      end
    after
      File.rm(tmp_path)
    end
  end

  defp parse_sheet([]), do: {[], []}

  defp parse_sheet([header | rows]) do
    columns = detect_columns(header)

    if columns do
      {transactions, warnings} =
        Enum.reduce(rows, {[], []}, fn row, {txns, warns} ->
          case parse_row(row, columns) do
            nil ->
              product =
                if columns.product, do: to_string(Enum.at(row, columns.product, "")), else: ""

              date = Enum.at(row, columns.date)

              if date != nil and product != "" do
                {txns, ["Linha ignorada (B3): #{product}" | warns]}
              else
                {txns, warns}
              end

            txn ->
              {[txn | txns], warns}
          end
        end)

      {Enum.reverse(transactions), Enum.reverse(warnings)}
    else
      {[], []}
    end
  end

  defp detect_columns(header) do
    header_normalized =
      Enum.map(header, fn
        cell when is_binary(cell) ->
          cell |> String.trim() |> normalize_string() |> String.downcase()

        _ ->
          ""
      end)

    direction_idx = find_column(header_normalized, ["entrada/saida", "entrada/sa"])
    date_idx = find_column(header_normalized, ["data"])
    movement_idx = find_column(header_normalized, ["movimentacao", "movimenta"])
    product_idx = find_column(header_normalized, ["produto"])
    institution_idx = find_column(header_normalized, ["instituicao", "institui"])
    qty_idx = find_column(header_normalized, ["quantidade", "qtde", "qtd"])
    price_idx = find_column(header_normalized, ["preco unitario", "pre"])
    total_idx = find_column(header_normalized, ["valor da operacao", "valor da opera", "valor"])

    if date_idx do
      %{
        direction: direction_idx,
        date: date_idx,
        movement: movement_idx,
        product: product_idx,
        institution: institution_idx,
        quantity: qty_idx,
        price: price_idx,
        total: total_idx
      }
    else
      nil
    end
  end

  defp find_column(header, patterns) do
    Enum.find_index(header, fn cell ->
      Enum.any?(patterns, &String.starts_with?(cell, &1))
    end)
  end

  defp parse_row(row, columns) do
    date = parse_date(Enum.at(row, columns.date))

    if date == nil do
      nil
    else
      product_raw = if columns.product, do: to_string(Enum.at(row, columns.product, "")), else: ""
      {ticker, name} = parse_product(product_raw)

      movement_raw =
        if columns.movement, do: to_string(Enum.at(row, columns.movement, "")), else: ""

      direction_raw =
        if columns.direction, do: to_string(Enum.at(row, columns.direction, "")), else: ""

      quantity = parse_decimal(Enum.at(row, columns.quantity)) || Decimal.new(0)
      price = parse_decimal(Enum.at(row, columns.price)) || Decimal.new(0)
      total = parse_decimal(Enum.at(row, columns.total)) || Decimal.new(0)

      operation = detect_operation(movement_raw, direction_raw)
      asset_type = detect_asset_type(ticker, name)

      # Skip rows with no meaningful data
      # Skip non-financial movements and buy/sell with zero total (e.g. transfers with no value)
      if operation == :skip or
           (operation in ["compra", "venda"] and Decimal.compare(total, 0) == :eq and
              Decimal.compare(price, 0) == :eq) do
        nil
      else
        %{
          date: date,
          asset_name: name || ticker || "N/A",
          asset_ticker: ticker,
          asset_type: asset_type,
          operation: operation,
          quantity: quantity,
          unit_price: price,
          total_amount: total,
          fees: Decimal.new(0),
          original_description: "#{movement_raw} - #{product_raw}"
        }
      end
    end
  end

  # Parse "TICKER - Full Name" format from Produto column
  defp parse_product(product) when is_binary(product) do
    trimmed = String.trim(product)

    case String.split(trimmed, " - ", parts: 2) do
      [ticker, name] ->
        {String.trim(ticker), String.trim(name)}

      [single] ->
        # Check if it looks like a ticker
        if String.match?(single, ~r/^[A-Z]{3,6}\d{1,2}$/i) do
          {String.trim(single), nil}
        else
          {nil, String.trim(single)}
        end
    end
  end

  defp parse_product(_), do: {nil, nil}

  defp detect_operation(movement, direction) do
    mov = movement |> normalize_string() |> String.downcase()
    dir = direction |> normalize_string() |> String.downcase()

    cond do
      String.contains?(mov, "compra") and String.contains?(dir, "credito") -> "compra"
      String.contains?(mov, "venda") and String.contains?(dir, "debito") -> "venda"
      String.contains?(mov, "compra / venda") and String.contains?(dir, "credito") -> "compra"
      String.contains?(mov, "compra / venda") and String.contains?(dir, "debito") -> "venda"
      String.contains?(mov, "dividendo") -> "dividendo"
      String.contains?(mov, "juros sobre capital") or String.contains?(mov, "jcp") -> "jcp"
      String.contains?(mov, "rendimento") -> "rendimento"
      String.contains?(mov, "amortizacao") or String.contains?(mov, "amortiza") -> "amortizacao"
      String.contains?(mov, "resgate") -> "rendimento"
      String.contains?(mov, "leilao de fracao") or String.contains?(mov, "leil") -> "rendimento"
      String.contains?(mov, "transferencia") and String.contains?(dir, "credito") -> "compra"
      String.contains?(mov, "transferencia") and String.contains?(dir, "debito") -> "venda"
      # Skip non-financial movements
      String.contains?(mov, "direito de subscri") -> :skip
      String.contains?(mov, "cessao de direitos") -> :skip
      String.contains?(mov, "desdobro") -> :skip
      String.contains?(mov, "bonificacao") -> :skip
      String.contains?(mov, "atualizacao") -> :skip
      String.contains?(mov, "fracao em ativos") -> :skip
      String.contains?(mov, "vencimento") -> "venda"
      # Default: use direction as hint
      String.contains?(dir, "credito") -> "compra"
      String.contains?(dir, "debito") -> "venda"
      true -> "outro"
    end
  end

  defp detect_asset_type(ticker, name) do
    ticker_lower = if ticker, do: String.downcase(ticker), else: ""
    name_lower = if name, do: String.downcase(name), else: ""

    cond do
      String.starts_with?(ticker_lower, "cdb") or String.contains?(name_lower, "cdb") ->
        "renda_fixa"

      String.contains?(name_lower, "tesouro") ->
        "tesouro"

      (String.ends_with?(ticker_lower, "11") or String.ends_with?(ticker_lower, "12")) and
          (String.contains?(name_lower, "fundo de investimento imobili") or
             String.contains?(name_lower, "fdo inv imob") or
             String.contains?(name_lower, "fii")) ->
        "fii"

      String.ends_with?(ticker_lower, "11") ->
        "fii"

      String.contains?(name_lower, "bdr") ->
        "bdr"

      String.contains?(name_lower, "etf") ->
        "etf"

      String.contains?(name_lower, "fundo de investimento") ->
        "fundo"

      String.match?(ticker_lower, ~r/^[a-z]{4}\d{1,2}$/) ->
        "acao"

      true ->
        "outro"
    end
  end

  # Normalize accented characters to ASCII for reliable matching
  defp normalize_string(str) when is_binary(str) do
    str
    |> String.replace(~r/[àáâãäå]/u, "a")
    |> String.replace(~r/[èéêë]/u, "e")
    |> String.replace(~r/[ìíîï]/u, "i")
    |> String.replace(~r/[òóôõö]/u, "o")
    |> String.replace(~r/[ùúûü]/u, "u")
    |> String.replace(~r/[ç]/u, "c")
    |> String.replace(~r/[ñ]/u, "n")
    |> String.replace(~r/[ÀÁÂÃÄÅ]/u, "A")
    |> String.replace(~r/[ÈÉÊË]/u, "E")
    |> String.replace(~r/[ÌÍÎÏ]/u, "I")
    |> String.replace(~r/[ÒÓÔÕÖ]/u, "O")
    |> String.replace(~r/[ÙÚÛÜ]/u, "U")
    |> String.replace(~r/[Ç]/u, "C")
    |> String.replace(~r/[Ñ]/u, "N")
  end

  defp normalize_string(str), do: to_string(str)

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

      true ->
        nil
    end
  end

  defp parse_date(%Date{} = date), do: date
  defp parse_date({date, _time}), do: parse_date(date)
  defp parse_date(_), do: nil

  defp parse_decimal(nil), do: nil
  defp parse_decimal("-"), do: nil

  defp parse_decimal(val) when is_integer(val), do: Decimal.new(val)

  defp parse_decimal(val) when is_float(val) do
    val |> Decimal.from_float() |> Decimal.round(6)
  end

  defp parse_decimal(%Decimal{} = val), do: val

  defp parse_decimal(val) when is_binary(val) do
    cleaned =
      val
      |> String.trim()
      |> String.replace("R$", "")
      |> String.replace(" ", "")
      |> String.trim()

    if cleaned == "-" or cleaned == "" do
      nil
    else
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
  end

  defp parse_decimal(_), do: nil
end
