defmodule Grana.Investments.Constants do
  @moduledoc """
  Constantes centralizadas para o módulo de investimentos.
  Tipos de ativos, operações, labels, cores e badges.
  """

  @asset_types ~w(acao fii etf bdr renda_fixa tesouro cripto fundo nota_fiscal debenture precatorio recebiveis cri cra op_estruturada outro)
  @operations ~w(compra venda dividendo jcp rendimento amortizacao taxa outro)

  @buy_sell_ops ~w(compra venda)
  @dividend_ops ~w(dividendo jcp rendimento amortizacao)
  @proventos_ops ~w(compra venda dividendo jcp rendimento amortizacao)
  @income_ops_csv "dividendo,jcp,rendimento,amortizacao"

  @asset_type_labels %{
    "acao" => "Ações",
    "fii" => "FII",
    "etf" => "ETF",
    "bdr" => "BDR",
    "renda_fixa" => "Renda Fixa",
    "tesouro" => "Tesouro",
    "cripto" => "Cripto",
    "fundo" => "Fundo",
    "nota_fiscal" => "Nota Fiscal",
    "debenture" => "Debênture",
    "precatorio" => "Precatório",
    "recebiveis" => "Receb. Judiciais",
    "cri" => "CRI",
    "cra" => "CRA",
    "op_estruturada" => "Op. Estruturada",
    "outro" => "Outro"
  }

  @operation_labels %{
    "compra" => "Compra",
    "venda" => "Venda",
    "dividendo" => "Dividendo",
    "jcp" => "JCP",
    "rendimento" => "Rendimento",
    "amortizacao" => "Amortização",
    "taxa" => "Taxa",
    "outro" => "Outro"
  }

  @asset_colors %{
    "acao" => "#3B82F6",
    "fii" => "#8B5CF6",
    "etf" => "#06B6D4",
    "bdr" => "#F59E0B",
    "renda_fixa" => "#10B981",
    "tesouro" => "#EF4444",
    "cripto" => "#F97316",
    "fundo" => "#6366F1",
    "nota_fiscal" => "#14B8A6",
    "debenture" => "#EC4899",
    "precatorio" => "#78716C",
    "recebiveis" => "#A855F7",
    "cri" => "#22D3EE",
    "cra" => "#34D399",
    "op_estruturada" => "#94A3B8",
    "outro" => "#9CA3AF"
  }

  @asset_badges %{
    "acao" => "badge-info",
    "fii" => "badge-secondary",
    "etf" => "badge-accent",
    "bdr" => "badge-warning",
    "renda_fixa" => "badge-success",
    "tesouro" => "badge-error",
    "cripto" => "badge-warning",
    "fundo" => "badge-primary",
    "nota_fiscal" => "badge-accent",
    "debenture" => "badge-info",
    "precatorio" => "badge-secondary",
    "recebiveis" => "badge-primary",
    "cri" => "badge-success",
    "cra" => "badge-success",
    "op_estruturada" => "badge-secondary",
    "outro" => "badge-ghost"
  }

  def asset_types, do: @asset_types
  def operations, do: @operations
  def buy_sell_ops, do: @buy_sell_ops
  def dividend_ops, do: @dividend_ops
  def proventos_ops, do: @proventos_ops
  def income_ops_csv, do: @income_ops_csv

  def asset_type_label(type), do: Map.get(@asset_type_labels, type, "—")
  def operation_label(op), do: Map.get(@operation_labels, op, op)
  def asset_type_color(type), do: Map.get(@asset_colors, type, "#9CA3AF")
  def asset_type_badge(type), do: Map.get(@asset_badges, type, "badge-ghost")
  def asset_colors, do: @asset_colors
end
