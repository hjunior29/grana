defmodule Granai.Banking.Parsers.PdfExtractor do
  alias Granai.Banking.Parsers.InstallmentParser

  def extract(pdf_bytes, bank) do
    api_key = Application.get_env(:granai, :gemini_api_key) || System.get_env("GEMINI_API_KEY")

    case api_key do
      nil -> {:error, "GEMINI_API_KEY not configured"}
      key -> do_extract(pdf_bytes, bank, key)
    end
  end

  defp do_extract(pdf_bytes, bank, api_key) do
    base64 = Base.encode64(pdf_bytes)

    url =
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=#{api_key}"

    body = %{
      contents: [
        %{
          parts: [
            %{inline_data: %{mime_type: "application/pdf", data: base64}},
            %{text: prompt_for(bank)}
          ]
        }
      ],
      generationConfig: %{temperature: 0.1, maxOutputTokens: 8192}
    }

    case Req.post(url, json: body, receive_timeout: 120_000) do
      {:ok, %{status: 200, body: response_body}} ->
        parse_response(response_body)

      {:ok, %{status: status, body: body}} ->
        {:error, "Gemini API error: #{status} - #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  defp prompt_for("nubank") do
    """
    Extraia TODAS as transações deste extrato bancário do Nubank em formato PDF.

    Para cada transação, extraia:
    - date: data no formato DD/MM/YYYY
    - description: descrição completa da transação (ex: "Compra no débito SUPERMERCADO INOVACAO", "Transferência enviada pelo Pix Beltrano Augusto Exemplo", "Pagamento de fatura")
    - amount: valor absoluto como número decimal com ponto (ex: 142.50, não 142,50)
    - type: "credit" para entradas/recebimentos ou "debit" para saídas/pagamentos/compras

    REGRAS:
    - IGNORE linhas de "Total de entradas" e "Total de saídas", elas são subtotais e NÃO são transações
    - IGNORE linhas de saldo inicial, saldo final, rendimento líquido
    - Transações que aparecem após "Total de entradas" são do tipo "credit"
    - Transações que aparecem após "Total de saídas" são do tipo "debit"
    - A descrição deve incluir o tipo (ex: "Compra no débito") E o nome do estabelecimento/destinatário
    - Para transferências Pix, inclua o nome do destinatário/remetente na descrição
    - Valores devem ser POSITIVOS (sem sinal negativo)
    - PRESERVE informações de parcelas na descrição (ex: "Netflix - Parcela 1/3", "Compra Loja - Parcela 2/6")

    Retorne APENAS um JSON array, sem explicações:
    [{"date": "01/01/2026", "description": "Pagamento de fatura", "amount": 15.00, "type": "debit"}, ...]
    """
  end

  defp prompt_for("bradesco") do
    """
    Extraia TODAS as transações deste extrato bancário do Bradesco em formato PDF.

    Para cada transação, extraia:
    - date: data no formato DD/MM/YYYY
    - description: descrição completa incluindo a linha DES:/REM: quando existir (ex: "PIX QR CODE DINAMICO - 99 FOOD", "TRANSFERENCIA PIX - FLAMBRA LTDA", "PAGTO ELETRON COBRANCA - NU PAGAMENTOS SA")
    - amount: valor absoluto como número decimal com ponto (ex: 142.50, não 142,50)
    - type: "credit" se o valor está na coluna Crédito, "debit" se está na coluna Débito

    REGRAS:
    - IGNORE linhas de "COD. LANC. 0" (saldo inicial)
    - IGNORE linhas de "Total" (subtotais)
    - Quando houver "DES: nome" ou "REM: nome", inclua o nome na descrição separado por " - "
    - Valores devem ser POSITIVOS (sem sinal negativo)
    - Se uma transação tem valor tanto em Crédito quanto em Débito, trate como duas transações separadas
    - PRESERVE informações de parcelas na descrição (ex: "LOJA 1/3", "Compra 2/6")

    Retorne APENAS um JSON array, sem explicações:
    [{"date": "06/02/2026", "description": "PIX QR CODE DINAMICO - 99 FOOD", "amount": 17.18, "type": "debit"}, ...]
    """
  end

  defp prompt_for(_bank) do
    """
    Extraia TODAS as transações deste extrato bancário em formato PDF.

    Para cada transação, extraia:
    - date: data no formato DD/MM/YYYY
    - description: descrição completa da transação
    - amount: valor absoluto como número decimal com ponto (ex: 142.50)
    - type: "credit" para entradas/recebimentos ou "debit" para saídas/pagamentos

    REGRAS:
    - IGNORE linhas de subtotais, saldos e cabeçalhos
    - Valores devem ser POSITIVOS
    - Inclua todas as transações individuais
    - PRESERVE informações de parcelas na descrição (ex: "Parcela 1/3", "2/6")

    Retorne APENAS um JSON array, sem explicações:
    [{"date": "01/01/2026", "description": "Descrição", "amount": 100.00, "type": "debit"}, ...]
    """
  end

  defp parse_response(response_body) do
    text =
      response_body
      |> get_in(["candidates", Access.at(0), "content", "parts", Access.at(0), "text"])
      |> to_string()

    json_text =
      case Regex.run(~r/\[.*\]/s, text) do
        [match] -> match
        _ -> text
      end

    case Jason.decode(json_text) do
      {:ok, transactions} when is_list(transactions) ->
        parsed =
          transactions
          |> Enum.map(&parse_transaction/1)
          |> Enum.reject(&is_nil/1)

        case parsed do
          [] -> {:error, "No transactions found in PDF"}
          items -> {:ok, items}
        end

      _ ->
        {:error, "Falha ao processar resposta da IA"}
    end
  end

  defp parse_transaction(%{"date" => date_str, "description" => desc, "amount" => amount, "type" => type})
       when is_binary(date_str) and is_binary(desc) and is_binary(type) do
    case parse_date(date_str) do
      {:ok, date} ->
        decimal_amount = to_decimal(amount)
        trimmed_desc = String.trim(desc)
        {cleaned_desc, inst_current, inst_total} = InstallmentParser.extract(trimmed_desc)
        group_id = InstallmentParser.generate_group_id(cleaned_desc, inst_total)

        %{
          date: date,
          amount: if(type == "debit", do: Decimal.negate(decimal_amount), else: decimal_amount),
          type: type,
          identifier: nil,
          description: cleaned_desc,
          original_description: trimmed_desc,
          installment_current: inst_current,
          installment_total: inst_total,
          installment_group_id: group_id
        }

      _ ->
        nil
    end
  end

  defp parse_transaction(_), do: nil

  defp parse_date(date_str) do
    case String.split(date_str, "/") do
      [day, month, year] ->
        Date.new(
          String.to_integer(year),
          String.to_integer(month),
          String.to_integer(day)
        )

      _ ->
        :error
    end
  end

  defp to_decimal(val) when is_float(val), do: Decimal.from_float(val)
  defp to_decimal(val) when is_integer(val), do: Decimal.new(val)

  defp to_decimal(val) when is_binary(val) do
    case Decimal.parse(val) do
      {d, _} -> d
      :error -> Decimal.new(0)
    end
  end

  defp to_decimal(_), do: Decimal.new(0)
end
