defmodule Grana.AI.Provider do
  @moduledoc """
  Fachada sobre os provedores de IA. A `config` vem de `Grana.AI.resolve_config/1`:
  `%{provider: kind, model:, api_key:, base_url:, name:}` mais `temperature`,
  `max_output_tokens` e `receive_timeout` opcionais, que cada chamador define.

  `kind` é `"gemini"`, `"openai"`, `"anthropic"` ou `"openai_compatible"` (qualquer
  serviço com a API de chat da OpenAI: OpenRouter, Groq, Ollama...). As respostas
  são lidas por `extract_text/1` e `finish_reason/1` em qualquer um dos formatos.
  """

  @callback generate_content(prompt :: String.t(), config :: map()) ::
              {:ok, map()} | {:error, any()}

  @callback generate_content_with_file(
              file_base64 :: String.t(),
              mime :: String.t(),
              prompt :: String.t(),
              config :: map()
            ) :: {:ok, map()} | {:error, any()}

  def generate_content(prompt, %{provider: provider} = config) do
    provider_module(provider).generate_content(prompt, config)
  end

  def generate_content_with_file(file_base64, mime, prompt, %{provider: provider} = config) do
    provider_module(provider).generate_content_with_file(file_base64, mime, prompt, config)
  end

  @doc "Texto da resposta, no formato do Gemini, da OpenAI (e compatíveis) ou da Anthropic."
  def extract_text(%{"candidates" => _} = body) do
    body
    |> get_in(["candidates", Access.at(0), "content", "parts", Access.at(0), "text"])
    |> to_string()
  end

  def extract_text(%{"choices" => _} = body) do
    case get_in(body, ["choices", Access.at(0), "message", "content"]) do
      text when is_binary(text) -> text
      parts when is_list(parts) -> join_text(parts)
      _ -> ""
    end
  end

  def extract_text(%{"content" => parts}) when is_list(parts), do: join_text(parts)
  def extract_text(_body), do: ""

  defp join_text(parts) do
    parts
    |> Enum.flat_map(fn
      %{"text" => text} when is_binary(text) -> [text]
      _ -> []
    end)
    |> Enum.join()
  end

  @doc """
  Motivo de término da geração, normalizado para o vocabulário do Gemini
  (`"STOP"`, `"MAX_TOKENS"`, `"SAFETY"`...), quando disponível. Usado para
  diagnosticar respostas truncadas ou bloqueadas, de qualquer provedor.
  """
  def finish_reason(%{"candidates" => _} = body) do
    get_in(body, ["candidates", Access.at(0), "finishReason"])
  end

  def finish_reason(%{"choices" => _} = body) do
    body |> get_in(["choices", Access.at(0), "finish_reason"]) |> normalize_reason()
  end

  def finish_reason(%{"stop_reason" => reason}), do: normalize_reason(reason)
  def finish_reason(_body), do: nil

  defp normalize_reason(nil), do: nil
  defp normalize_reason(reason) when reason in ["stop", "end_turn", "stop_sequence"], do: "STOP"
  defp normalize_reason(reason) when reason in ["length", "max_tokens"], do: "MAX_TOKENS"
  defp normalize_reason("content_filter"), do: "SAFETY"
  defp normalize_reason(reason), do: String.upcase(reason)

  defp provider_module("gemini"), do: Grana.AI.Providers.Gemini
  defp provider_module("anthropic"), do: Grana.AI.Providers.Anthropic

  defp provider_module(kind) when kind in ["openai", "openai_compatible"],
    do: Grana.AI.Providers.OpenAI
end
