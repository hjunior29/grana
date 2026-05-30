defmodule GranaWeb.LandingLive do
  use GranaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Controle suas finanças")
     |> assign(:roadmap_url, Application.get_env(:grana, :roadmap_url))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-7xl">
        <section class="finance-hero">
          <div class="finance-hero-copy">
            <div class="page-kicker mb-5">
              <.icon name="hero-sparkles" class="size-4" /> Organizador financeiro pessoal
            </div>

            <h1 class="headline-balance text-5xl font-black leading-[0.95] tracking-normal sm:text-7xl lg:text-8xl">
              Controle total das suas finanças
            </h1>

            <p class="mt-6 max-w-2xl text-base leading-8 text-base-content/70 sm:text-lg">
              Importe extratos, faturas e movimentações de investimentos. O Grana organiza tudo,
              categoriza automaticamente, mostra gráficos claros e ajuda você a tomar decisões com IA.
            </p>

            <div class="mt-8 flex flex-col gap-3 sm:flex-row">
              <.link
                navigate={if @current_scope, do: ~p"/dashboard", else: ~p"/users/register"}
                class="btn btn-primary btn-lg"
              >
                <.icon name="hero-rocket-launch" class="size-5" />
                {if @current_scope, do: "Abrir Dashboard", else: "Criar Conta"}
              </.link>
              <.link
                navigate={if @current_scope, do: ~p"/upload", else: ~p"/users/log-in"}
                class="btn btn-ghost btn-lg"
              >
                <.icon name="hero-arrow-right-on-rectangle" class="size-5" />
                {if @current_scope, do: "Importar dados", else: "Entrar"}
              </.link>
            </div>

            <div class="integration-strip mt-8 grid grid-cols-2 gap-3 p-3 sm:flex sm:items-center sm:gap-4">
              <span class="text-xs font-bold uppercase tracking-wide text-base-content/50">
                Importa de
              </span>
              <div class="flex items-center gap-2">
                <img src={~p"/images/nubank-logo.png"} alt="Nubank" class="size-7 rounded-full" />
                <img src={~p"/images/bradesco-logo.png"} alt="Bradesco" class="size-7 rounded-full" />
                <img src={~p"/images/b3-logo.png"} alt="B3" class="size-7 rounded-full object-cover" />
                <img
                  src={~p"/images/gcb-logo.png"}
                  alt="GCB"
                  class="size-7 rounded-full object-cover"
                />
              </div>
              <span class="text-xs text-base-content/55 sm:ml-auto">
                CSV, PDF, XLSX e categorias inteligentes
              </span>
            </div>
          </div>

          <div class="hero-visual">
            <div class="hero-panel hero-balance-card floating-card">
              <div class="flex items-start justify-between gap-4">
                <div>
                  <p class="text-sm font-bold text-base-content/55">Saldo organizado</p>
                  <p class="mt-2 text-4xl font-black tracking-normal">R$ 8.420,16</p>
                  <p class="mt-2 text-sm text-success">
                    <.icon name="hero-arrow-trending-up" class="size-4" />
                    18% melhor que o mês anterior
                  </p>
                </div>
                <div class="brand-image-ring">
                  <img src={~p"/images/logo-animated.gif"} alt="Grana" class="size-16 rounded-xl" />
                </div>
              </div>

              <div class="hero-chart-bars mt-8" aria-hidden="true">
                <span style="height: 44%"></span>
                <span style="height: 70%"></span>
                <span style="height: 52%"></span>
                <span style="height: 86%"></span>
                <span style="height: 62%"></span>
                <span style="height: 96%"></span>
                <span style="height: 76%"></span>
                <span style="height: 58%"></span>
              </div>
            </div>

            <div class="hero-panel floating-card absolute left-0 top-[17rem] w-[78%] sm:w-[21rem]">
              <div class="flex items-center justify-between">
                <div>
                  <p class="text-xs font-bold uppercase text-base-content/45">Categorias</p>
                  <p class="mt-1 text-lg font-black">Gastos sob controle</p>
                </div>
                <span class="badge badge-success">IA</span>
              </div>
              <div class="mt-4 space-y-3">
                <div class="flex items-center gap-3">
                  <span class="size-3 rounded-full bg-success"></span>
                  <span class="flex-1 text-sm">Mercado</span>
                  <span class="text-sm font-bold">28%</span>
                </div>
                <div class="flex items-center gap-3">
                  <span class="size-3 rounded-full bg-warning"></span>
                  <span class="flex-1 text-sm">Transporte</span>
                  <span class="text-sm font-bold">17%</span>
                </div>
                <div class="flex items-center gap-3">
                  <span class="size-3 rounded-full bg-info"></span>
                  <span class="flex-1 text-sm">Investimentos</span>
                  <span class="text-sm font-bold">31%</span>
                </div>
              </div>
            </div>

            <div class="hero-panel floating-card absolute bottom-4 right-0 w-[82%] sm:w-[22rem]">
              <div class="flex items-center gap-3">
                <div class="feature-icon">
                  <.icon name="hero-bolt" class="size-5" />
                </div>
                <div>
                  <p class="text-sm font-bold">Processamento Automático</p>
                  <p class="text-xs text-base-content/55">
                    Extrato lido, transações agrupadas e anomalias destacadas.
                  </p>
                </div>
              </div>
              <div class="mt-4 grid grid-cols-3 gap-2 text-center text-xs">
                <div class="rounded-lg bg-base-100/60 p-3">
                  <p class="font-black text-success">142</p>
                  <p class="text-base-content/45">transações</p>
                </div>
                <div class="rounded-lg bg-base-100/60 p-3">
                  <p class="font-black text-warning">9</p>
                  <p class="text-base-content/45">alertas</p>
                </div>
                <div class="rounded-lg bg-base-100/60 p-3">
                  <p class="font-black text-info">4</p>
                  <p class="text-base-content/45">fontes</p>
                </div>
              </div>
            </div>
          </div>
        </section>

        <section id="recursos" class="py-12 sm:py-20">
          <div class="mb-8 flex flex-col justify-between gap-4 sm:flex-row sm:items-end">
            <div>
              <p class="page-kicker mb-4">
                <.icon name="hero-squares-2x2" class="size-4" /> Tudo no mesmo fluxo
              </p>
              <h2 class="text-3xl font-black tracking-normal sm:text-5xl">
                Uma UI feita para organizar dinheiro sem esforço
              </h2>
            </div>
            <p class="max-w-xl text-sm leading-7 text-base-content/60">
              O app prioriza leitura rápida: filtros compactos, cartões com sinais fortes,
              tabelas escaneáveis, microinterações e feedback visual em importações.
            </p>
          </div>

          <div class="grid gap-4 md:grid-cols-3">
            <article class="feature-card">
              <div class="feature-icon">
                <.icon name="hero-cloud-arrow-up" class="size-5" />
              </div>
              <h3 class="mt-5 text-xl font-black">Upload Simples</h3>
              <p class="mt-3 text-sm leading-7 text-base-content/65">
                Arraste arquivos CSV, PDF ou XLSX e acompanhe o processamento com progresso animado.
              </p>
            </article>

            <article class="feature-card">
              <div class="feature-icon">
                <.icon name="hero-sparkles" class="size-5" />
              </div>
              <h3 class="mt-5 text-xl font-black">Categorização Inteligente</h3>
              <p class="mt-3 text-sm leading-7 text-base-content/65">
                Categorias, regras e IA trabalham juntas para reduzir ajustes manuais no dia a dia.
              </p>
            </article>

            <article class="feature-card">
              <div class="feature-icon">
                <.icon name="hero-chart-pie" class="size-5" />
              </div>
              <h3 class="mt-5 text-xl font-black">Gráficos Detalhados</h3>
              <p class="mt-3 text-sm leading-7 text-base-content/65">
                Veja gastos por categoria, evolução mensal, projeções de parcelas e carteira de investimentos.
              </p>
            </article>
          </div>
        </section>

        <section id="como-funciona" class="py-12 sm:py-20">
          <div class="grid gap-6 lg:grid-cols-[0.78fr_1fr] lg:items-start">
            <div>
              <p class="page-kicker mb-4">
                <.icon name="hero-play" class="size-4" /> Como funciona
              </p>
              <h2 class="text-3xl font-black tracking-normal sm:text-5xl">
                Três etapas, uma visão limpa
              </h2>
              <p class="mt-4 text-sm leading-7 text-base-content/60">
                Do arquivo bruto ao dashboard acionável, o fluxo foi desenhado para parecer rápido,
                responsivo e visualmente claro em desktop e celular.
              </p>
            </div>

            <div class="grid gap-4">
              <article class="workflow-step">
                <div class="flex gap-4">
                  <div class="workflow-icon">1</div>
                  <div>
                    <h3 class="text-lg font-black">Faça Upload</h3>
                    <p class="mt-2 text-sm leading-7 text-base-content/65">
                      Envie extratos bancários, faturas, notas de investimento e arquivos da B3 ou GCB.
                    </p>
                  </div>
                </div>
              </article>

              <article class="workflow-step">
                <div class="flex gap-4">
                  <div class="workflow-icon">2</div>
                  <div>
                    <h3 class="text-lg font-black">Processamento Automático</h3>
                    <p class="mt-2 text-sm leading-7 text-base-content/65">
                      O Grana extrai transações, identifica fontes, aplica categorias e preserva o histórico.
                    </p>
                  </div>
                </div>
              </article>

              <article class="workflow-step">
                <div class="flex gap-4">
                  <div class="workflow-icon">3</div>
                  <div>
                    <h3 class="text-lg font-black">Analise, ajuste e economize</h3>
                    <p class="mt-2 text-sm leading-7 text-base-content/65">
                      Use dashboards, metas e análises com IA para encontrar padrões e decidir o próximo passo.
                    </p>
                  </div>
                </div>
              </article>
            </div>
          </div>
        </section>

        <section class="py-12 sm:py-20">
          <div class="surface-panel overflow-hidden p-6 sm:p-8">
            <div class="grid gap-8 lg:grid-cols-[1fr_0.8fr] lg:items-center">
              <div>
                <p class="page-kicker mb-4">
                  <.icon name="hero-shield-check" class="size-4" /> Privacidade primeiro
                </p>
                <h2 class="text-3xl font-black tracking-normal sm:text-5xl">
                  Feito para organizar, não para vender seus dados
                </h2>
                <p class="mt-4 text-sm leading-7 text-base-content/65">
                  O Grana é um organizador financeiro pessoal. As análises com IA seguem o modelo BYOK:
                  você usa sua própria chave, controla a configuração e mantém o foco no seu orçamento.
                </p>
                <div class="mt-6 flex flex-col gap-3 sm:flex-row">
                  <.link navigate={~p"/terms"} class="btn btn-ghost">
                    <.icon name="hero-document-text" class="size-5" /> Termos e privacidade
                  </.link>
                  <.link
                    :if={@roadmap_url}
                    href={@roadmap_url}
                    target="_blank"
                    class="btn btn-ghost"
                  >
                    <.icon name="hero-light-bulb" class="size-5" /> Sugerir integração
                  </.link>
                </div>
              </div>

              <div class="grid gap-3 sm:grid-cols-2">
                <div class="rounded-lg border border-base-content/10 bg-base-100/60 p-4">
                  <p class="text-2xl font-black text-success">100%</p>
                  <p class="mt-1 text-sm text-base-content/60">controle da sua conta</p>
                </div>
                <div class="rounded-lg border border-base-content/10 bg-base-100/60 p-4">
                  <p class="text-2xl font-black text-warning">BYOK</p>
                  <p class="mt-1 text-sm text-base-content/60">sua chave de IA</p>
                </div>
                <div class="rounded-lg border border-base-content/10 bg-base-100/60 p-4">
                  <p class="text-2xl font-black text-info">CSV</p>
                  <p class="mt-1 text-sm text-base-content/60">exportação simples</p>
                </div>
                <div class="rounded-lg border border-base-content/10 bg-base-100/60 p-4">
                  <p class="text-2xl font-black text-accent">LGPD</p>
                  <p class="mt-1 text-sm text-base-content/60">política clara</p>
                </div>
              </div>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
