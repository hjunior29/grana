defmodule Grana.Investments.Parsers.GcbCsv do
  @moduledoc """
  Parser para extratos CSV da GCB.

  Formato: 3 colunas — Data_de_operação, Nome_da_operação, Valor_da_operação
  Data: "10 de fevereiro de 2026"
  Valor: "R$ 490,04" ou "-R$ 8.484,01"
  """

  @months %{
    "janeiro" => 1,
    "fevereiro" => 2,
    "março" => 3,
    "marco" => 3,
    "abril" => 4,
    "maio" => 5,
    "junho" => 6,
    "julho" => 7,
    "agosto" => 8,
    "setembro" => 9,
    "outubro" => 10,
    "novembro" => 11,
    "dezembro" => 12
  }

  @skip_prefixes [
    "valor aportado",
    "valor resgatado",
    "cashback",
    "processando investimento",
    "estorno"
  ]

  def parse(file_content) do
    lines =
      file_content
      |> String.trim()
      |> String.split(~r/\r?\n/)
      |> Enum.drop(1)

    parsed = Enum.map(lines, &parse_csv_line/1)

    {valid_lines, parse_warnings} =
      Enum.reduce(parsed, {[], []}, fn
        nil, {acc, w} -> {acc, w}
        line, {acc, w} -> {[line | acc], w}
      end)

    non_skipped =
      valid_lines
      |> Enum.reverse()
      |> Enum.reject(&skip?/1)

    {transactions, classify_warnings} =
      Enum.reduce(non_skipped, {[], []}, fn raw, {txns, warns} ->
        case classify(raw) do
          nil ->
            desc = raw[:description] || "?"
            {txns, ["Operação não reconhecida: #{desc}" | warns]}

          txn ->
            {[txn | txns], warns}
        end
      end)

    warnings = Enum.reverse(parse_warnings ++ classify_warnings)
    {Enum.reverse(transactions), warnings}
  rescue
    e -> {:error, "Erro ao processar CSV da GCB: #{Exception.message(e)}"}
  end

  defp parse_csv_line(line) do
    line = String.trim(line)
    if line == "", do: nil, else: parse_csv_fields(line)
  end

  defp parse_csv_fields(line) do
    case Regex.scan(~r/"([^"]*)"/, line) do
      [[_, date_str], [_, desc], [_, amount_str]] ->
        %{date_str: date_str, description: desc, amount_str: amount_str}

      _ ->
        # Fallback: try comma-separated without quotes
        case String.split(line, ",", parts: 3) do
          [date_str, desc, amount_str] ->
            %{
              date_str: String.trim(date_str, "\""),
              description: String.trim(desc, "\""),
              amount_str: String.trim(amount_str, "\"")
            }

          _ ->
            nil
        end
    end
  end

  defp skip?(%{description: desc}) do
    lower = String.downcase(desc)
    Enum.any?(@skip_prefixes, &String.starts_with?(lower, &1))
  end

  defp skip?(_), do: true

  defp classify(%{date_str: date_str, description: desc, amount_str: amount_str}) do
    with {:ok, date} <- parse_date(date_str),
         {:ok, amount} <- parse_amount(amount_str),
         {:ok, classified} <- classify_operation(desc) do
      %{
        date: date,
        asset_name: classified.asset_name,
        asset_ticker: classified.ticker,
        asset_type: classified.asset_type,
        operation: classified.operation,
        quantity: Decimal.new(0),
        unit_price: Decimal.new(0),
        total_amount: amount,
        fees: Decimal.new(0),
        identifier: classified.identifier,
        original_description: desc
      }
    else
      _ -> nil
    end
  end

  # ── Date parsing ──

  def parse_date(str) do
    str = String.downcase(String.trim(str))

    case Regex.run(~r/^(\d{1,2}) de (\p{L}+) de (\d{4})$/u, str) do
      [_, day_str, month_str, year_str] ->
        with {day, _} <- Integer.parse(day_str),
             {year, _} <- Integer.parse(year_str),
             month when is_integer(month) <- Map.get(@months, month_str) do
          Date.new(year, month, day)
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  # ── Amount parsing ──

  def parse_amount(str) do
    str = String.trim(str)
    negative = String.starts_with?(str, "-")

    number_str =
      str
      |> String.replace(~r/[R$\s\x{00A0}]/u, "")
      |> String.replace(~r/^-/, "")
      |> String.replace(".", "")
      |> String.replace(",", ".")

    case Decimal.parse(number_str) do
      {d, _} ->
        result = if negative, do: Decimal.negate(d), else: d
        {:ok, result}

      :error ->
        :error
    end
  end

  # ── Operation classification ──

  defp classify_operation(desc) do
    # Normalize to ASCII lowercase for reliable matching
    norm = normalize(desc)

    cond do
      # Nota Fiscal — recompra (must be before compra, as "recompra" contains "compra")
      String.contains?(norm, "recompra de nota fiscal") ->
        {:ok,
         %{
           asset_type: "nota_fiscal",
           operation: "venda",
           asset_name: "Nota Fiscal",
           ticker: nil,
           identifier: nil
         }}

      # Nota Fiscal — liquidação (venda/retorno)
      String.contains?(norm, "liquidacao de nota fiscal") ->
        {:ok,
         %{
           asset_type: "nota_fiscal",
           operation: "venda",
           asset_name: "Nota Fiscal",
           ticker: nil,
           identifier: nil
         }}

      # Nota Fiscal — compra
      String.contains?(norm, "compra de nota fiscal") or
          String.contains?(norm, "investimento em nota fiscal") ->
        {:ok,
         %{
           asset_type: "nota_fiscal",
           operation: "compra",
           asset_name: "Nota Fiscal",
           ticker: nil,
           identifier: nil
         }}

      # Debênture — resgate (check before compra to avoid false match)
      String.contains?(norm, "resgate") and String.contains?(norm, "debenture") ->
        ticker = extract_id(desc, ~r/(DEB\d+)/)
        name = extract_debenture_name(desc)

        {:ok,
         %{
           asset_type: "debenture",
           operation: "venda",
           asset_name: name,
           ticker: ticker,
           identifier: ticker
         }}

      # Debênture — compra
      String.contains?(norm, "debenture") or Regex.match?(~r/investimento em deb\d+/i, norm) ->
        ticker = extract_id(desc, ~r/(DEB\d+)/)
        name = extract_debenture_name(desc)

        {:ok,
         %{
           asset_type: "debenture",
           operation: "compra",
           asset_name: name,
           ticker: ticker,
           identifier: ticker
         }}

      # Precatório — compra
      String.contains?(norm, "compra de precatorio") ->
        {:ok,
         %{
           asset_type: "precatorio",
           operation: "compra",
           asset_name: "Precatório Federal",
           ticker: nil,
           identifier: nil
         }}

      # Precatório — liquidação (venda/retorno)
      String.contains?(norm, "precatorio") and String.contains?(norm, "liquidacao") ->
        {:ok,
         %{
           asset_type: "precatorio",
           operation: "venda",
           asset_name: "Precatório Federal",
           ticker: nil,
           identifier: nil
         }}

      # Criptomoeda — compra
      String.contains?(norm, "compra de criptomoeda") ->
        crypto_name = extract_after(desc, ~r/Criptomoeda\s+(.+)/i)
        {name, ticker} = crypto_info(crypto_name)

        {:ok,
         %{
           asset_type: "cripto",
           operation: "compra",
           asset_name: name,
           ticker: ticker,
           identifier: nil
         }}

      # Criptomoeda — venda
      String.contains?(norm, "venda de criptomoeda") ->
        crypto_name = extract_after(desc, ~r/Criptomoeda\s+(.+)/i)
        {name, ticker} = crypto_info(crypto_name)

        {:ok,
         %{
           asset_type: "cripto",
           operation: "venda",
           asset_name: name,
           ticker: ticker,
           identifier: nil
         }}

      # Operação Estruturada — compra
      String.contains?(norm, "compra de operacao estruturada") ->
        {:ok,
         %{
           asset_type: "op_estruturada",
           operation: "compra",
           asset_name: "Operação Estruturada",
           ticker: nil,
           identifier: nil
         }}

      # Operação Estruturada — liquidação (venda/retorno)
      String.contains?(norm, "liquidacao de operacao estruturada") ->
        {:ok,
         %{
           asset_type: "op_estruturada",
           operation: "venda",
           asset_name: "Operação Estruturada",
           ticker: nil,
           identifier: nil
         }}

      # INSS / Recebíveis Judiciais
      String.contains?(norm, "investimento em inss") ->
        ticker = extract_id(desc, ~r/(INSS\d+)/)

        {:ok,
         %{
           asset_type: "recebiveis",
           operation: "compra",
           asset_name: "Recebível Judicial (INSS)",
           ticker: ticker,
           identifier: ticker
         }}

      # Fallback — operação não reconhecida
      true ->
        :error
    end
  end

  defp normalize(str) do
    str
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/[\x{0300}-\x{036f}]/u, "")
  end

  # ── Helpers ──

  defp extract_id(desc, pattern) do
    case Regex.run(pattern, desc) do
      [_, id] -> id
      _ -> nil
    end
  end

  defp extract_after(desc, pattern) do
    case Regex.run(pattern, desc) do
      [_, value] -> String.trim(value)
      _ -> desc
    end
  end

  defp extract_debenture_name(desc) do
    cond do
      String.contains?(desc, "Especial 1 ano") -> "Debênture Especial 1 ano"
      String.contains?(desc, "Especial 6 meses") -> "Debênture Especial 6 meses"
      String.contains?(desc, "Liquidez D+1") -> "Debênture Liquidez D+1"
      true -> "Debênture"
    end
  end

  defp crypto_info(name) do
    name = String.trim(name)

    cond do
      String.contains?(name, "Bitcoin") -> {"Bitcoin", "BTC"}
      String.contains?(name, "Ethereum") -> {"Ethereum", "ETH"}
      true -> {name, nil}
    end
  end
end
