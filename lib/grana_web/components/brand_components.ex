defmodule GranaWeb.BrandComponents do
  @moduledoc """
  Marca do Grana: o símbolo e o nome em Martian Mono.

  O símbolo resume o app: a moeda no centro (a de 1 real, bimetálica), o anel das
  categorias (com as cores das categorias padrão) e, em volta, os 12 meses — verdes
  quando sobrou, vermelhos quando faltou, cada um do tamanho do mês. Tem versão clara
  e escura; o CSS (`.grana-logo`) mostra a do tema ativo.

  O nome é desenhado como vetor, e não com `font-family`, porque a CSP do app não
  carrega fontes externas; assim ele sai igual em qualquer máquina e herda a cor do
  texto (`currentColor`) de cada tema e estilo visual.
  """
  use GranaWeb, :html

  @wordmark_path "M59 61Q59 68.7 55.3 74.3Q51.6 79.9 44.7 82.9Q37.9 86 28.5 86Q20.7 86 14.6 83.6Q8.5 81.2 4.7 76.8Q0.9 72.4 0 66.3H17.9Q19.5 68.5 22.3 69.7Q25.1 71 28.5 71Q34.4 71 37.7 68.3Q41 65.7 41 61V54.5H37Q35.4 57.6 31.7 59.4Q28.1 61.2 23.6 61.2Q16.4 61.2 11.1 57.6Q5.8 53.9 2.9 47.3Q0 40.6 0 31.5Q0 21.9 2.9 15Q5.8 8 11.1 4.2Q16.4 0.4 23.6 0.4Q28.2 0.4 31.9 2.4Q35.5 4.4 37.1 7.9H41V2H59ZM17.3 31.2Q17.3 38.3 20.5 42.3Q23.8 46.2 29.6 46.2Q35.4 46.2 38.7 42.3Q41.9 38.3 41.9 31.2Q41.9 24 38.7 20.1Q35.4 16.2 29.6 16.2Q23.8 16.2 20.5 20.1Q17.3 24 17.3 31.2ZM73 2H100.5V8H104.5Q106.1 4.2 109.5 2.2Q113 0.1 117.3 0.1Q124.6 0.1 128.2 5.9Q131.8 11.6 131.8 23.1V33.3H113.6V25.3Q113.6 17.5 108 17.5Q104.4 17.5 102.8 20.7Q101.1 23.9 101.1 30.7V48.2H118.1V64H73.9V48.2H83.9V17.8H73ZM180.9 24.7V37.5L167.4 39.6Q164.6 40 163 41.6Q161.3 43.1 161.3 45.5Q161.3 48.1 162.9 49.5Q164.5 51 167.9 51Q171.3 51 174 49.6Q176.7 48.2 178.3 45.8Q179.9 43.5 179.9 40.6V25Q179.9 20.1 177.5 17.7Q175.1 15.3 170 15.3Q166.6 15.3 164.1 16.4Q161.5 17.5 159.9 19.6Q158.4 21.7 157.8 24.7H140.5Q141.2 17 145 11.5Q148.8 5.9 155.2 3Q161.6 0 170 0Q183.4 0 190.4 6.1Q197.5 12.1 197.5 23.6V64H179.9V57.7H175.9Q174.3 61.5 171.1 63.5Q167.8 65.5 162.5 65.5Q156.8 65.5 152.5 63.2Q148.1 60.9 145.7 56.8Q143.2 52.7 143.2 47.4Q143.2 39.1 148.4 34Q153.5 28.9 163.1 27.4ZM213.7 64V2H231.7V8H235.7Q237.6 4.2 241.2 2.1Q244.9 0 249.7 0Q255.7 0 259.9 2.9Q264.1 5.8 266.3 11.4Q268.5 17 268.5 25V64H250.5V29.3Q250.5 23 248.2 19.8Q245.8 16.7 241.2 16.7Q236.4 16.7 234.1 19.8Q231.7 23 231.7 29.3V64ZM320.9 24.7V37.5L307.4 39.6Q304.6 40 303 41.6Q301.3 43.1 301.3 45.5Q301.3 48.1 302.9 49.5Q304.5 51 307.9 51Q311.3 51 314 49.6Q316.7 48.2 318.3 45.8Q319.9 43.5 319.9 40.6V25Q319.9 20.1 317.5 17.7Q315.1 15.3 310 15.3Q306.6 15.3 304.1 16.4Q301.5 17.5 299.9 19.6Q298.4 21.7 297.8 24.7H280.5Q281.2 17 285 11.5Q288.8 5.9 295.2 3Q301.6 0 310 0Q323.4 0 330.4 6.1Q337.5 12.1 337.5 23.6V64H319.9V57.7H315.9Q314.3 61.5 311.1 63.5Q307.8 65.5 302.5 65.5Q296.8 65.5 292.5 63.2Q288.1 60.9 285.7 56.8Q283.2 52.7 283.2 47.4Q283.2 39.1 288.4 34Q293.5 28.9 303.1 27.4Z"

  @geometry %{
    # Jan→Dez a partir do topo, no sentido horário: tamanho do mês e se sobrou dinheiro.
    months: [
      %{size: 11.4, positive: true},
      %{size: 12.8, positive: true},
      %{size: 12.2, positive: false},
      %{size: 11.8, positive: true},
      %{size: 10.8, positive: false},
      %{size: 14.8, positive: true},
      %{size: 11.2, positive: true},
      %{size: 12.0, positive: false},
      %{size: 13.8, positive: true},
      %{size: 12.6, positive: true},
      %{size: 11.0, positive: false},
      %{size: 14.2, positive: true}
    ],
    # Categorias padrão (Banking.ensure_default_categories/1) com as cores delas — sem
    # verde nem vermelho, que ficam para o resultado dos meses.
    categories: [
      %{name: "Moradia", icon: "hero-home", color: "#8B5CF6", dark: "#A78BFA", span: 92},
      %{name: "Alimentação", icon: "hero-cake", color: "#F59E0B", dark: "#FBBF24", span: 74},
      %{name: "Transporte", icon: "hero-truck", color: "#3B82F6", dark: "#60A5FA", span: 64},
      %{name: "Lazer", icon: "hero-musical-note", color: "#EC4899", dark: "#F472B6", span: 50},
      %{name: "Compras", icon: "hero-shopping-bag", color: "#F97316", dark: "#FB923C", span: 40}
    ],
    month_colors: %{
      light: %{positive: "#009689", negative: "#EA003E"},
      dark: %{positive: "#00BAA6", negative: "#F43F5E"}
    },
    petal_inner: 8.0,
    ring: [4.8, 7.1],
    coin: 4.0
  }

  @doc "Geometria do símbolo (unidades de 32x32), a mesma de `priv/static/images/logo.svg`."
  def geometry, do: @geometry

  attr :class, :any, default: "size-7"

  def logo(assigns) do
    ~H"""
    <span class={["grana-logo", @class]}>
      <img src={~p"/images/logo.svg"} alt="" class="grana-logo-light" />
      <img src={~p"/images/logo-dark.svg"} alt="" class="grana-logo-dark" />
    </span>
    """
  end

  attr :class, :any, default: "h-5 w-auto"

  def wordmark(assigns) do
    assigns = assign(assigns, :path, @wordmark_path)

    ~H"""
    <svg
      viewBox="0 0 337.5 86"
      class={@class}
      fill="currentColor"
      role="img"
      aria-label="Grana"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path d={@path} />
    </svg>
    """
  end

  attr :class, :any, default: nil
  attr :logo_class, :string, default: "size-7"
  attr :wordmark_class, :string, default: "h-5 w-auto"

  def brand(assigns) do
    ~H"""
    <span class={["inline-flex items-center gap-2", @class]}>
      <.logo class={@logo_class} />
      <%!-- A caixa do nome reserva a perna do "g"; descer um pouco centraliza o miolo das letras com o símbolo. --%>
      <.wordmark class={[@wordmark_class, "translate-y-[8%]"]} />
    </span>
    """
  end
end
