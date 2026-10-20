defmodule Grana.Banking.KeywordCategorizer do
  @moduledoc """
  Classificador determinístico por palavra-chave: **Investimentos** (aplicação,
  resgate, compra e venda de FII, ações e cripto, saldo da NuInvest, operação na B3,
  capitalização) e **Impostos e Taxas** (IOF, DAS/DAS MEI (Simples Nacional),
  IRRF/IRPF, IPTU, IPVA, INSS, FGTS, DARF, ISSQN/COFINS, além de multa, juros de mora,
  tarifa, anuidade, imposto/tributo/encargo).

  Roda **antes da IA** na importação (preenchendo o que as regras do usuário não
  cobriram) e também alimenta o re-cálculo de dados já importados.
  """

  # Siglas de tributos — casadas como TOKEN inteiro (evita falso-positivo dentro
  # de outra palavra, ex.: "iof" não casa em "biofarma").
  @tax_tokens ~w(iof irrf irpf iptu ipva issqn cofins inss fgts darf)

  # Termos inequívocos (substring) — seguros para recategorizar dados existentes.
  @tax_strict_contains [
    "imposto",
    "tributo",
    "multa",
    "anuidade",
    "juros de mora",
    "das mei",
    "das-mei",
    "simples nacional"
  ]

  # Termos mais amplos (taxas/tarifas em geral) — usados só na importação, quando
  # a transação ainda está sem categoria.
  @tax_broad_contains @tax_strict_contains ++ ["taxa", "tarifa", "encargo"]

  # Movements between the account and the user's own investments, by how the bank
  # starts the description ("Resgate RDB", "Compra de FII - ABCD11", "Inv/ op na b3").
  # Without a category they would count as spending or income.
  @investment_prefixes [
    "aplicacao",
    "resgate",
    "compra de fii",
    "venda de fii",
    "compra de acoes",
    "venda de acoes",
    "compra de criptomoedas",
    "venda de criptomoedas",
    "venda de nucoins",
    "transferencia de saldo nuinvest",
    "inv/ op na b3",
    "capitalizacao"
  ]

  @doc "Categoria determinística para a descrição, ou nil."
  def categorize(description) do
    cond do
      investment?(description) -> "Investimentos"
      tax?(description) -> "Impostos e Taxas"
      true -> nil
    end
  end

  @doc "Movimento entre a conta e os investimentos do próprio usuário."
  def investment?(description) do
    norm = normalize(description)
    Enum.any?(@investment_prefixes, &String.starts_with?(norm, &1))
  end

  @doc "Reconhece imposto/taxa de forma ampla (inclui taxa/tarifa genéricas)."
  def tax?(description), do: keyword_match?(description, @tax_broad_contains)

  @doc "Reconhece imposto inequívoco (estrito) — para recategorizar o existente."
  def clear_tax?(description), do: keyword_match?(description, @tax_strict_contains)

  @doc """
  Termos (substring) para PRÉ-FILTRAR candidatos no banco antes do `clear_tax?/1`
  preciso. É um superset do casamento estrito (token ⊂ substring), então não
  perde nenhum match — evita carregar a tabela inteira em memória.
  """
  def strict_db_keywords, do: @tax_tokens ++ @tax_strict_contains

  defp keyword_match?(description, contains_list) do
    norm = normalize(description)
    toks = String.split(norm, ~r/[^a-z0-9]+/u, trim: true)

    Enum.any?(@tax_tokens, &(&1 in toks)) or
      Enum.any?(contains_list, &String.contains?(norm, &1))
  end

  defp normalize(nil), do: ""

  defp normalize(text) do
    text
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[\x{0300}-\x{036f}]/u, "")
  end
end
