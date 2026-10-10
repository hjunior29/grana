defmodule Grana.AI.HTTP do
  @moduledoc """
  Pedidos HTTP aos provedores de IA e tradução dos erros em mensagens amigáveis.
  Sempre com timeout, para uma chamada travada não segurar o worker ou a tela.
  """

  @default_receive_timeout 30_000

  @type result :: {:ok, term()} | {:http_error, pos_integer(), term()} | {:error, String.t()}

  @doc "POST JSON. `config[:receive_timeout]` limita a espera."
  @spec post(String.t(), list(), map(), map()) :: result()
  def post(url, headers, body, config) do
    url |> Req.post([json: body, headers: headers] ++ opts(config)) |> handle()
  end

  @spec get(String.t(), list(), keyword()) :: result()
  def get(url, headers, params \\ []) do
    url |> Req.get([headers: headers, params: params] ++ opts(%{})) |> handle()
  end

  defp opts(config), do: [receive_timeout: config[:receive_timeout] || @default_receive_timeout]

  defp handle({:ok, %{status: 200, body: body}}), do: {:ok, body}
  defp handle({:ok, %{status: status, body: body}}), do: {:http_error, status, body}

  defp handle({:error, %Req.TransportError{reason: :timeout}}),
    do: {:error, "A requisição demorou demais. Tente novamente."}

  defp handle({:error, %Req.TransportError{reason: reason}})
       when reason in [:econnrefused, :nxdomain],
       do:
         {:error,
          "Não foi possível conectar ao servidor da API. Verifique o endereço e sua conexão."}

  defp handle({:error, _reason}),
    do: {:error, "Falha na conexão com a API. Verifique sua internet e tente novamente."}

  @doc "Mensagem amigável para um erro HTTP de um provedor (`label` = nome para o usuário)."
  def friendly_error(status, body, label)

  def friendly_error(401, _body, label),
    do: "Chave de API inválida para #{label}. Verifique a chave nas Configurações."

  def friendly_error(403, _body, label),
    do:
      "A chave de API não tem permissão em #{label}. Confira se ela está ativa e com acesso ao modelo."

  def friendly_error(404, body, label),
    do: "Modelo ou endereço não encontrado em #{label}#{detail(body)}"

  def friendly_error(429, _body, _label),
    do: "Limite de requisições atingido. Aguarde alguns minutos e tente novamente."

  def friendly_error(status, _body, label) when status in [500, 502, 503, 529],
    do: "#{label} está indisponível no momento. Tente novamente em instantes."

  def friendly_error(status, body, _label) do
    case message(body) do
      nil -> "Erro inesperado da API (código #{status}). Tente novamente."
      msg -> "Erro da API (#{status}): #{msg}"
    end
  end

  @doc "Texto de erro do corpo, nos formatos OpenAI/Anthropic/Gemini."
  def message(%{"error" => %{"message" => msg}}) when is_binary(msg), do: msg
  def message(%{"error" => msg}) when is_binary(msg), do: msg
  def message(%{"message" => msg}) when is_binary(msg), do: msg
  def message(_), do: nil

  defp detail(body) do
    case message(body) do
      nil -> "."
      msg -> ": #{msg}"
    end
  end
end
