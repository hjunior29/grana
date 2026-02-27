defmodule Grana.Investments.Parsers.PdfExtractor do
  @moduledoc """
  Extrai transações de investimento de PDFs usando IA (Google Gemini).
  Funciona para qualquer instituição de investimento.
  """

  alias Grana.AI.Provider
  alias Grana.Investments.Constants

  def extract(file_content, institution_or_user_id) do
    user_id =
      case institution_or_user_id do
        id when is_integer(id) -> id
        _slug -> nil
      end

    case get_ai_config(user_id) do
      {:error, reason} -> {:error, reason}
      {:ok, config} -> do_extract(file_content, config)
    end
  end

  defp get_ai_config(nil), do: {:error, "API Key necessária para processar PDFs de investimentos"}

  defp get_ai_config(user_id) do
    Grana.Accounts.get_user_ai_config(user_id)
  end

  defp do_extract(file_content, config) do
    encoded = Base.encode64(file_content)

    prompt = """
    Analise este extrato de investimentos e extraia TODAS as transações.

    Para cada transação, retorne um JSON array com objetos contendo:
    - "date": data no formato "YYYY-MM-DD"
    - "asset_name": nome completo do ativo
    - "asset_ticker": código/ticker do ativo (ex: PETR4, ITSA4, KNRI11)
    - "asset_type": um de: acao, fii, etf, bdr, renda_fixa, tesouro, cripto, fundo, outro
    - "operation": um de: compra, venda, dividendo, jcp, rendimento, amortizacao, taxa, outro
    - "quantity": quantidade (número decimal)
    - "unit_price": preço unitário (número decimal)
    - "total_amount": valor total (número decimal, sempre positivo)
    - "fees": taxas/custos (número decimal)

    Retorne APENAS o JSON array, sem texto adicional.
    Se não encontrar transações, retorne [].
    """

    ai_config = Map.merge(config, %{temperature: 0.1, max_output_tokens: 4096})

    case Provider.generate_content_with_file(prompt, encoded, "application/pdf", ai_config) do
      {:ok, response_body} -> parse_response(response_body)
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_response(response_body) do
    text = Provider.extract_text(response_body)

    json_text =
      case Regex.run(~r/\[.*\]/s, text) do
        [match] -> match
        _ -> text
      end

    case Jason.decode(json_text) do
      {:ok, items} when is_list(items) ->
        {transactions, warnings} =
          Enum.reduce(items, {[], []}, fn item, {txns, warns} ->
            case parse_item(item) do
              nil ->
                desc = item["asset_name"] || item["asset_ticker"] || "?"
                {txns, ["Item ignorado (PDF): #{desc}" | warns]}

              txn ->
                {[txn | txns], warns}
            end
          end)

        case Enum.reverse(transactions) do
          [] -> {:error, "Nenhuma transação encontrada no PDF"}
          txns -> {:ok, txns, Enum.reverse(warnings)}
        end

      _ ->
        {:error, "Falha ao processar resposta da IA"}
    end
  end

  defp parse_item(item) do
    with {:ok, date} <- parse_date(item["date"]),
         total when not is_nil(total) <- parse_decimal(item["total_amount"]) do
      %{
        date: date,
        asset_name: item["asset_name"] || "N/A",
        asset_ticker: item["asset_ticker"],
        asset_type: validate_type(item["asset_type"], "outro"),
        operation: validate_operation(item["operation"], "outro"),
        quantity: parse_decimal(item["quantity"]) || Decimal.new(0),
        unit_price: parse_decimal(item["unit_price"]) || Decimal.new(0),
        total_amount: Decimal.abs(total),
        fees: parse_decimal(item["fees"]) || Decimal.new(0),
        original_description: "#{item["operation"]} #{item["asset_ticker"] || item["asset_name"]}"
      }
    else
      _ -> nil
    end
  end

  defp parse_date(nil), do: :error

  defp parse_date(date_str) when is_binary(date_str) do
    Date.from_iso8601(date_str)
  end

  defp parse_date(_), do: :error

  defp parse_decimal(nil), do: nil
  defp parse_decimal(val) when is_number(val), do: Decimal.from_float(val / 1)

  defp parse_decimal(val) when is_binary(val) do
    case Decimal.parse(val) do
      {d, _} -> d
      :error -> nil
    end
  end

  defp parse_decimal(_), do: nil

  defp validate_type(type, _default) when type in unquote(Constants.asset_types()), do: type
  defp validate_type(_, default), do: default

  defp validate_operation(op, _default) when op in unquote(Constants.operations()), do: op
  defp validate_operation(_, default), do: default
end
