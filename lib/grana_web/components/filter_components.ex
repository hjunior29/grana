defmodule GranaWeb.FilterComponents do
  @moduledoc """
  Grupos de chips da barra de filtros (período, banco, fonte e tipo). Compõem o
  `<.filter_bar>` do Painel, das Despesas fixas e da Análise: cada tela passa só o
  estado e os nomes dos eventos.
  """
  use Phoenix.Component

  import GranaWeb.CoreComponents, only: [icon: 1]
  import GranaWeb.UiComponents

  alias Grana.Banking

  @doc "Ano e mês. `selected_year` e `selected_month` são nil quando só \"Todos\" está ativo."
  attr :years, :list, required: true
  attr :selected_year, :any, default: nil
  attr :months, :list, required: true, doc: "meses (1..12) com dados no ano"
  attr :selected_month, :any, default: nil
  attr :all_years, :boolean, default: false, doc: "mostra o chip \"Todos\" dos anos"
  attr :all_years_active, :boolean, default: false
  attr :all_months_active, :boolean, required: true
  attr :all_months_label, :string, default: "Todos"

  def period_filter(assigns) do
    ~H"""
    <.chip_group label="Período">
      <.chip :if={@all_years} active={@all_years_active} phx-click="select_view_total">Todos</.chip>
      <.chip
        :for={y <- @years}
        active={y == @selected_year}
        phx-click="select_year"
        phx-value-year={y}
      >
        {y}
      </.chip>
    </.chip_group>
    <.chip_group>
      <.chip active={@all_months_active} phx-click="select_month" phx-value-month="all">
        {@all_months_label}
      </.chip>
      <.chip
        :for={m <- @months}
        active={m == @selected_month}
        phx-click="select_month"
        phx-value-month={m}
      >
        {Banking.month_name_short(m)}
      </.chip>
    </.chip_group>
    """
  end

  attr :banks, :list, required: true
  attr :selected, :string, required: true
  attr :event, :string, default: "select_bank"

  def bank_filter(assigns) do
    ~H"""
    <.chip_group :if={@banks != []} label="Banco">
      <.chip active={@selected == "all"} phx-click={@event} phx-value-bank="all">Todos</.chip>
      <.chip :for={b <- @banks} active={@selected == b} phx-click={@event} phx-value-bank={b}>
        <img src={bank_logo_url(b)} alt="" class="size-4 rounded-full" />
        <span class="hidden sm:inline">{String.capitalize(b)}</span>
        <span class="sr-only sm:hidden">{String.capitalize(b)}</span>
      </.chip>
    </.chip_group>
    """
  end

  attr :selected, :string, required: true
  attr :event, :string, required: true
  attr :param, :string, default: "type", doc: "nome do phx-value (type ou source)"

  def source_filter(assigns) do
    ~H"""
    <.chip_group label="Fonte">
      <.chip active={@selected == "all"} {%{"phx-click" => @event, "phx-value-#{@param}" => "all"}}>
        Todas
      </.chip>
      <.chip
        active={@selected == "extrato"}
        {%{"phx-click" => @event, "phx-value-#{@param}" => "extrato"}}
      >
        <.icon name="hero-banknotes" class="size-3" />
        <span class="hidden sm:inline">Extrato</span>
        <span class="sr-only sm:hidden">Extrato</span>
      </.chip>
      <.chip
        active={@selected == "fatura"}
        {%{"phx-click" => @event, "phx-value-#{@param}" => "fatura"}}
      >
        <.icon name="hero-credit-card" class="size-3" />
        <span class="hidden sm:inline">Fatura</span>
        <span class="sr-only sm:hidden">Fatura</span>
      </.chip>
    </.chip_group>
    """
  end

  attr :selected, :string, required: true
  attr :event, :string, default: "select_txn_type"

  def movement_filter(assigns) do
    ~H"""
    <.chip_group label="Tipo">
      <.chip active={@selected == "all"} phx-click={@event} phx-value-txn_type="all">Todas</.chip>
      <.chip active={@selected == "debit"} phx-click={@event} phx-value-txn_type="debit">
        Despesas
      </.chip>
      <.chip active={@selected == "credit"} phx-click={@event} phx-value-txn_type="credit">
        Receitas
      </.chip>
    </.chip_group>
    """
  end
end
