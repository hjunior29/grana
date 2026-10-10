defmodule Grana.OpenFinance.Pluggy do
  @moduledoc """
  Cliente HTTP da API da Pluggy (https://docs.pluggy.ai).

  Cada chamada recebe as credenciais da aplicação (`%{client_id, client_secret}`),
  troca-as por uma API key (`POST /auth`) e reaproveita essa chave durante sua
  validade (2h), como a Pluggy recomenda. Roda só no servidor: o navegador recebe
  no máximo um connect token (30 min, escopo restrito ao Item criado) para abrir
  o widget Pluggy Connect.
  """

  @base_url "https://api.pluggy.ai"
  @receive_timeout 30_000

  # A API key vale 2h; renovamos com folga para não usar uma chave prestes a expirar.
  @api_key_ttl_seconds 110 * 60

  # Conector "MeuPluggy": o caminho gratuito para uso pessoal (suas próprias contas).
  @meu_pluggy_connector_id 200

  def meu_pluggy_connector_id, do: @meu_pluggy_connector_id

  @doc "Credenciais definidas no ambiente (PLUGGY_CLIENT_ID/PLUGGY_CLIENT_SECRET), se houver."
  def env_credentials do
    with client_id when is_binary(client_id) <- config(:client_id),
         client_secret when is_binary(client_secret) <- config(:client_secret) do
      %{client_id: client_id, client_secret: client_secret}
    else
      _ -> nil
    end
  end

  @doc "URL pública (HTTPS) que a Pluggy chama nos webhooks (PLUGGY_WEBHOOK_URL)."
  def webhook_url, do: config(:webhook_url)

  @doc "Confere as credenciais trocando-as por uma API key."
  def verify_credentials(credentials) do
    with {:ok, _api_key} <- api_key(credentials), do: :ok
  end

  @doc "Cria um connect token para abrir o widget. `client_user_id` vai para o Item e para os webhooks."
  def create_connect_token(credentials, client_user_id) do
    body = %{options: %{clientUserId: client_user_id}}

    with {:ok, %{"accessToken" => token}} <-
           request(credentials, :post, "/connect_token", json: body) do
      {:ok, token}
    end
  end

  def get_item(credentials, item_id), do: request(credentials, :get, "/items/#{item_id}")

  def delete_item(credentials, item_id) do
    with {:ok, _} <- request(credentials, :delete, "/items/#{item_id}"), do: :ok
  end

  def list_accounts(credentials, item_id) do
    with {:ok, %{"results" => accounts}} <-
           request(credentials, :get, "/accounts", params: [itemId: item_id]) do
      {:ok, accounts}
    end
  end

  @doc "Todas as transações da conta (até 12 meses), seguindo o cursor do `/v2/transactions`."
  def list_transactions(credentials, account_id) do
    fetch_transaction_pages(credentials, "?" <> URI.encode_query(accountId: account_id), [])
  end

  defp fetch_transaction_pages(credentials, query, acc) do
    case request(credentials, :get, "/v2/transactions" <> query) do
      {:ok, %{"results" => results, "next" => next}} when is_binary(next) ->
        fetch_transaction_pages(credentials, next, [results | acc])

      {:ok, %{"results" => results}} ->
        {:ok, [results | acc] |> Enum.reverse() |> Enum.concat()}

      {:error, _} = error ->
        error
    end
  end

  def list_webhooks(credentials) do
    with {:ok, %{"results" => webhooks}} <- request(credentials, :get, "/webhooks"),
         do: {:ok, webhooks}
  end

  def create_webhook(credentials, url, event, headers) do
    request(credentials, :post, "/webhooks", json: %{url: url, event: event, headers: headers})
  end

  def delete_webhook(credentials, webhook_id) do
    with {:ok, _} <- request(credentials, :delete, "/webhooks/#{webhook_id}"), do: :ok
  end

  defp request(credentials, method, path, opts \\ []) do
    with {:ok, api_key} <- api_key(credentials) do
      case do_request(method, path, api_key, opts) do
        # Chave revogada/expirada antes do previsto: renova uma vez e tenta de novo.
        {:error, :unauthorized} ->
          :persistent_term.erase(api_key_term(credentials))

          with {:ok, api_key} <- api_key(credentials) do
            do_request(method, path, api_key, opts)
          end

        result ->
          result
      end
    end
  end

  defp do_request(method, path, api_key, opts) do
    [method: method, url: @base_url <> path, headers: [{"x-api-key", api_key}]]
    |> Keyword.merge(opts)
    |> Keyword.merge(receive_timeout: @receive_timeout, retry: false)
    |> Req.request()
    |> handle_response()
  end

  defp api_key(credentials) do
    now = System.monotonic_time(:second)

    case :persistent_term.get(api_key_term(credentials), nil) do
      {api_key, expires_at} when expires_at > now -> {:ok, api_key}
      _ -> authenticate(credentials, now)
    end
  end

  # Uma chave em cache por par de credenciais: trocar o secret na tela já força nova autenticação.
  defp api_key_term(%{client_id: client_id, client_secret: client_secret}) do
    {__MODULE__, :api_key, client_id, :crypto.hash(:sha256, client_secret)}
  end

  defp authenticate(%{client_id: client_id, client_secret: client_secret} = credentials, now) do
    [
      method: :post,
      url: @base_url <> "/auth",
      json: %{clientId: client_id, clientSecret: client_secret}
    ]
    |> Keyword.merge(receive_timeout: @receive_timeout, retry: false)
    |> Req.request()
    |> handle_response()
    |> case do
      {:ok, %{"apiKey" => api_key}} ->
        :persistent_term.put(api_key_term(credentials), {api_key, now + @api_key_ttl_seconds})
        {:ok, api_key}

      {:error, :unauthorized} ->
        {:error, :invalid_credentials}

      {:error, _} = error ->
        error
    end
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) when status in 200..299,
    do: {:ok, body}

  # API key inválida/expirada volta 403 (API_KEY_MISSING_OR_INVALID); credenciais erradas no /auth, 401.
  defp handle_response({:ok, %Req.Response{status: status}}) when status in [401, 403],
    do: {:error, :unauthorized}

  defp handle_response({:ok, %Req.Response{status: 404}}), do: {:error, :not_found}
  defp handle_response({:ok, %Req.Response{status: 429}}), do: {:error, :rate_limited}

  defp handle_response({:ok, %Req.Response{status: status, body: body}}),
    do: {:error, {:http_error, status, error_message(body)}}

  defp handle_response({:error, exception}),
    do: {:error, {:transport, Exception.message(exception)}}

  defp error_message(%{"message" => message}) when is_binary(message), do: message
  defp error_message(_), do: nil

  defp config(key) do
    case Application.get_env(:grana, :pluggy, [])[key] do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end
end
