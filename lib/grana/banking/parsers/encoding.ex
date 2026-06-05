defmodule Grana.Banking.Parsers.Encoding do
  @moduledoc """
  Normalização de codificação para CSVs de banco.

  Bancos brasileiros às vezes exportam em Latin-1/Windows-1252; lido como UTF-8,
  um acento (ex.: "ú" = byte 0xFA) vira byte inválido e o nome se corrompe.
  `to_utf8/1` converte para UTF-8 quando o conteúdo NÃO é UTF-8 válido (preservando
  os acentos); conteúdo já em UTF-8 passa intacto.

  Obs.: isto cobre apenas a entrada de CSV. PDFs são extraídos via `pdftotext -enc
  UTF-8`; quando a fonte do PDF não tem mapa Unicode (ToUnicode) para um glifo, o
  `pdftotext` emite um espaço no lugar do caractere — uma limitação da origem que
  não há como recuperar aqui.
  """

  @doc "Converte `content` para UTF-8 se ele não for UTF-8 válido (assume Latin-1)."
  def to_utf8(content) when is_binary(content) do
    if String.valid?(content) do
      content
    else
      case :unicode.characters_to_binary(content, :latin1, :utf8) do
        result when is_binary(result) ->
          result

        # Conversão parcial: preserva o que dá, substituindo só os bytes inválidos.
        {:incomplete, partial, _rest} when is_binary(partial) ->
          String.replace_invalid(partial)

        _ ->
          String.replace_invalid(content)
      end
    end
  end
end
