defmodule GranaiWeb.LandingLive do
  use GranaiWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Controle suas finanças")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen">
      <nav class="navbar bg-base-100/10 backdrop-blur-xl sticky top-0 z-50 border-b border-base-content/5 px-4 sm:px-6 lg:px-8">
        <div class="flex-1">
          <a href="/" class="flex items-center gap-2 text-xl font-bold tracking-tight">
            <img src={~p"/images/logo-32.png"} alt="" class="w-7 h-7" />
            <span style="font-family: 'Grand Hotel', cursive" class="text-2xl">Granai</span>
          </a>
        </div>
        <div class="flex-none">
          <div class="flex items-center gap-3">
            <Layouts.theme_toggle :if={!@current_scope} />
            <.link :if={!@current_scope} navigate={~p"/users/log-in"} class="btn btn-ghost btn-sm">
              Entrar
            </.link>
            <.link :if={!@current_scope} navigate={~p"/users/register"} class="btn btn-primary btn-sm">
              Criar Conta
            </.link>
            <.link :if={@current_scope} navigate={~p"/dashboard"} class="btn btn-primary btn-sm">
              Dashboard
            </.link>
          </div>
        </div>
      </nav>

      <%!-- Hero --%>
      <section class="py-24 px-4">
        <div class="max-w-4xl mx-auto text-center">
          <img
            src={~p"/images/logo-animated.gif"}
            alt="Granai"
            class="w-40 h-40 mx-auto mb-8 drop-shadow-xl"
          />
          <h1 class="text-5xl md:text-7xl font-bold tracking-tight leading-tight mb-6">
            Controle total das <br />
            <span style="font-family: 'Grand Hotel', cursive" class="text-primary text-6xl md:text-8xl font-normal">
              suas finanças
            </span>
          </h1>
          <p class="text-lg md:text-xl opacity-60 max-w-2xl mx-auto mb-10">
            Faça upload dos seus extratos bancários e tenha uma visão completa dos seus gastos.
            Categorização automática, gráficos intuitivos e análises detalhadas.
          </p>
          <div class="flex flex-col sm:flex-row gap-4 justify-center">
            <.link navigate={~p"/users/log-in"} class="btn btn-primary btn-lg">
              Começar Agora <.icon name="hero-arrow-right" class="size-5" />
            </.link>
            <a href="#dashboard-preview" class="btn btn-ghost btn-lg">
              Ver como funciona
            </a>
          </div>
        </div>
      </section>

      <%!-- Dashboard Preview --%>
      <section id="dashboard-preview" class="py-24 px-4 bg-base-200/50">
        <div class="max-w-6xl mx-auto">
          <div class="text-center mb-16">
            <p
              style="font-family: 'Grand Hotel', cursive"
              class="text-primary text-5xl mb-3"
            >
              Visão completa
            </p>
            <h2 class="text-3xl md:text-4xl font-bold tracking-tight mb-4">
              Dashboard inteligente
            </h2>
            <p class="text-lg opacity-60 max-w-xl mx-auto">
              Veja para onde vai cada centavo com gráficos interativos e resumos detalhados
            </p>
          </div>

          <div class="rounded-2xl border border-base-content/10 bg-base-200/30 p-4 md:p-8 shadow-xl">
            <%!-- Mock summary cards --%>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8">
              <div class="stat bg-base-100 rounded-xl shadow-sm">
                <div class="stat-title">Receitas</div>
                <div class="stat-value text-success text-2xl">R$ 8.450,00</div>
                <div class="stat-desc">12 transações</div>
              </div>
              <div class="stat bg-base-100 rounded-xl shadow-sm">
                <div class="stat-title">Despesas</div>
                <div class="stat-value text-error text-2xl">R$ 5.797,40</div>
                <div class="stat-desc">47 transações</div>
              </div>
              <div class="stat bg-base-100 rounded-xl shadow-sm">
                <div class="stat-title">Saldo</div>
                <div class="stat-value text-success text-2xl">R$ 2.652,60</div>
                <div class="stat-desc">Tudo categorizado</div>
              </div>
            </div>

            <%!-- Mock charts --%>
            <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
              <%!-- Donut chart --%>
              <div class="card bg-base-100 p-6 shadow-sm">
                <h3 class="font-semibold mb-4">Despesas por Categoria</h3>
                <div class="flex flex-col sm:flex-row items-center gap-6">
                  <svg viewBox="0 0 180 180" class="w-44 h-44 shrink-0">
                    <g transform="rotate(-90 90 90)">
                      <circle
                        cx="90"
                        cy="90"
                        r="70"
                        fill="none"
                        stroke="#F59E0B"
                        stroke-width="22"
                        stroke-dasharray="140.74 439.82"
                        stroke-dashoffset="0"
                      />
                      <circle
                        cx="90"
                        cy="90"
                        r="70"
                        fill="none"
                        stroke="#8B5CF6"
                        stroke-width="22"
                        stroke-dasharray="114.35 439.82"
                        stroke-dashoffset="-140.74"
                      />
                      <circle
                        cx="90"
                        cy="90"
                        r="70"
                        fill="none"
                        stroke="#3B82F6"
                        stroke-width="22"
                        stroke-dasharray="48.38 439.82"
                        stroke-dashoffset="-255.09"
                      />
                      <circle
                        cx="90"
                        cy="90"
                        r="70"
                        fill="none"
                        stroke="#F97316"
                        stroke-width="22"
                        stroke-dasharray="39.58 439.82"
                        stroke-dashoffset="-303.47"
                      />
                      <circle
                        cx="90"
                        cy="90"
                        r="70"
                        fill="none"
                        stroke="#EC4899"
                        stroke-width="22"
                        stroke-dasharray="36.50 439.82"
                        stroke-dashoffset="-343.05"
                      />
                      <circle
                        cx="90"
                        cy="90"
                        r="70"
                        fill="none"
                        stroke="#EF4444"
                        stroke-width="22"
                        stroke-dasharray="24.19 439.82"
                        stroke-dashoffset="-379.55"
                      />
                      <circle
                        cx="90"
                        cy="90"
                        r="70"
                        fill="none"
                        stroke="#64748B"
                        stroke-width="22"
                        stroke-dasharray="21.99 439.82"
                        stroke-dashoffset="-403.74"
                      />
                      <circle
                        cx="90"
                        cy="90"
                        r="70"
                        fill="none"
                        stroke="#A855F7"
                        stroke-width="22"
                        stroke-dasharray="14.07 439.82"
                        stroke-dashoffset="-425.73"
                      />
                    </g>
                    <text
                      x="90"
                      y="85"
                      text-anchor="middle"
                      class="fill-base-content text-xs opacity-50"
                    >
                      Total
                    </text>
                    <text
                      x="90"
                      y="100"
                      text-anchor="middle"
                      class="fill-base-content text-sm font-bold"
                    >
                      R$ 5.797
                    </text>
                  </svg>
                  <div class="space-y-2 flex-1 w-full">
                    <div :for={
                      {name, value, pct, color} <- [
                        {"Alimentação", "R$ 1.847", "32%", "#F59E0B"},
                        {"Moradia", "R$ 1.500", "26%", "#8B5CF6"},
                        {"Transporte", "R$ 650", "11%", "#3B82F6"},
                        {"Compras", "R$ 520", "9%", "#F97316"},
                        {"Lazer", "R$ 480", "8%", "#EC4899"},
                        {"Saúde", "R$ 320", "6%", "#EF4444"},
                        {"Pagamentos", "R$ 290", "5%", "#64748B"},
                        {"Assinaturas", "R$ 190", "3%", "#A855F7"}
                      ]
                    } class="flex items-center gap-2">
                      <div class="w-2.5 h-2.5 rounded-full shrink-0" style={"background:#{color}"} />
                      <span class="text-xs flex-1 truncate">{name}</span>
                      <span class="text-xs font-medium">{value}</span>
                      <span class="text-xs opacity-40 w-8 text-right">{pct}</span>
                    </div>
                  </div>
                </div>
              </div>

              <%!-- Daily bar chart --%>
              <div class="card bg-base-100 p-6 shadow-sm">
                <h3 class="font-semibold mb-4">Gastos Diários</h3>
                <div class="flex items-end gap-1 h-40">
                  <div
                    :for={
                      {day, h} <- [
                        {"01", 35},
                        {"02", 20},
                        {"03", 65},
                        {"04", 10},
                        {"05", 45},
                        {"06", 30},
                        {"07", 80},
                        {"08", 15},
                        {"09", 55},
                        {"10", 100},
                        {"11", 25},
                        {"12", 40},
                        {"13", 70},
                        {"14", 20},
                        {"15", 50},
                        {"16", 35},
                        {"17", 90},
                        {"18", 15},
                        {"19", 60},
                        {"20", 45},
                        {"21", 30},
                        {"22", 75},
                        {"23", 20},
                        {"24", 55},
                        {"25", 40},
                        {"26", 85},
                        {"27", 25},
                        {"28", 50},
                        {"29", 35},
                        {"30", 60}
                      ]
                    }
                    class="flex-1 flex flex-col items-center gap-1"
                  >
                    <div
                      class="w-full bg-primary/80 rounded-t hover:bg-primary transition-colors"
                      style={"height: #{h}%"}
                    />
                    <span class="text-[8px] opacity-40 hidden md:block">{day}</span>
                  </div>
                </div>
                <div class="flex justify-between mt-2 text-xs opacity-40">
                  <span>01/01</span>
                  <span>15/01</span>
                  <span>30/01</span>
                </div>
              </div>
            </div>

            <%!-- Mock top expenses table --%>
            <div class="card bg-base-100 p-6 shadow-sm">
              <h3 class="font-semibold mb-4">Top Despesas</h3>
              <div class="overflow-x-auto">
                <table class="table table-sm">
                  <thead>
                    <tr>
                      <th>Data</th>
                      <th>Descrição</th>
                      <th>Categoria</th>
                      <th class="text-right">Valor</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={
                      {date, desc, cat, color, val} <- [
                        {"03/01", "Aluguel Janeiro", "Moradia", "#8B5CF6", "R$ 1.500,00"},
                        {"10/01", "Supermercado Extra", "Alimentação", "#F59E0B", "R$ 487,32"},
                        {"17/01", "Farmácia São João", "Saúde", "#EF4444", "R$ 320,00"},
                        {"22/01", "Shopping - Roupas", "Compras", "#F97316", "R$ 289,90"},
                        {"07/01", "Posto Shell", "Transporte", "#3B82F6", "R$ 250,00"}
                      ]
                    }>
                      <td class="text-sm">{date}</td>
                      <td class="text-sm">{desc}</td>
                      <td>
                        <span
                          class="badge badge-sm"
                          style={"background-color: #{color}20; color: #{color}; border-color: #{color}40"}
                        >
                          {cat}
                        </span>
                      </td>
                      <td class="text-right text-sm font-medium text-error">{val}</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>
      </section>

      <%!-- Features --%>
      <section id="features" class="py-24 px-4">
        <div class="max-w-6xl mx-auto">
          <div class="text-center mb-16">
            <p
              style="font-family: 'Grand Hotel', cursive"
              class="text-primary text-5xl mb-3"
            >
              Simples e poderoso
            </p>
            <h2 class="text-3xl md:text-4xl font-bold tracking-tight mb-4">
              Tudo que você precisa
            </h2>
            <p class="text-lg opacity-60 max-w-xl mx-auto">
              Ferramentas poderosas para entender seus gastos e tomar melhores decisões financeiras
            </p>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
            <div class="card bg-base-200/50 p-6 hover:shadow-lg transition-shadow">
              <div class="w-12 h-12 rounded-xl bg-primary/10 flex items-center justify-center mb-4">
                <.icon name="hero-cloud-arrow-up" class="size-6 text-primary" />
              </div>
              <h3 class="font-semibold text-lg mb-2">Upload Simples</h3>
              <p class="opacity-60 text-sm">
                Arraste e solte seus extratos CSV. Suporte a Nubank e Bradesco com processamento instantâneo.
              </p>
            </div>

            <div class="card bg-base-200/50 p-6 hover:shadow-lg transition-shadow">
              <div class="w-12 h-12 rounded-xl bg-success/10 flex items-center justify-center mb-4">
                <.icon name="hero-tag" class="size-6 text-success" />
              </div>
              <h3 class="font-semibold text-lg mb-2">Categorização Inteligente</h3>
              <p class="opacity-60 text-sm">
                IA classifica automaticamente suas transações. Edite e o sistema aprende suas preferências.
              </p>
            </div>

            <div class="card bg-base-200/50 p-6 hover:shadow-lg transition-shadow">
              <div class="w-12 h-12 rounded-xl bg-info/10 flex items-center justify-center mb-4">
                <.icon name="hero-chart-bar" class="size-6 text-info" />
              </div>
              <h3 class="font-semibold text-lg mb-2">Gráficos Detalhados</h3>
              <p class="opacity-60 text-sm">
                Visualize seus gastos por categoria, acompanhe gastos diários e identifique padrões.
              </p>
            </div>

            <div class="card bg-base-200/50 p-6 hover:shadow-lg transition-shadow">
              <div class="w-12 h-12 rounded-xl bg-warning/10 flex items-center justify-center mb-4">
                <.icon name="hero-document-duplicate" class="size-6 text-warning" />
              </div>
              <h3 class="font-semibold text-lg mb-2">Upload em Batch</h3>
              <p class="opacity-60 text-sm">
                Envie até 20 extratos de uma vez. Múltiplos meses e bancos processados simultaneamente.
              </p>
            </div>

            <div class="card bg-base-200/50 p-6 hover:shadow-lg transition-shadow">
              <div class="w-12 h-12 rounded-xl bg-error/10 flex items-center justify-center mb-4">
                <.icon name="hero-magnifying-glass" class="size-6 text-error" />
              </div>
              <h3 class="font-semibold text-lg mb-2">Busca e Filtros</h3>
              <p class="opacity-60 text-sm">
                Encontre qualquer transação rapidamente. Filtre por categoria, data ou busque por descrição.
              </p>
            </div>

            <div class="card bg-base-200/50 p-6 hover:shadow-lg transition-shadow">
              <div class="w-12 h-12 rounded-xl bg-accent/10 flex items-center justify-center mb-4">
                <.icon name="hero-sparkles" class="size-6 text-accent" />
              </div>
              <h3 class="font-semibold text-lg mb-2">Aprendizado Contínuo</h3>
              <p class="opacity-60 text-sm">
                Corrija categorias uma vez e o sistema lembra para sempre. Suas regras são aplicadas automaticamente.
              </p>
            </div>
          </div>
        </div>
      </section>

      <%!-- Supported Banks --%>
      <section class="py-24 px-4 bg-base-200/50">
        <div class="max-w-6xl mx-auto">
          <div class="text-center mb-16">
            <p
              style="font-family: 'Grand Hotel', cursive"
              class="text-primary text-5xl mb-3"
            >
              Compatível
            </p>
            <h2 class="text-3xl md:text-4xl font-bold tracking-tight mb-4">
              Seus bancos, seus dados
            </h2>
            <p class="text-lg opacity-60 max-w-xl mx-auto">
              Importe extratos dos principais bancos brasileiros em segundos
            </p>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-8">
            <%!-- Nubank --%>
            <div class="card bg-base-200/50 border border-base-content/5 p-6">
              <div class="flex items-center gap-3 mb-5">
                <img src={~p"/images/nubank-logo.png"} alt="Nubank" class="w-8 h-8 rounded" />
                <h3 class="font-semibold text-lg">Nubank</h3>
                <span class="badge badge-sm badge-ghost">CSV</span>
              </div>
              <div class="mockup-code text-xs">
                <pre data-prefix="1"><code>Data,Valor,Identificador,Descrição</code></pre>
                <pre data-prefix="2"><code>02/01/2026,-45.90,abc123,Supermercado Extra</code></pre>
                <pre data-prefix="3"><code>03/01/2026,-12.50,def456,Uber *Trip</code></pre>
                <pre data-prefix="4"><code>05/01/2026,-89.90,ghi789,Amazon.com.br</code></pre>
                <pre data-prefix="5" class="text-warning"><code>07/01/2026,3500.00,jkl012,Transferência recebida</code></pre>
              </div>
            </div>

            <%!-- Bradesco --%>
            <div class="card bg-base-200/50 border border-base-content/5 p-6">
              <div class="flex items-center gap-3 mb-5">
                <img src={~p"/images/bradesco-logo.png"} alt="Bradesco" class="w-8 h-8 rounded" />
                <h3 class="font-semibold text-lg">Bradesco</h3>
                <span class="badge badge-sm badge-ghost">CSV</span>
              </div>
              <div class="mockup-code text-xs">
                <pre data-prefix="1"><code>Data;Histórico;Docto.;Crédito;Débito;Saldo</code></pre>
                <pre data-prefix="2"><code>06/02/2026;PIX TRANSF;98765;;150,00;4.850,00</code></pre>
                <pre data-prefix="3"><code>07/02/2026;PGTO BOLETO;54321;;890,00;3.960,00</code></pre>
                <pre data-prefix="4"><code>08/02/2026;COMPRA VISA;11223;;67,50;3.892,50</code></pre>
                <pre data-prefix="5" class="text-warning"><code>10/02/2026;REND B3;33445;245,80;;4.138,30</code></pre>
              </div>
            </div>
          </div>
        </div>
      </section>

      <%!-- AI Analysis Preview --%>
      <section class="py-24 px-4">
        <div class="max-w-6xl mx-auto">
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-12 items-center">
            <div>
              <p
                style="font-family: 'Grand Hotel', cursive"
                class="text-primary text-5xl mb-3"
              >
                Inteligência Artificial
              </p>
              <h2 class="text-3xl md:text-4xl font-bold tracking-tight mb-4">
                Análise com IA
              </h2>
              <p class="text-lg opacity-60 mb-8">
                Clique em um botão e receba insights personalizados sobre seus gastos.
                A IA analisa seus padrões e oferece dicas para economizar.
              </p>
              <div class="space-y-4">
                <div class="flex items-start gap-3">
                  <div class="w-8 h-8 rounded-lg bg-warning/10 flex items-center justify-center shrink-0 mt-0.5">
                    <.icon name="hero-light-bulb" class="size-4 text-warning" />
                  </div>
                  <div>
                    <p class="font-medium text-sm">Insights automáticos</p>
                    <p class="text-sm opacity-60">Identifica padrões de gasto e tendências mensais</p>
                  </div>
                </div>
                <div class="flex items-start gap-3">
                  <div class="w-8 h-8 rounded-lg bg-error/10 flex items-center justify-center shrink-0 mt-0.5">
                    <.icon name="hero-exclamation-triangle" class="size-4 text-error" />
                  </div>
                  <div>
                    <p class="font-medium text-sm">Alertas inteligentes</p>
                    <p class="text-sm opacity-60">Avisa quando seus gastos estão fora do normal</p>
                  </div>
                </div>
                <div class="flex items-start gap-3">
                  <div class="w-8 h-8 rounded-lg bg-success/10 flex items-center justify-center shrink-0 mt-0.5">
                    <.icon name="hero-check-circle" class="size-4 text-success" />
                  </div>
                  <div>
                    <p class="font-medium text-sm">Dicas de economia</p>
                    <p class="text-sm opacity-60">Sugestões práticas para otimizar seu orçamento</p>
                  </div>
                </div>
              </div>
            </div>

            <div class="card bg-gradient-to-br from-primary/5 to-secondary/5 border border-primary/10 p-6 shadow-xl">
              <div class="flex items-center gap-2 mb-4">
                <.icon name="hero-sparkles" class="size-5 text-primary" />
                <h3 class="font-semibold">Análise Inteligente</h3>
              </div>

              <p class="text-sm mb-4 font-medium">
                Seus gastos com alimentação representam 32% do total — acima da média recomendada de 25%.
                Moradia está dentro do esperado.
              </p>

              <div class="space-y-2 mb-4">
                <div class="flex items-start gap-2 text-sm">
                  <.icon name="hero-light-bulb" class="size-4 text-warning shrink-0 mt-0.5" />
                  <span class="opacity-80">
                    Gastos com delivery aumentaram 40% em relação ao mês anterior
                  </span>
                </div>
                <div class="flex items-start gap-2 text-sm">
                  <.icon name="hero-light-bulb" class="size-4 text-warning shrink-0 mt-0.5" />
                  <span class="opacity-80">
                    3 assinaturas detectadas — considere revisar se todas estão em uso
                  </span>
                </div>
              </div>

              <div class="alert alert-warning text-sm py-2 mb-3">
                <.icon name="hero-exclamation-triangle" class="size-4" />
                <span>Atenção: despesas com lazer estão 20% acima da média dos últimos 3 meses</span>
              </div>

              <div class="flex items-start gap-2 text-sm bg-success/10 rounded-lg p-3">
                <.icon name="hero-check-circle" class="size-4 text-success shrink-0 mt-0.5" />
                <span class="opacity-80">
                  Cozinhar em casa 3x por semana pode economizar até R$ 400/mês em alimentação
                </span>
              </div>
            </div>
          </div>
        </div>
      </section>

      <%!-- Transaction Categorization Preview --%>
      <section class="py-24 px-4 bg-base-200/50">
        <div class="max-w-6xl mx-auto">
          <div class="text-center mb-16">
            <p
              style="font-family: 'Grand Hotel', cursive"
              class="text-primary text-5xl mb-3"
            >
              Organizado
            </p>
            <h2 class="text-3xl md:text-4xl font-bold tracking-tight mb-4">
              Cada transação no seu lugar
            </h2>
            <p class="text-lg opacity-60 max-w-xl mx-auto">
              Categorização automática com possibilidade de ajuste manual. O sistema aprende com você.
            </p>
          </div>

          <div class="rounded-2xl border border-base-content/10 bg-base-200/30 p-4 md:p-8 shadow-xl">
            <div class="flex flex-wrap gap-3 mb-6">
              <div
                :for={
                  {name, color, icon} <- [
                    {"Alimentação", "#F59E0B", "hero-cake"},
                    {"Transporte", "#3B82F6", "hero-truck"},
                    {"Moradia", "#8B5CF6", "hero-home"},
                    {"Saúde", "#EF4444", "hero-heart"},
                    {"Lazer", "#EC4899", "hero-musical-note"},
                    {"Compras", "#F97316", "hero-shopping-bag"},
                    {"Investimentos", "#10B981", "hero-chart-bar"},
                    {"Pagamentos", "#64748B", "hero-credit-card"},
                    {"Salário", "#22C55E", "hero-banknotes"},
                    {"Assinaturas", "#A855F7", "hero-arrow-path"}
                  ]
                }
                class="badge gap-1.5 py-3"
                style={"background-color: #{color}15; color: #{color}; border-color: #{color}30"}
              >
                <.icon name={icon} class="size-3" />
                {name}
              </div>
            </div>

            <div class="overflow-x-auto">
              <table class="table">
                <thead>
                  <tr>
                    <th>Data</th>
                    <th>Descrição</th>
                    <th>Banco</th>
                    <th>Categoria</th>
                    <th class="text-right">Valor</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={
                    {date, desc, bank, cat, color, val, type} <- [
                      {"02/01", "Supermercado Extra", "nubank", "Alimentação", "#F59E0B", "R$ 245,80", "debit"},
                      {"03/01", "Uber *Trip São Paulo", "nubank", "Transporte", "#3B82F6", "R$ 32,50", "debit"},
                      {"05/01", "Transferência recebida", "nubank", "Salário", "#22C55E", "R$ 5.500,00", "credit"},
                      {"06/01", "Netflix.com", "bradesco", "Assinaturas", "#A855F7", "R$ 55,90", "debit"},
                      {"07/01", "Aluguel Fevereiro", "bradesco", "Moradia", "#8B5CF6", "R$ 1.500,00", "debit"},
                      {"08/01", "Drogasil - Medicamentos", "nubank", "Saúde", "#EF4444", "R$ 89,70", "debit"},
                      {"10/01", "Rendimento RDB", "bradesco", "Investimentos", "#10B981", "R$ 245,80", "credit"},
                      {"12/01", "iFood *Restaurante", "nubank", "Alimentação", "#F59E0B", "R$ 67,40", "debit"}
                    ]
                  } class="hover">
                    <td class="text-sm">{date}</td>
                    <td class="text-sm">{desc}</td>
                    <td>
                      <span class="badge badge-sm badge-ghost">{String.capitalize(bank)}</span>
                    </td>
                    <td>
                      <span
                        class="badge badge-sm"
                        style={"background-color: #{color}20; color: #{color}; border-color: #{color}40"}
                      >
                        {cat}
                      </span>
                    </td>
                    <td class={[
                      "text-right text-sm font-medium",
                      (type == "credit" && "text-success") || "text-error"
                    ]}>
                      {(type == "credit" && "+ " || "- ") <> val}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </section>

      <%!-- How it works --%>
      <section class="py-24 px-4">
        <div class="max-w-4xl mx-auto text-center">
          <p
            style="font-family: 'Grand Hotel', cursive"
            class="text-primary text-5xl mb-3"
          >
            Rápido e fácil
          </p>
          <h2 class="text-3xl md:text-4xl font-bold tracking-tight mb-4">
            Como funciona
          </h2>
          <p class="text-lg opacity-60 mb-12">Três passos simples</p>

          <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
            <div class="flex flex-col items-center">
              <div class="w-16 h-16 rounded-full bg-primary/10 flex items-center justify-center mb-4 text-2xl font-bold text-primary">
                1
              </div>
              <h3 class="font-semibold mb-2">Faça Upload</h3>
              <p class="text-sm opacity-60">
                Exporte o CSV do seu banco e faça upload na plataforma. Suporte a upload individual ou em batch.
              </p>
            </div>

            <div class="flex flex-col items-center">
              <div class="w-16 h-16 rounded-full bg-primary/10 flex items-center justify-center mb-4 text-2xl font-bold text-primary">
                2
              </div>
              <h3 class="font-semibold mb-2">Processamento Automático</h3>
              <p class="text-sm opacity-60">
                A IA categoriza suas transações automaticamente com base em padrões e regras personalizadas.
              </p>
            </div>

            <div class="flex flex-col items-center">
              <div class="w-16 h-16 rounded-full bg-primary/10 flex items-center justify-center mb-4 text-2xl font-bold text-primary">
                3
              </div>
              <h3 class="font-semibold mb-2">Analise e Economize</h3>
              <p class="text-sm opacity-60">
                Visualize gráficos, receba insights da IA e descubra onde economizar.
              </p>
            </div>
          </div>
        </div>
      </section>

      <%!-- CTA --%>
      <section class="py-24 px-4 bg-base-200/50">
        <div class="max-w-2xl mx-auto text-center">
          <p
            style="font-family: 'Grand Hotel', cursive"
            class="text-primary text-5xl mb-4"
          >
            Comece hoje
          </p>
          <h2 class="text-3xl md:text-4xl font-bold tracking-tight mb-4">
            Pronto para organizar suas finanças?
          </h2>
          <p class="text-lg opacity-60 mb-8">
            Crie sua conta gratuitamente e tenha controle total dos seus gastos
          </p>
          <div class="flex flex-col sm:flex-row gap-4 justify-center">
            <.link navigate={~p"/users/register"} class="btn btn-primary btn-lg">
              Criar Conta Grátis <.icon name="hero-arrow-right" class="size-5" />
            </.link>
            <.link navigate={~p"/users/log-in"} class="btn btn-ghost btn-lg">
              Já tenho conta
            </.link>
          </div>
        </div>
      </section>

      <%!-- Footer --%>
      <footer class="navbar py-8 border-t border-base-content/5 px-4 sm:px-6 lg:px-8">
        <div class="flex-1">
          <a href="/" class="flex items-center gap-2 text-xl font-bold tracking-tight">
            <img src={~p"/images/logo-32.png"} alt="" class="w-7 h-7" />
            <span style="font-family: 'Grand Hotel', cursive">Granai</span>
          </a>
        </div>
        <div class="flex-none">
          <span>Feito com Phoenix LiveView por <a href="https://github.com/hjunior29" class="text-primary hover:text-primary/80">hjunior29</a>❤️</span>
        </div>
      </footer>
    </div>
    """
  end
end
