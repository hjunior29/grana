defmodule Granai.AI.Provider do
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

  defp provider_module("gemini"), do: Granai.AI.Providers.Gemini
end
