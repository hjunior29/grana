defmodule Grana.AI.Provider do
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

  def extract_text(response_body) do
    response_body
    |> get_in(["candidates", Access.at(0), "content", "parts", Access.at(0), "text"])
    |> to_string()
  end

  @doc """
  Motivo de término da geração (ex.: "STOP", "MAX_TOKENS", "SAFETY"), quando
  disponível na resposta. Usado para diagnosticar respostas truncadas/bloqueadas.
  """
  def finish_reason(response_body) do
    get_in(response_body, ["candidates", Access.at(0), "finishReason"])
  end

  defp provider_module("gemini"), do: Grana.AI.Providers.Gemini
end
