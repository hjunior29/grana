defmodule GranaWeb.LandingLive do
  use GranaWeb, :live_view

  alias Grana.Demo
  alias GranaWeb.OpenFinanceComponents
  alias GranaWeb.SpendingCalendar

  @impl true
  # Na demonstração a landing é a vitrine: abre também para quem já entrou na demo.
  def mount(_params, _session, %{assigns: %{current_scope: %{user: %{}}}} = socket) do
    if Demo.enabled?(),
      do: {:ok, assign_landing(socket)},
      else: {:ok, push_navigate(socket, to: ~p"/dashboard")}
  end

  def mount(_params, _session, socket), do: {:ok, assign_landing(socket)}

  # Quem já entrou na demo volta direto ao app; os demais passam pelo login.
  defp demo_path(nil), do: ~p"/users/log-in"
  defp demo_path(_scope), do: ~p"/dashboard"

  defp assign_landing(socket) do
    assign(socket,
      page_title: "Controle suas finanças",
      spending_view: "calendar",
      hide_values: false,
      hide_names: false,
      install_method: "script",
      demo: Demo.enabled?()
    )
  end

  @impl true
  def handle_event("set_spending_view", %{"view" => view}, socket)
      when view in ~w(bars calendar) do
    {:noreply, assign(socket, :spending_view, view)}
  end

  def handle_event("toggle_privacy", %{"key" => "values"}, socket),
    do: {:noreply, update(socket, :hide_values, &(!&1))}

  def handle_event("toggle_privacy", %{"key" => "names"}, socket),
    do: {:noreply, update(socket, :hide_names, &(!&1))}

  def handle_event("set_install_method", %{"method" => method}, socket)
      when method in ~w(script docker fly) do
    {:noreply, assign(socket, :install_method, method)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- grana-app-shell: the visual styles chosen below restyle the whole page, as in the app --%>
    <div
      id="lp"
      class={[
        "grana-app-shell min-h-screen",
        @hide_values && "ui-hide-values",
        @hide_names && "ui-hide-names"
      ]}
      phx-hook=".ScrollMotion"
    >
      <nav class="navbar bg-base-100/10 backdrop-blur-xl sticky top-0 z-50 border-b border-base-content/5 px-4 sm:px-6 lg:px-8">
        <div class="flex-1">
          <a id="landing-brand" href="/" class="flex items-center">
            <GranaWeb.BrandComponents.brand />
          </a>
        </div>
        <div class="flex-none">
          <div class="flex items-center gap-3">
            <Layouts.theme_toggle :if={!@current_scope} />
            <.link
              :if={@demo && !@current_scope}
              id="nav-demo"
              navigate={~p"/users/log-in"}
              class="btn btn-primary btn-sm"
            >
              Ver a demo
            </.link>
            <.link
              :if={!@demo && !@current_scope}
              navigate={~p"/users/log-in"}
              class="btn btn-primary btn-sm"
            >
              Entrar
            </.link>
            <.link :if={@current_scope} navigate={~p"/dashboard"} class="btn btn-primary btn-sm">
              {if @demo, do: "Voltar à demo", else: "Dashboard"}
            </.link>
          </div>
        </div>
      </nav>

      <%!-- A logo contada pelo scroll: moeda, categorias e meses se juntam no símbolo --%>
      <section
        id="logo-story"
        class="logo-story"
        phx-hook=".LogoStory"
        phx-update="ignore"
        data-geometry={Jason.encode!(GranaWeb.BrandComponents.geometry())}
        data-months={Jason.encode!(story_months())}
        aria-label="Como nasceu a logo do Grana"
      >
        <div class="logo-story-stage">
          <svg class="logo-story-canvas" data-canvas aria-hidden="true"></svg>

          <div id="logo-story-coin" class="logo-story-panel" data-panel="0">
            <div class="logo-story-coin-anchor" data-anchor="coin"></div>
            <p class="logo-story-kicker">Por trás da logo</p>
            <h2>Tudo começa na moeda</h2>
            <p>
              Ter controle financeiro é saber onde você gasta, onde dá para economizar e quanto
              sobra no fim do mês. A moeda de 1 real no centro é isso: o seu dinheiro como ponto
              de partida.
            </p>
          </div>

          <div
            id="logo-story-categories"
            class="logo-story-panel logo-story-panel-left"
            data-panel="1"
          >
            <div class="logo-story-card">
              <h3>Despesas por categoria</h3>
              <div class="logo-story-donut">
                <div class="logo-story-donut-anchor" data-anchor="donut"></div>
                <div class="logo-story-donut-total">
                  <span>Total</span>
                  <strong>{brl(story_categories_total())}</strong>
                </div>
              </div>
              <ul class="logo-story-category-list">
                <li :for={cat <- story_categories()}>
                  <span class="logo-story-category-icon" style={"background-color: #{cat.color}20"}>
                    <span class="flex" style={"color: #{cat.color}"}>
                      <.icon name={cat.icon} class="size-3.5" />
                    </span>
                  </span>
                  <span class="logo-story-category-name">{cat.name}</span>
                  <span class="logo-story-category-amount">{brl(cat.amount)}</span>
                  <span class="logo-story-category-share">{percent(cat.share)}</span>
                </li>
              </ul>
            </div>
            <p class="logo-story-kicker">Categorias</p>
            <h2>Cada gasto no seu lugar</h2>
            <p>
              O Grana coloca cada transação numa categoria, com cor e ícone, e mostra quanto cada
              uma leva do seu dinheiro. Na logo, essa rosca abraça a moeda.
            </p>
          </div>

          <div id="logo-story-months" class="logo-story-panel" data-panel="2">
            <div class="logo-story-card">
              <div class="logo-story-card-header">
                <h3>Receitas vs Despesas</h3>
                <div class="logo-story-card-balance">
                  <strong>+{brl(story_balance())}</strong>
                  <span>economizou {percent(story_balance() / story_income())}</span>
                </div>
              </div>
              <div class="logo-story-chart-anchor" data-anchor="chart"></div>
              <div class="logo-story-legend">
                <span><i class="logo-story-dot-positive"></i> Receitas</span>
                <span><i class="logo-story-dot-negative"></i> Despesas</span>
              </div>
            </div>
            <p class="logo-story-kicker">Ganhos e despesas</p>
            <h2>O saldo de cada mês</h2>
            <p>
              Todo mês o Grana compara o que entrou com o que saiu. O que sobra fica verde; o que
              falta, vermelho. Na logo, cada mês vira uma pétala do tamanho desse saldo.
            </p>
          </div>

          <div id="logo-story-final" class="logo-story-panel" data-panel="3">
            <GranaWeb.BrandComponents.wordmark class="h-9 w-auto mb-5" />
            <h2>Isso é o Grana</h2>
            <p>
              O seu dinheiro no centro, as categorias em volta e os meses contando a história.
              A logo é um resumo do próprio app.
            </p>
          </div>

          <div class="logo-story-hint" data-hint>
            Role para baixo <.icon name="hero-chevron-double-down" class="size-4" />
          </div>
        </div>
      </section>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".LogoStory">
        const N = 16
        const SVG = "http://www.w3.org/2000/svg"
        const LABELS = ["Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"]
        const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v))
        const seg = (p, a, b) => clamp((p - a) / (b - a))
        const ease = t => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2)
        const lerp = (a, b, t) => a + (b - a) * t

        // Formas como listas de pontos na mesma ordem (borda de fora → borda de dentro),
        // para uma virar a outra ponto a ponto.
        const arc = (cx, cy, r, a0, a1) => {
          const pts = []
          for (let i = 0; i < N; i++) {
            const a = ((a0 + ((a1 - a0) * i) / (N - 1)) * Math.PI) / 180
            pts.push([cx + r * Math.cos(a), cy + r * Math.sin(a)])
          }
          return pts
        }
        const sector = (cx, cy, r0, r1, a0, a1) => arc(cx, cy, r1, a0, a1).concat(arc(cx, cy, r0, a1, a0))
        const bar = (x0, x1, yFar, yNear) => {
          const far = [], near = []
          for (let i = 0; i < N; i++) {
            const x = x0 + ((x1 - x0) * i) / (N - 1)
            far.push([x, yFar])
            near.unshift([x, yNear])
          }
          return far.concat(near)
        }
        const mix = (from, to, t) => from.map((p, i) => [lerp(p[0], to[i][0], t), lerp(p[1], to[i][1], t)])
        const d = pts => "M" + pts.map(p => p[0].toFixed(1) + " " + p[1].toFixed(1)).join("L") + "Z"

        export default {
          mounted() {
            this.geo = JSON.parse(this.el.dataset.geometry)
            this.data = JSON.parse(this.el.dataset.months)
            this.stage = this.el.querySelector(".logo-story-stage")
            this.svg = this.el.querySelector("[data-canvas]")
            this.panels = [...this.el.querySelectorAll("[data-panel]")]
            this.hint = this.el.querySelector("[data-hint]")
            this.build()
            this.onScroll = () => this.queue()
            this.onResize = () => {
              this.layout()
              this.queue()
            }
            window.addEventListener("scroll", this.onScroll, {passive: true})
            window.addEventListener("resize", this.onResize)
            this.layout()
            this.render()
          },
          destroyed() {
            window.removeEventListener("scroll", this.onScroll)
            window.removeEventListener("resize", this.onResize)
            cancelAnimationFrame(this.raf)
          },
          queue() {
            if (this.raf) return
            this.raf = requestAnimationFrame(() => {
              this.raf = null
              this.render()
            })
          },
          add(tag, attrs = {}, parent = this.svg) {
            const node = document.createElementNS(SVG, tag)
            for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v)
            parent.appendChild(node)
            return node
          },
          build() {
            this.baseline = this.add("line", {"stroke-width": 1})
            this.labels = LABELS.map(label => {
              const t = this.add("text", {"text-anchor": "middle", "font-size": 10})
              t.textContent = label
              return t
            })
            this.income = this.data.map(() => this.add("path"))
            this.expense = this.data.map(() => this.add("path"))
            this.cats = this.geo.categories.map(() => this.add("path"))
            this.coin = this.add("g")
            this.add("circle", {r: 4, fill: "#D97706"}, this.coin)
            this.add("circle", {r: 3.65, fill: "#FBBF24"}, this.coin)
            this.add("circle", {r: 2.55, fill: "#E2E8F0", stroke: "#94A3B8", "stroke-width": 0.35}, this.coin)
          },
          rel(node) {
            const r = node.getBoundingClientRect(), s = this.stage.getBoundingClientRect()
            return {x: r.left - s.left, y: r.top - s.top, w: r.width, h: r.height}
          },
          layout() {
            const w = this.stage.clientWidth, h = this.stage.clientHeight
            this.svg.setAttribute("viewBox", `0 0 ${w} ${h}`)
            const mobile = w < 768
            const size = mobile ? Math.min(h * 0.4, w * 0.8) : Math.min(h * 0.66, w * 0.42, 600)
            const half = (size / 32) * 15.4
            this.s = size / 32
            // O símbolo fica do lado oposto ao texto: à direita enquanto as categorias
            // estão à esquerda, à esquerda quando os meses entram à direita.
            const left = this.rel(this.panels[1]), right = this.rel(this.panels[2])
            this.cxRight = mobile ? w / 2 : Math.max(w / 2, left.x + left.w + half + 32)
            this.cxLeft = mobile ? w / 2 : Math.min(w / 2, right.x - half - 32)
            this.cy = mobile ? 16 + half + 56 : h / 2
            this.coinFrom = this.rel(this.el.querySelector("[data-anchor=coin]"))
            this.donut = this.rel(this.el.querySelector("[data-anchor=donut]"))
            this.chart = this.rel(this.el.querySelector("[data-anchor=chart]"))
          },
          dark() {
            const theme = document.documentElement.getAttribute("data-theme")
            return theme ? theme === "dark" : matchMedia("(prefers-color-scheme: dark)").matches
          },
          render() {
            const box = this.el.getBoundingClientRect()
            if (box.bottom < -50 || box.top > window.innerHeight + 50) return
            const p = clamp(-box.top / (box.height - window.innerHeight))
            const dark = this.dark()
            const geo = this.geo, s = this.s, cy = this.cy
            const cx = lerp(this.cxRight, this.cxLeft, ease(seg(p, 0.44, 0.54)))
            const colors = geo.month_colors[dark ? "dark" : "light"]
            const ink = dark ? "#94A3B8" : "#64748B"

            // textos: moeda → categorias → meses → fechamento
            const show = [
              1 - seg(p, 0.05, 0.12),
              seg(p, 0.15, 0.22) * (1 - seg(p, 0.4, 0.46)),
              seg(p, 0.48, 0.55) * (1 - seg(p, 0.8, 0.86)),
              seg(p, 0.9, 0.96)
            ]
            this.panels.forEach((el, i) => {
              el.style.opacity = show[i]
              el.style.visibility = show[i] > 0.01 ? "visible" : "hidden"
            })
            this.hint.style.opacity = 1 - seg(p, 0.02, 0.05)

            // 1. a moeda sai do texto e vai para o centro
            const m = ease(seg(p, 0.05, 0.17))
            const c0 = this.coinFrom
            const k = lerp(c0.w / 8, s, m)
            this.coin.setAttribute(
              "transform",
              `translate(${lerp(c0.x + c0.w / 2, cx, m)} ${lerp(c0.y + c0.h / 2, cy, m)}) scale(${k})`
            )

            // 2. a rosca de categorias do card voa e vira o anel em volta da moeda
            const dn = this.donut
            const dcx = dn.x + dn.w / 2, dcy = dn.y + dn.h / 2, dr = dn.w / 2
            let a = -90
            geo.categories.forEach((cat, j) => {
              const a0 = a + 3, a1 = a + cat.span + 5
              a += cat.span + 8
              const from = sector(dcx, dcy, dr * 0.76, dr, a0, a1)
              const to = sector(cx, cy, geo.ring[0] * s, geo.ring[1] * s, a0, a1)
              const t = ease(seg(p, 0.3 + j * 0.012, 0.42 + j * 0.012))
              const path = this.cats[j]
              path.setAttribute("d", d(mix(from, to, t)))
              path.setAttribute("fill", dark ? cat.dark : cat.color)
              path.style.opacity = seg(p, 0.15, 0.22)
            })

            // 3. receitas x despesas → saldo de cada mês → pétalas
            const c = this.chart
            const max = Math.max(...this.data.map(mo => Math.max(mo.income, mo.expense)))
            const group = c.w / 12
            const bw = group * 0.36
            const base = c.y + c.h
            const chartIn = seg(p, 0.48, 0.55)
            const chartOut = 1 - seg(p, 0.72, 0.78)
            this.baseline.setAttribute("x1", c.x)
            this.baseline.setAttribute("x2", c.x + c.w)
            this.baseline.setAttribute("y1", base)
            this.baseline.setAttribute("y2", base)
            this.baseline.setAttribute("stroke", ink)
            this.baseline.style.opacity = chartIn * chartOut * 0.35
            this.data.forEach((mo, i) => {
              const gx = c.x + i * group + group * 0.12
              const grow = ease(seg(p, 0.52 + i * 0.006, 0.6 + i * 0.006))
              const hI = (mo.income / max) * c.h * grow
              const hE = (mo.expense / max) * c.h * grow
              const incomeBar = bar(gx, gx + bw, base - hI, base)
              const expenseBar = bar(gx + bw + 1.5, gx + 2 * bw + 1.5, base - hE, base)
              // o saldo: uma barra só, da cor de quem venceu, com a diferença entre as duas
              const positive = mo.income >= mo.expense
              const balance = bar(gx, gx + 2 * bw + 1.5, base - Math.abs(hI - hE), base)
              const merge = ease(seg(p, 0.64 + i * 0.004, 0.72 + i * 0.004))
              const month = geo.months[i]
              const a0 = -90 + i * 30 + 1.4, a1 = -90 + (i + 1) * 30 - 1.4
              const petal = sector(cx, cy, geo.petal_inner * s, month.size * s, a0, a1)
              const fly = ease(seg(p, 0.76 + i * 0.006, 0.88 + i * 0.006))
              const keep = positive ? this.income[i] : this.expense[i]
              const drop = positive ? this.expense[i] : this.income[i]
              const keepFrom = positive ? incomeBar : expenseBar
              const dropFrom = positive ? expenseBar : incomeBar
              keep.setAttribute("d", d(mix(mix(keepFrom, balance, merge), petal, fly)))
              keep.setAttribute("fill", positive ? colors.positive : colors.negative)
              keep.style.opacity = chartIn
              drop.setAttribute("d", d(mix(dropFrom, balance, merge)))
              drop.setAttribute("fill", positive ? colors.negative : colors.positive)
              drop.style.opacity = chartIn * (1 - merge)
              const label = this.labels[i]
              label.setAttribute("x", gx + bw + 0.75)
              label.setAttribute("y", base + 14)
              label.setAttribute("fill", ink)
              label.style.opacity = chartIn * chartOut
            })
          }
        }
      </script>

      <%!-- Manifesto: o que é o Grana, logo depois da história da logo --%>
      <section id="hero" class="lp-section lp-hero" data-motion>
        <div class="lp-wrap text-center">
          <p class="lp-kicker lp-rise">Open source · self-hosted · uma pessoa só</p>
          <h1 class="lp-h1 lp-rise" style="--d: 0.1">
            Suas finanças,<br />
            <span class="text-primary">no seu servidor</span>
          </h1>
          <p class="lp-lead mx-auto max-w-2xl lp-rise" style="--d: 0.2">
            Importe extratos e faturas, deixe cada gasto na sua categoria, converse com os seus
            dados e entenda cada mês. Tudo num único arquivo, na sua máquina, com a sua própria
            chave de IA.
          </p>
          <div class="lp-actions lp-rise" style="--d: 0.3">
            <.link
              :if={@demo}
              id="hero-demo"
              navigate={demo_path(@current_scope)}
              class="btn btn-primary btn-lg"
            >
              Ver a demo
            </.link>
            <.link
              :if={!@demo}
              id="hero-login"
              navigate={~p"/users/log-in"}
              class="btn btn-primary btn-lg"
            >
              Entrar
            </.link>
            <a id="hero-install" href="#instalacao" class="btn btn-ghost btn-lg">
              Instalar no seu servidor
            </a>
          </div>
          <p :if={@demo} id="hero-demo-note" class="lp-demo-note lp-rise" style="--d: 0.35">
            A demo é uma conta compartilhada, com dados fictícios: o que você mudar, os outros
            visitantes também veem, e tudo volta ao original quando o servidor reinicia.
          </p>
          <ul class="lp-facts lp-rise" style="--d: 0.4">
            <li :for={{icon, text} <- facts()}>
              <.icon name={icon} class="size-4 text-primary" /> {text}
            </li>
          </ul>
        </div>
      </section>

      <%!-- Como funciona: o palco fica preso e a linha acende um passo de cada vez --%>
      <section id="como-funciona" class="lp-scene lp-scene-short lp-alt" data-scene>
        <div class="lp-stage lp-stage-single text-center">
          <div data-motion>
            <p class="lp-kicker lp-rise">Como funciona</p>
            <h2 class="lp-h2 lp-rise" style="--d: 0.05">Três passos, no seu ritmo</h2>
            <p class="lp-lead mx-auto max-w-xl lp-rise" style="--d: 0.1">
              Os seus uploads são o histórico oficial. O resto complementa.
            </p>
          </div>

          <div class="lp-steps">
            <div class="lp-steps-line" aria-hidden="true">
              <div class="lp-steps-fill"></div>
              <div class="lp-steps-dot"></div>
            </div>
            <div
              :for={{{icon, title, text}, n} <- Enum.with_index(steps(), 1)}
              class="lp-step"
              style={step_window(n)}
            >
              <div class="lp-step-circle">
                <.icon name={icon} class="size-6" />
                <span class="lp-step-number">{n}</span>
              </div>
              <h3>{title}</h3>
              <p>{text}</p>
            </div>
          </div>
        </div>
      </section>

      <%!-- Importação: os arquivos entram na fila e são processados enquanto você rola --%>
      <section id="importacao" class="lp-scene" data-scene aria-label="Importação de extratos">
        <div class="lp-stage">
          <div class="lp-stage-text">
            <p class="lp-kicker">Importação</p>
            <h2 class="lp-h2">Solte os arquivos e siga a vida</h2>
            <p class="lp-lead">
              Extratos e faturas em CSV ou PDF, quantos quiser de uma vez. A fila roda em
              segundo plano: pode sair da tela, e o Grana avisa quando terminar.
            </p>
            <ul class="lp-bullets">
              <li
                :for={{icon, text} <- import_bullets()}
                class="lp-t lp-t-rise"
                style="--a: 0.3; --b: 0.5"
              >
                <.icon name={icon} class="size-5 text-primary" /> <span>{text}</span>
              </li>
            </ul>
          </div>

          <div class="lp-stage-mock">
            <div class="lp-card lp-upload">
              <div class="lp-dropzone">
                <.icon name="hero-cloud-arrow-up" class="size-8 text-primary" />
                <p>Arraste extratos e faturas</p>
                <span class="ui-caption">CSV ou PDF · sem limite de arquivos</span>
              </div>
              <ul class="lp-queue">
                <li
                  :for={{{name, bank, status}, i} <- Enum.with_index(import_files())}
                  class="lp-file lp-t"
                  style={"--a: #{0.06 + i * 0.07}; --b: #{0.22 + i * 0.07}; --i: #{i}"}
                >
                  <span class="lp-file-icon">
                    <.icon
                      name={
                        if String.ends_with?(name, ".pdf"),
                          do: "hero-document-text",
                          else: "hero-table-cells"
                      }
                      class="size-4"
                    />
                  </span>
                  <span class="lp-file-name">
                    <span class="ui-private-name truncate">{name}</span>
                    <small class="ui-caption">{bank}</small>
                  </span>
                  <span
                    class="lp-file-bar lp-t"
                    style={"--a: #{0.32 + i * 0.09}; --b: #{0.5 + i * 0.09}"}
                  >
                    <i></i>
                  </span>
                  <span
                    class="lp-file-done lp-t lp-t-pop"
                    style={"--a: #{0.5 + i * 0.09}; --b: #{0.56 + i * 0.09}"}
                  >
                    <.icon name="hero-check" class="size-3.5" /> {status}
                  </span>
                </li>
              </ul>
            </div>
            <div
              class="lp-toast ui-notice ui-notice-success lp-t lp-t-rise"
              style="--a: 0.86; --b: 0.94"
            >
              <.icon name="hero-check-circle" class="size-5 shrink-0" />
              <div>
                <p class="font-semibold">Importação concluída</p>
                <p class="ui-help">4 arquivos, 212 transações. Você estava em outra tela.</p>
              </div>
            </div>
          </div>
        </div>
      </section>

      <%!-- Categorias: cada transação ganha a sua, por regra ou por IA --%>
      <section id="categorias" class="lp-scene lp-alt" data-scene aria-label="Categorização">
        <div class="lp-stage lp-stage-flip">
          <div class="lp-stage-text">
            <p class="lp-kicker">Categorias</p>
            <h2 class="lp-h2">Cada transação no seu lugar</h2>
            <p class="lp-lead">
              Primeiro valem as suas regras. O que elas não pegam, a IA categoriza. Corrigiu uma
              vez? Vira regra, e nunca mais se repete.
            </p>
            <ul class="lp-bullets">
              <li
                :for={{icon, text} <- category_bullets()}
                class="lp-t lp-t-rise"
                style="--a: 0.45; --b: 0.65"
              >
                <.icon name={icon} class="size-5 text-primary" /> <span>{text}</span>
              </li>
            </ul>
          </div>

          <div class="lp-stage-mock">
            <div class="lp-card lp-table">
              <div class="lp-table-head">
                <span>Data</span><span class="lp-table-desc">Descrição</span><span>Categoria</span><span class="text-right">Valor</span>
              </div>
              <div
                :for={{{date, desc, cat, color, value, how}, i} <- Enum.with_index(category_rows())}
                class="lp-table-row"
              >
                <span class="ui-caption">{date}</span>
                <span class="ui-private-name truncate lp-table-desc">{desc}</span>
                <span class="lp-chip-slot">
                  <span
                    class="lp-chip-skeleton lp-t lp-t-fade"
                    style={"--a: #{0.1 + i * 0.1}; --b: #{0.16 + i * 0.1}; --reverse: 1"}
                  >
                  </span>
                  <span
                    class="lp-cat-chip lp-t lp-t-pop"
                    style={"--a: #{0.1 + i * 0.1}; --b: #{0.18 + i * 0.1}; --cat: #{color}"}
                  >
                    <.icon
                      name={if how == :rule, do: "hero-bolt", else: "hero-sparkles"}
                      class="size-3"
                    />
                    {cat}
                  </span>
                </span>
                <span class={[
                  "ui-private text-right font-medium",
                  if(String.starts_with?(value, "+"),
                    do: "ui-money-receita",
                    else: "ui-money-despesa"
                  )
                ]}>
                  {value}
                </span>
              </div>
            </div>
            <div class="lp-legend lp-t lp-t-rise" style="--a: 0.72; --b: 0.82">
              <span><.icon name="hero-bolt" class="size-3.5 text-primary" /> Regra sua</span>
              <span>
                <.icon name="hero-sparkles" class="size-3.5 text-primary" /> Categorizado pela IA
              </span>
            </div>
          </div>
        </div>
      </section>

      <%!-- Painel --%>
      <section id="painel" class="lp-section" data-motion>
        <div class="lp-wrap">
          <div class="text-center mb-12">
            <p class="lp-kicker lp-rise">Painel</p>
            <h2 class="lp-h2 lp-rise" style="--d: 0.05">O mês inteiro numa tela</h2>
            <p class="lp-lead mx-auto max-w-xl lp-rise" style="--d: 0.1">
              Filtre por mês, ano, banco, fonte e tipo. Cada gráfico abre as transações por trás dele.
            </p>
          </div>

          <div class="lp-dash">
            <div class="lp-dash-stats">
              <div
                :for={{{label, value, tone, help}, i} <- Enum.with_index(dash_stats())}
                class="lp-stat lp-rise"
                style={"--d: #{0.15 + i * 0.06}"}
              >
                <span class="ui-caption">{label}</span>
                <strong class={tone}><.private_text text={value} /></strong>
                <span class="ui-caption"><.private_text text={help} /></span>
              </div>
            </div>

            <div class="lp-dash-grid" data-motion>
              <div class="lp-card lp-rise">
                <h3 class="lp-card-title">Despesas por categoria</h3>
                <div
                  id="landing-cat-hook"
                  phx-hook="CategoryChart"
                  data-categories={Jason.encode!(dash_categories())}
                >
                  <ul class="lp-cat-list">
                    <li :for={cat <- dash_categories()}>
                      <i style={"background-color: #{cat.color}"}></i>
                      <span class="flex-1 truncate">{cat.name}</span>
                      <span class="ui-private font-medium">{brl_float(cat.value)}</span>
                    </li>
                  </ul>
                </div>
              </div>

              <%!-- The dashboard's own toggle and calendar, with March's data --%>
              <div class="lp-card lp-rise" style="--d: 0.08">
                <div class="mb-3 flex items-center justify-between gap-3">
                  <h3 class="lp-card-title mb-0">Gastos diários</h3>
                  <SpendingCalendar.view_toggle id="landing-daily-view" view={@spending_view} />
                </div>
                <div :if={@spending_view == "calendar"} class="lp-cal">
                  <SpendingCalendar.heat_grid
                    id="landing-spending-calendar"
                    columns={~w(Dom Seg Ter Qua Qui Sex Sáb)}
                    rows={dash_calendar()}
                  />
                </div>
                <div
                  :if={@spending_view == "bars"}
                  id="landing-daily-chart"
                  phx-hook="DailyChart"
                  phx-update="ignore"
                  data-daily={Jason.encode!(dash_daily())}
                >
                </div>
                <p class="ui-caption mt-3">
                  {if @spending_view == "calendar",
                    do: "Quanto mais vermelho, mais caro foi o dia.",
                    else: "Cada barra é um dia de março."} Passe o mouse para ver o valor.
                </p>
              </div>
            </div>

            <div class="lp-card lp-rise" data-motion>
              <h3 class="lp-card-title">Fluxo de caixa</h3>
              <div class="lp-wipe" style="--d: 0.2">
                <div
                  id="landing-flow-hook"
                  phx-hook="CashFlowChart"
                  data-flow={Jason.encode!(dash_flow())}
                >
                </div>
              </div>
            </div>

            <div class="lp-dash-grid lp-dash-grid-3" data-motion>
              <div class="lp-card lp-rise">
                <h3 class="lp-card-title">Metas</h3>
                <ul class="lp-goals">
                  <li :for={{{label, pct, tone}, i} <- Enum.with_index(dash_goals())}>
                    <div class="flex justify-between ui-help">
                      <span>{label}</span><span>{pct}%</span>
                    </div>
                    <div class="lp-goal-track">
                      <i
                        class={["lp-goal-fill", tone]}
                        style={"--w: #{min(pct, 100)}%; --d: #{0.3 + i * 0.1}"}
                      >
                      </i>
                    </div>
                  </li>
                </ul>
              </div>
              <div class="lp-card lp-rise" style="--d: 0.08">
                <h3 class="lp-card-title">Despesas fixas</h3>
                <ul class="lp-list">
                  <li :for={{name, value} <- dash_fixed()}>
                    <span class="truncate">{name}</span><span class="ui-private ui-money-despesa font-medium">{value}</span>
                  </li>
                </ul>
                <p class="ui-caption mt-3">Detectadas sozinhas, mês após mês.</p>
              </div>
              <div class="lp-card lp-rise" style="--d: 0.16">
                <h3 class="lp-card-title">Parcelas</h3>
                <ul class="lp-list">
                  <li :for={{name, cur, total, value} <- dash_installments()}>
                    <span class="truncate">
                      {name} <small class="ui-caption">{cur}/{total}</small>
                    </span>
                    <span class="ui-private font-medium">{value}</span>
                  </li>
                </ul>
                <p class="ui-caption mt-3">Projeção dos próximos 12 meses no painel.</p>
              </div>
            </div>
          </div>
        </div>
      </section>

      <%!-- IA: quatro especialistas, um de cada vez --%>
      <section
        id="ia"
        class="lp-scene lp-scene-long lp-alt"
        data-scene
        aria-label="Inteligência artificial"
      >
        <div class="lp-stage">
          <div class="lp-stage-text lp-panels">
            <div
              :for={{{kicker, title, text}, i} <- Enum.with_index(ai_panels())}
              class="lp-panel"
              style={panel_window(i, 4)}
            >
              <p class="lp-kicker">{kicker}</p>
              <h2 class="lp-h2">{title}</h2>
              <p class="lp-lead">{text}</p>
            </div>
            <ol class="lp-dots" aria-hidden="true">
              <li :for={i <- 0..3} class="lp-dot" style={panel_window(i, 4)}></li>
            </ol>
          </div>

          <div class="lp-stage-mock lp-panels">
            <%!-- 1. Advanced search: types the whole request, then loads like the app --%>
            <div class="lp-panel" style="--a: -0.04; --b: 0.25">
              <div class="lp-card lp-ai-search" style="--ba: 0.088; --bb: 0.15">
                <div class="ui-ai-search-bar">
                  <.icon name="hero-sparkles" class="size-4 shrink-0 text-primary" />
                  <span class="lp-ai-input lp-t" style="--a: 0.012; --b: 0.075">
                    <span class="lp-ai-placeholder" aria-hidden="true">
                      Peça à IA: gastos com delivery nos últimos 3 meses
                    </span>
                    <span class="lp-typer">
                      <span class="lp-typer-ghost" aria-hidden="true">{search_request()}</span>
                      <span class="lp-typer-text">{search_request()}</span>
                    </span>
                  </span>
                  <span class="ui-model-picker lp-ai-model">
                    <.icon name="hero-cpu-chip" class="size-4 shrink-0" />
                    <span class="truncate">gemini-2.5-flash</span>
                  </span>
                  <span class="btn btn-primary btn-sm btn-square lp-ai-send" aria-hidden="true">
                    <.icon name="hero-arrow-up" class="size-4" />
                  </span>
                </div>
                <div class="lp-stack">
                  <p class="ui-help mt-2 flex items-center gap-2 lp-ai-loading">
                    <span class="loading loading-spinner loading-xs"></span> Montando a busca…
                  </p>
                  <div class="ui-ai-search-result lp-t lp-t-rise" style="--a: 0.15; --b: 0.19">
                    <span class="ui-ai-query">
                      <code class="ui-query-code">
                        ("vida plena" OR farmacia OR "plano de saúde") AND type:expense AND date>=today-3m
                      </code>
                      <span class="ui-ai-query-action">
                        <.icon name="hero-arrow-down-left" class="size-3.5" /> Usar
                      </span>
                    </span>
                    <p class="ui-help mt-1.5 flex flex-wrap items-center gap-x-2">
                      <span>Inclui Vida Plena e farmácias, que estavam fora de Saúde.</span>
                      <span class="ui-caption">gemini-2.5-flash</span>
                    </p>
                    <span class="ui-ai-search-close" aria-hidden="true">
                      <.icon name="hero-x-mark" class="size-4" />
                    </span>
                  </div>
                </div>
              </div>
            </div>

            <%!-- 2. Análise --%>
            <div class="lp-panel" style="--a: 0.25; --b: 0.5">
              <div class="lp-card">
                <div class="flex items-center gap-3">
                  <span class="flex size-9 shrink-0 items-center justify-center ui-rounded-box bg-primary/10 text-primary">
                    <.icon name="hero-sparkles" class="size-5" />
                  </span>
                  <span class="min-w-0 flex-1">
                    <span class="font-semibold block">Análise de março de 2026</span>
                    <span class="ui-help block">Analisada agora · gemini-pro</span>
                  </span>
                  <span class="ui-score ui-score-good lp-t lp-t-pop" style="--a: 0.3; --b: 0.35">
                    8.2
                  </span>
                </div>
                <h4 class="font-semibold mt-4 lp-t lp-t-rise" style="--a: 0.33; --b: 0.38">
                  Março equilibrado, com folga curta
                </h4>
                <ul class="mt-2 space-y-2 ui-body">
                  <li
                    :for={{{icon, tone, text}, i} <- Enum.with_index(analysis_points())}
                    class="flex items-start gap-2 lp-t lp-t-rise"
                    style={"--a: #{0.36 + i * 0.03}; --b: #{0.41 + i * 0.03}"}
                  >
                    <.icon name={icon} class={["size-4 shrink-0 mt-0.5", tone]} />
                    <span class="ui-text-secondary"><.private_text text={text} /></span>
                  </li>
                </ul>
              </div>
            </div>

            <%!-- 3. Processamento --%>
            <div class="lp-panel" style="--a: 0.5; --b: 0.75">
              <div class="lp-card">
                <div class="flex items-center gap-3">
                  <span class="lp-file-icon"><.icon name="hero-document-text" class="size-4" /></span>
                  <span class="min-w-0 flex-1">
                    <span class="font-medium block">fatura-itau-marco.pdf</span>
                    <span class="ui-caption block">Nenhum parser conhece este layout</span>
                  </span>
                  <span class="ui-tag ui-tag-salvo lp-t lp-t-pop" style="--a: 0.55; --b: 0.6">
                    <.icon name="hero-cpu-chip" class="size-3" /> gemini-flash
                  </span>
                </div>
                <div class="lp-pdf-lines lp-t" style="--a: 0.54; --b: 0.66">
                  <i :for={_ <- 1..4}></i>
                </div>
                <ul class="lp-list mt-3">
                  <li
                    :for={{{desc, cat, value}, i} <- Enum.with_index(processed_rows())}
                    class="lp-t lp-t-rise"
                    style={"--a: #{0.6 + i * 0.03}; --b: #{0.66 + i * 0.03}"}
                  >
                    <span class="truncate">
                      <span class="ui-private-name">{desc}</span>
                      <small class="ui-caption">{cat}</small>
                    </span>
                    <span class="ui-private ui-money-despesa font-medium">{value}</span>
                  </li>
                </ul>
              </div>
            </div>

            <%!-- 4. Chat --%>
            <div class="lp-panel" style="--a: 0.75; --b: 1.5">
              <div class="lp-chat">
                <div class="ui-chat-row justify-end lp-t lp-t-rise" style="--a: 0.76; --b: 0.8">
                  <p class="ui-chat-bubble">Quanto gastei com saúde nos últimos 3 meses?</p>
                </div>
                <div class="flex flex-wrap gap-1.5 lp-t lp-t-rise" style="--a: 0.8; --b: 0.85">
                  <span class="ui-chat-step ui-chat-step-data">
                    <.icon name="hero-circle-stack" class="size-3" /> Estabelecimentos
                  </span>
                  <span class="ui-chat-step ui-chat-step-agent">
                    <.icon name="hero-sparkles" class="size-3" /> Especialista de pesquisa
                  </span>
                  <span class="ui-chat-step ui-chat-step-data">
                    <.icon name="hero-circle-stack" class="size-3" /> Busca de transações
                  </span>
                </div>
                <div class="ui-chat-row lp-t lp-t-rise" style="--a: 0.85; --b: 0.9">
                  <div class="ui-chat-answer ui-chat-html">
                    <p>
                      Saúde levou <strong class="ui-private ui-money-despesa">R$ 1.264,30</strong>
                      nos últimos três meses,
                      incluindo a <span class="ui-private-name">Vida Plena</span>, que estava em Pagamentos.
                    </p>
                    <table class="lp-t lp-t-wipe" style="--a: 0.9; --b: 0.97">
                      <thead>
                        <tr>
                          <th>Mês</th>
                          <th>Vida Plena</th>
                          <th>Farmácias</th>
                          <th class="text-right">Total</th>
                        </tr>
                      </thead>
                      <tbody>
                        <tr :for={{m, a, b, t} <- chat_rows()}>
                          <td>{m}</td>
                          <td><span class="ui-private">{a}</span></td>
                          <td><span class="ui-private">{b}</span></td>
                          <td class="text-right ui-money-despesa">
                            <span class="ui-private">{t}</span>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <%!-- Open Finance: connect through Meu Pluggy, the data flows, "Hoje" on the dashboard --%>
      <section
        id="open-finance"
        class="lp-scene lp-scene-3"
        data-scene
        aria-label="Open Finance via Pluggy"
      >
        <div class="lp-stage">
          <div class="lp-stage-text lp-panels">
            <div
              :for={{{kicker, title, text}, i} <- Enum.with_index(open_finance_panels())}
              class="lp-panel"
              style={panel_window(i, 3)}
            >
              <p class="lp-kicker">{kicker}</p>
              <h2 class="lp-h2">{title}</h2>
              <p class="lp-lead">{text}</p>
            </div>
            <ol class="lp-dots" aria-hidden="true">
              <li :for={i <- 0..2} class="lp-dot" style={panel_window(i, 3)}></li>
            </ol>
          </div>

          <div class="lp-stage-mock lp-panels">
            <%!-- 1. Connect: the Meu Pluggy widget, then the banks show up --%>
            <div class="lp-panel lp-of-connect" style={panel_window(0, 3)}>
              <div class="lp-card">
                <div class="flex flex-wrap items-center gap-2">
                  <OpenFinanceComponents.open_finance_logo class="size-5 shrink-0" />
                  <h3 class="lp-card-title mb-0">Open Finance</h3>
                  <span class="ui-tag ui-tag-neutro">
                    via <img src={~p"/images/pluggy-logo.png"} alt="Pluggy" class="h-3 w-auto" />
                  </span>
                </div>
                <p class="ui-help mt-2">
                  Saldos, cartões e transações lidos direto dos seus bancos, com o consentimento do
                  Open Finance Brasil.
                </p>
                <ul class="lp-of-conns">
                  <li
                    :for={{{bank, logo, detail}, i} <- Enum.with_index(of_connections())}
                    class="lp-of-conn lp-t lp-t-rise"
                    style={"--a: #{0.2 + i * 0.05}; --b: #{0.25 + i * 0.05}"}
                  >
                    <img src={logo} alt="" class="size-8 shrink-0 rounded-full" />
                    <span class="min-w-0 flex-1">
                      <span class="block font-medium">{bank}</span>
                      <span class="ui-caption block truncate">{detail}</span>
                    </span>
                    <span class="ui-tag ui-tag-ativo">Atualizado</span>
                  </li>
                </ul>
                <span class="btn btn-primary btn-sm mt-4" aria-hidden="true">
                  <.icon name="hero-plus" class="size-4" /> Conectar via Meu Pluggy
                </span>
              </div>

              <div class="lp-of-dim lp-win" style="--a: 0.03; --b: 0.2" aria-hidden="true"></div>
              <div class="lp-card lp-of-widget lp-win" style="--a: 0.03; --b: 0.2">
                <div class="flex items-center justify-between gap-2">
                  <img src={~p"/images/pluggy-logo.png"} alt="Pluggy" class="h-4 w-auto" />
                  <span class="ui-caption">Meu Pluggy</span>
                </div>
                <p class="mt-3 text-sm font-semibold">Escolha o banco</p>
                <div class="lp-of-banks">
                  <span class="lp-of-bank lp-t" style="--a: 0.07; --b: 0.09">
                    <img src={~p"/images/nubank-logo.png"} alt="" class="size-5 rounded-full" />
                    Nubank
                  </span>
                  <span class="lp-of-bank">
                    <img src={~p"/images/bradesco-logo.png"} alt="" class="size-5 rounded-full" />
                    Bradesco
                  </span>
                </div>
                <p class="ui-caption mt-3 mb-1.5">O banco compartilha, só para leitura:</p>
                <ul class="lp-of-perms">
                  <li
                    :for={{perm, i} <- Enum.with_index(of_permissions())}
                    class="lp-t lp-t-pop"
                    style={"--a: #{0.1 + i * 0.015}; --b: #{0.12 + i * 0.015}"}
                  >
                    <.icon name="hero-check-circle" class="size-4 text-success" /> {perm}
                  </li>
                </ul>
              </div>
            </div>

            <%!-- 2. The data path: bank → Open Finance Brasil → Pluggy → your Grana --%>
            <div class="lp-panel" style={panel_window(1, 3)}>
              <div class="lp-card lp-of-flow">
                <div class="lp-of-track">
                  <div class="lp-of-line lp-t" style="--a: 0.36; --b: 0.46" aria-hidden="true">
                    <i></i>
                  </div>
                  <div class="lp-of-node">
                    <span class="lp-of-icon lp-of-icon-banks">
                      <img src={~p"/images/nubank-logo.png"} alt="" class="size-7 rounded-full" />
                      <img src={~p"/images/bradesco-logo.png"} alt="" class="size-7 rounded-full" />
                    </span>
                    <span>Seus bancos<small>você autoriza</small></span>
                  </div>
                  <div class="lp-of-node">
                    <span class="lp-of-icon">
                      <OpenFinanceComponents.open_finance_logo class="size-7" />
                    </span>
                    <span>Open Finance Brasil<small>regulado pelo BC</small></span>
                  </div>
                  <div class="lp-of-node">
                    <span class="lp-of-icon lp-of-icon-wide">
                      <img src={~p"/images/pluggy-logo.png"} alt="Pluggy" class="h-3.5 w-auto" />
                    </span>
                    <span>Pluggy<small>reúne os dados</small></span>
                  </div>
                  <div class="lp-of-node">
                    <span class="lp-of-icon lp-of-icon-grana">
                      <GranaWeb.BrandComponents.logo class="size-8" />
                    </span>
                    <span>Seu Grana<small>guarda e organiza</small></span>
                  </div>
                  <span
                    :for={{{icon, label}, i} <- Enum.with_index(of_packets())}
                    class="lp-of-packet lp-t"
                    style={"--a: #{0.38 + i * 0.06}; --b: #{0.54 + i * 0.06}"}
                    aria-hidden="true"
                  >
                    <.icon name={icon} class="size-3.5" />
                    <span class="lp-of-packet-label">{label}</span>
                  </span>
                </div>
                <ul class="lp-of-facts">
                  <li
                    :for={{{icon, text}, i} <- Enum.with_index(open_finance_bullets())}
                    class="lp-t lp-t-rise"
                    style={"--a: #{0.42 + i * 0.05}; --b: #{0.48 + i * 0.05}"}
                  >
                    <.icon name={icon} class="size-5 shrink-0 text-primary" /> <span>{text}</span>
                  </li>
                </ul>
              </div>
            </div>

            <%!-- 3. "Hoje": the block on top of the dashboard --%>
            <div class="lp-panel" style={panel_window(2, 3)}>
              <div id="open-finance-preview" class="lp-card lp-of-today">
                <div class="mb-3 flex items-center justify-between gap-3">
                  <span class="flex items-center gap-2">
                    <OpenFinanceComponents.open_finance_logo class="size-5 shrink-0" />
                    <h3 class="lp-card-title mb-0">Hoje</h3>
                  </span>
                  <span class="ui-help">Open Finance · atualizado há 12 min</span>
                </div>
                <div class="lp-of-tiles">
                  <div
                    :for={{{id, label, value, tone, caption}, i} <- Enum.with_index(of_tiles())}
                    class="lp-t lp-t-rise"
                    style={"--a: #{0.69 + i * 0.03}; --b: #{0.74 + i * 0.03}"}
                  >
                    <.stat_tile id={id} label={label} value={value} tone={tone} caption={caption} />
                  </div>
                </div>
                <div class="lp-of-bank-grid">
                  <div
                    :for={{bank, i} <- Enum.with_index(of_today_banks())}
                    class="lp-of-bank-card lp-t lp-t-rise"
                    style={"--a: #{0.76 + i * 0.04}; --b: #{0.81 + i * 0.04}"}
                  >
                    <div class="mb-2 flex items-center gap-2">
                      <img src={bank.logo} alt="" class="size-6 shrink-0 rounded-full" />
                      <span class="font-medium">{bank.name}</span>
                    </div>
                    <p class="ui-caption mb-1 font-semibold uppercase tracking-wide">Contas</p>
                    <div class="flex items-baseline justify-between gap-2 py-0.5 text-sm">
                      <span class="truncate">
                        Conta corrente<span class="ui-text-tertiary"> ••{bank.account}</span>
                      </span>
                      <span class="ui-private font-medium tabular-nums whitespace-nowrap">
                        {bank.balance}
                      </span>
                    </div>
                    <p class="ui-caption mt-2 mb-1 font-semibold uppercase tracking-wide">
                      Cartão de crédito
                    </p>
                    <div class="flex items-baseline justify-between gap-2 text-sm">
                      <span class="truncate">
                        {bank.card}<span class="ui-text-tertiary"> ••{bank.card_number}</span>
                      </span>
                      <span class="text-right whitespace-nowrap">
                        <span class="ui-caption block leading-none">fatura atual</span>
                        <span class="ui-private font-medium tabular-nums">{bank.invoice}</span>
                      </span>
                    </div>
                    <div class="lp-goal-track">
                      <i
                        class="lp-goal-fill bg-warning"
                        style={"--w: #{bank.usage}%; --d: #{0.8 + i * 0.04}"}
                      >
                      </i>
                    </div>
                    <p class="ui-caption mt-0.5">
                      {bank.usage}% do limite usado · {bank.dates}
                    </p>
                  </div>
                </div>
                <div class="lp-of-months lp-t lp-t-rise" style="--a: 0.86; --b: 0.92">
                  <p class="ui-help mb-2 flex items-center gap-1.5">
                    <.icon name="hero-chevron-right" class="size-3.5" />
                    Meses sem upload cobertos pelo Open Finance (2)
                  </p>
                  <div class="flex gap-1">
                    <div :for={{initial, kind} <- of_months()} class="grid justify-items-center gap-1">
                      <span class="ui-caption">{initial}</span>
                      <span class={["grana-calendar-cell grid size-[18px] place-items-center", kind]}>
                        <span
                          :if={kind == "calendar-count-0"}
                          class="grid size-3 place-items-center rounded-full bg-base-100 shadow-sm"
                        >
                          <OpenFinanceComponents.open_finance_logo class="size-2" />
                        </span>
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <%!-- Your way: privacy and the visual styles, live on this very page --%>
      <section id="privacidade" class="lp-section lp-alt" data-motion>
        <div class="lp-wrap">
          <div class="text-center mb-12">
            <p class="lp-kicker lp-rise">Do seu jeito</p>
            <h2 class="lp-h2 lp-rise" style="--d: 0.05">Mostre só o que quiser</h2>
            <p class="lp-lead mx-auto max-w-xl lp-rise" style="--d: 0.1">
              Experimente aqui: o que você mudar vale para a página inteira, como no app.
            </p>
          </div>
          <div class="lp-dash-grid lp-custom">
            <div id="lp-privacy" class="lp-card lp-rise" style="--d: 0.15">
              <h3 class="lp-card-title flex items-center gap-2">
                <.icon name="hero-eye-slash" class="size-5 text-primary" /> Modo privacidade
              </h3>
              <p class="ui-help mb-4">
                Para gravar ou mostrar a tela: o que estiver oculto vira uma camada fosca, na hora,
                em todas as páginas.
              </p>
              <div class="lp-switch-row">
                <div>
                  <p class="ui-body">Ocultar valores</p>
                  <p class="ui-help">Receita e despesa seguem nas cores; o número, não.</p>
                </div>
                <.switch
                  id="lp-hide-values"
                  label="Ocultar valores"
                  checked={@hide_values}
                  phx-click="toggle_privacy"
                  phx-value-key="values"
                />
              </div>
              <div class="lp-switch-row">
                <div>
                  <p class="ui-body">Ocultar nomes</p>
                  <p class="ui-help">Descrições, pessoas, lojas e nomes de arquivos.</p>
                </div>
                <.switch
                  id="lp-hide-names"
                  label="Ocultar nomes"
                  checked={@hide_names}
                  phx-click="toggle_privacy"
                  phx-value-key="names"
                />
              </div>
              <ul class="lp-privacy-rows">
                <li :for={{desc, category, value, tone} <- privacy_rows()}>
                  <span class="min-w-0">
                    <span class="ui-private-name truncate block">{desc}</span>
                    <span class="ui-caption">{category}</span>
                  </span>
                  <span class={["ui-private font-medium tabular-nums", tone]}>{value}</span>
                </li>
              </ul>
              <p class="ui-caption mt-3 flex items-center gap-1.5">
                <.icon name="hero-information-circle" class="size-4 shrink-0" />
                Vale também para gráficos, dicas e respostas do chat.
              </p>
            </div>

            <div id="lp-styles" class="lp-card lp-rise" style="--d: 0.25">
              <div class="mb-1 flex flex-wrap items-center justify-between gap-3">
                <h3 class="lp-card-title mb-0 flex items-center gap-2">
                  <.icon name="hero-paint-brush" class="size-5 text-primary" /> Estilo visual
                </h3>
                <Layouts.theme_toggle />
              </div>
              <p class="ui-help mb-4">
                Sete estilos, cada um no claro e no escuro. Clique em um e a página inteira muda,
                como no app.
              </p>
              <Layouts.visual_style_toggle grid />
            </div>
          </div>
        </div>
      </section>

      <%!-- Self-hosted: where the data lives, told like the logo story --%>
      <section
        id="seguranca"
        class="lp-scene lp-scene-3"
        data-scene
        aria-label="Self-hosted e segurança"
      >
        <div class="lp-stage">
          <div class="lp-stage-text lp-panels">
            <div class="lp-panel" style={panel_window(0, 3)}>
              <p class="lp-kicker">Self-hosted</p>
              <h2 class="lp-h2">Num app comum, seus dados moram com eles</h2>
              <p class="lp-lead">
                Extratos, saldos e o acesso ao seu banco vão para o servidor de uma empresa. Ela
                guarda, cruza e decide o que fazer com tudo isso.
              </p>
            </div>
            <div class="lp-panel" style={panel_window(1, 3)}>
              <p class="lp-kicker">Self-hosted</p>
              <h2 class="lp-h2">No Grana, eles moram com você</h2>
              <p class="lp-lead">
                O Grana roda num servidor seu: um computador em casa, uma VPS, um Raspberry Pi.
                Tudo fica num único arquivo SQLite, e só sai de lá o que você configurar.
              </p>
            </div>
            <div class="lp-panel" style={panel_window(2, 3)}>
              <p class="lp-kicker">Segurança</p>
              <h2 class="lp-h2">Seus dados, no seu servidor</h2>
              <ul class="lp-sec-list">
                <li :for={{icon, title, text} <- security_items()}>
                  <span class="lp-feature-icon"><.icon name={icon} class="size-5" /></span>
                  <span class="min-w-0">
                    <span class="block font-semibold">{title}</span>
                    <span class="ui-help block">{text}</span>
                  </span>
                </li>
              </ul>
            </div>
            <ol class="lp-dots" aria-hidden="true">
              <li :for={i <- 0..2} class="lp-dot" style={panel_window(i, 3)}></li>
            </ol>
          </div>

          <div class="lp-stage-mock">
            <div class="lp-card lp-sh" aria-hidden="true">
              <svg class="lp-sh-lines" viewBox="0 0 100 100" preserveAspectRatio="none">
                <line class="lp-sh-link" x1="14" y1="50" x2="38" y2="50" />
                <line
                  :for={{_icon, _name, _note, y} <- self_hosted_links()}
                  class="lp-sh-out"
                  x1="75"
                  y1="50"
                  x2="86"
                  y2={y}
                />
              </svg>

              <div class="lp-sh-node lp-sh-you">
                <span class="lp-sh-icon"><.icon name="hero-user" class="size-6" /></span>
                <span class="lp-sh-label">Você</span>
              </div>

              <div class="lp-sh-target lp-sh-cloud">
                <span class="lp-sh-box">
                  <.icon name="hero-building-office-2" class="size-9" />
                  <span class="lp-sh-label">Servidor de um app</span>
                </span>
                <i class="lp-sh-strike lp-t" style="--a: 0.24; --b: 0.3"></i>
              </div>
              <span
                :for={{{icon, text, x, y}, i} <- Enum.with_index(cloud_tags())}
                class="lp-sh-tag lp-t lp-t-pop"
                style={"--a: #{0.12 + i * 0.03}; --b: #{0.16 + i * 0.03}; --x: #{x}; --y: #{y}"}
              >
                <.icon name={icon} class="size-3.5" /> {text}
              </span>

              <div class="lp-sh-target lp-sh-server">
                <span class="lp-sh-box">
                  <GranaWeb.BrandComponents.logo class="size-9" />
                  <span class="lp-sh-file">
                    <.icon name="hero-circle-stack" class="size-3.5" /> grana.db
                  </span>
                  <span class="lp-sh-label">Seu servidor</span>
                </span>
              </div>

              <div
                :for={{{icon, name, note, y}, i} <- Enum.with_index(self_hosted_links())}
                class="lp-sh-node lp-sh-ext lp-t lp-t-pop"
                style={"--a: #{0.52 + i * 0.03}; --b: #{0.57 + i * 0.03}; --y: #{y}"}
              >
                <span class="lp-sh-mini"><.icon name={icon} class="size-4" /></span>
                <span class="lp-sh-label">{name}<small>{note}</small></span>
              </div>
              <p class="lp-sh-note lp-t lp-t-rise" style="--a: 0.58; --b: 0.63">
                só sai o que você configurar
              </p>

              <span
                :for={{{icon, text, x, y}, i} <- Enum.with_index(server_badges())}
                class="lp-sh-tag lp-sh-badge lp-t lp-t-pop"
                style={"--a: #{0.7 + i * 0.04}; --b: #{0.75 + i * 0.04}; --x: #{x}; --y: #{y}"}
              >
                <.icon name={icon} class="size-3.5" /> {text}
              </span>

              <span
                :for={{icon, a} <- self_hosted_packets()}
                class="lp-sh-packet lp-t"
                style={"--a: #{a}; --b: #{a + 0.12}"}
              >
                <.icon name={icon} class="size-3.5" />
              </span>
            </div>
          </div>
        </div>
      </section>

      <%!-- Install: three steps, each with its terminal; commands copy with one click --%>
      <section id="instalacao" class="lp-section lp-alt" data-motion phx-hook=".CopyCommands">
        <div class="lp-wrap">
          <div class="text-center mb-10">
            <p class="lp-kicker lp-rise">Instalação</p>
            <h2 class="lp-h2 lp-rise" style="--d: 0.05">Instale onde preferir</h2>
            <p class="lp-lead mx-auto max-w-2xl lp-rise" style="--d: 0.1">
              No seu servidor (Debian 12+ ou Ubuntu 22.04+, x86_64 ou arm64), com Docker ou na
              nuvem do Fly.io. Nenhuma variável de ambiente é obrigatória: o resto se configura
              pela tela.
            </p>
            <div class="lp-seg lp-rise" style="--d: 0.15" role="group" aria-label="Forma de instalar">
              <button
                :for={{method, icon, label} <- install_methods()}
                id={"install-method-#{method}"}
                type="button"
                class={["lp-seg-btn", @install_method == method && "is-active"]}
                aria-pressed={to_string(@install_method == method)}
                phx-click="set_install_method"
                phx-value-method={method}
              >
                <.icon name={icon} class="size-4" /> {label}
              </button>
            </div>
          </div>

          <ol class="lp-install">
            <li id="instalacao-passo-1" class="lp-install-step" data-motion>
              <div class="lp-install-rail" aria-hidden="true">
                <span class="lp-install-number">1</span><i class="lp-install-line"></i>
              </div>
              <div class="lp-install-copy lp-rise">
                <h3>Instale</h3>
                <p :if={@install_method == "script"} class="ui-help">
                  O script baixa a release da sua arquitetura, confere o sha256, cria o usuário
                  <code>grana</code>
                  e ativa o serviço no systemd. Dados em <code>/var/lib/grana</code>.
                </p>
                <p :if={@install_method == "docker"} class="ui-help">
                  A imagem <code>ghcr.io/hjunior29/grana</code>
                  (amd64 e arm64) guarda tudo no volume <code>grana-data</code>. Variáveis, se
                  quiser, num <code>.env</code>
                  ao lado do compose.
                </p>
                <div :if={@install_method == "fly"} id="instalacao-fly" class="ui-help">
                  <p>
                    Uma máquina pequena roda a mesma imagem, com o banco num volume e HTTPS em <code>meu-grana.fly.dev</code>. O
                    <code>fly.toml</code>
                    já vem pronto: troque <code>meu-grana</code>
                    pelo nome do seu app.
                  </p>
                  <ul class="lp-install-tips">
                    <li :for={tip <- fly_tips()}>{tip}</li>
                  </ul>
                </div>
              </div>
              <.terminal
                id="instalacao-terminal-1"
                title={terminal_title(@install_method)}
                commands={install_commands(@install_method)}
                output={install_output(@install_method)}
              />
            </li>

            <li id="instalacao-passo-2" class="lp-install-step" data-motion>
              <div class="lp-install-rail" aria-hidden="true">
                <span class="lp-install-number">2</span><i class="lp-install-line"></i>
              </div>
              <div class="lp-install-copy lp-rise">
                <h3>Pegue o código do primeiro acesso</h3>
                <p class="ui-help">
                  Sem dono, a instância leva as telas do app ao setup, que pede um código de uso
                  único impresso no log. Ele vale até a conta ser criada.
                </p>
              </div>
              <.terminal
                id="instalacao-terminal-2"
                title={terminal_title(@install_method)}
                commands={log_commands(@install_method)}
                output={log_output(@install_method)}
              />
            </li>

            <li id="instalacao-passo-3" class="lp-install-step" data-motion>
              <div class="lp-install-rail" aria-hidden="true">
                <span class="lp-install-number">3</span>
              </div>
              <div class="lp-install-copy lp-rise">
                <h3>Configure a sua instância</h3>
                <p class="ui-help">
                  Abra <code>{setup_url(@install_method)}</code>, digite o código e crie a sua
                  conta, ou restaure um backup. Um onboarding opcional configura o resto; cada
                  etapa pode ser pulada e refeita em Configurações.
                </p>
                <p class="ui-help mt-2">{https_note(@install_method)}</p>
              </div>
              <div class="lp-browser lp-rise" style="--d: 0.12" aria-hidden="true">
                <div class="lp-term-bar">
                  <span class="lp-term-dots"><i></i><i></i><i></i></span>
                  <span class="lp-browser-url">
                    <.icon name="hero-globe-alt" class="size-3.5" /> {setup_host(@install_method)}/setup
                  </span>
                </div>
                <div class="lp-browser-body">
                  <ol class="lp-setup-dots">
                    <li :for={n <- 1..4} class={n == 1 && "is-active"}>{n}</li>
                  </ol>
                  <p class="font-semibold">Configuração inicial</p>
                  <span class="ui-label mt-3 block">Código do setup</span>
                  <span class="lp-setup-input">
                    <span class="lp-typer lp-t" style="--a: 0.3; --b: 0.55">
                      <span class="lp-typer-ghost">{setup_code()}</span>
                      <span class="lp-typer-text">{setup_code()}</span>
                    </span>
                  </span>
                  <span class="btn btn-primary btn-sm mt-3 w-full">Continuar</span>
                  <div class="lp-setup-next lp-t lp-t-rise" style="--a: 0.6; --b: 0.75">
                    <span class="ui-caption">Depois, se quiser:</span>
                    <span :for={{icon, label} <- onboarding_steps()} class="lp-setup-chip">
                      <.icon name={icon} class="size-3.5" /> {label}
                    </span>
                  </div>
                </div>
              </div>
            </li>
          </ol>

          <p id="instalacao-pikapods" class="ui-help text-center mt-12 lp-rise" style="--d: 0.45">
            Sem terminal? O
            <a href="https://www.pikapods.com" target="_blank" class="link">PikaPods</a>
            hospeda apps open source do catálogo dele, a partir de US$ 1,80/mês. O Grana ainda não
            está lá:
            <a href="https://feedback.pikapods.com" target="_blank" class="link">peça o Grana</a>
          </p>

          <p class="text-center mt-6 lp-rise" style="--d: 0.5">
            <a
              id="instalacao-readme"
              href="https://github.com/hjunior29/grana#readme"
              target="_blank"
              rel="noopener"
              class="btn btn-ghost"
            >
              <.icon name="hero-book-open" class="size-5" /> Guia completo no README
            </a>
          </p>
        </div>
      </section>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyCommands">
        // Copies the commands of a terminal. Plain HTTP on the LAN has no clipboard API,
        // so it falls back to a hidden textarea.
        export default {
          mounted() {
            this.el.addEventListener("click", e => {
              const button = e.target.closest("[data-copy]")
              if (!button) return
              this.copy(button.dataset.copy).then(() => {
                const label = button.querySelector("[data-copy-label]")
                label.textContent = "Copiado"
                button.classList.add("is-copied")
                clearTimeout(button.copyTimer)
                button.copyTimer = setTimeout(() => {
                  label.textContent = "Copiar"
                  button.classList.remove("is-copied")
                }, 1600)
              })
            })
          },
          copy(text) {
            if (navigator.clipboard && window.isSecureContext) {
              return navigator.clipboard.writeText(text)
            }
            const area = document.createElement("textarea")
            area.value = text
            area.setAttribute("readonly", "")
            area.style.cssText = "position:fixed;top:0;opacity:0"
            document.body.appendChild(area)
            area.select()
            document.execCommand("copy")
            area.remove()
            return Promise.resolve()
          }
        }
      </script>

      <%!-- CTA --%>
      <section id="cta" class="lp-section" data-motion>
        <div class="lp-wrap lp-narrow text-center">
          <GranaWeb.BrandComponents.logo class="block size-20 mx-auto mb-6 lp-rise" />
          <h2 class="lp-h2 lp-rise" style="--d: 0.1">Pronto para organizar as suas finanças?</h2>
          <p class="lp-lead lp-rise" style="--d: 0.2">
            {if @demo,
              do: "Veja a demonstração ou instale o Grana no seu próprio servidor.",
              else: "Entre na sua instância ou instale o Grana no seu próprio servidor."}
          </p>
          <div class="lp-actions lp-rise" style="--d: 0.3">
            <.link
              :if={@demo}
              id="cta-demo"
              navigate={demo_path(@current_scope)}
              class="btn btn-primary btn-lg"
            >
              Ver a demo
            </.link>
            <.link
              :if={!@demo}
              id="cta-login"
              navigate={~p"/users/log-in"}
              class="btn btn-primary btn-lg"
            >
              Entrar
            </.link>
            <a href="#instalacao" class="btn btn-ghost btn-lg">Instalar no seu servidor</a>
          </div>
        </div>
      </section>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ScrollMotion">
        // Motion pela rolagem: cada [data-motion] ganha --p de 0 a 1 conforme entra na tela;
        // cada [data-scene] (seção alta com palco preso) ganha --p conforme é atravessada.
        // O CSS faz o resto a partir de --p. Com "reduzir movimento", tudo nasce pronto.
        const clamp = v => Math.min(1, Math.max(0, v))

        export default {
          mounted() {
            this.reduced = matchMedia("(prefers-reduced-motion: reduce)").matches
            this.collect()
            if (this.reduced) return
            this.onScroll = () => this.queue()
            addEventListener("scroll", this.onScroll, {passive: true})
            addEventListener("resize", this.onScroll)
            this.render()
          },
          // A server patch (the switches, the tabs) drops the inline --p: write it again.
          updated() {
            this.collect()
            if (!this.reduced) this.render()
          },
          collect() {
            this.items = [...this.el.querySelectorAll("[data-motion], [data-scene]")].map(el => ({
              el, scene: el.hasAttribute("data-scene"), last: null
            }))
            if (this.reduced) this.items.forEach(({el}) => el.style.setProperty("--p", "1"))
          },
          destroyed() {
            removeEventListener("scroll", this.onScroll)
            removeEventListener("resize", this.onScroll)
            cancelAnimationFrame(this.raf)
          },
          queue() {
            if (this.raf) return
            this.raf = requestAnimationFrame(() => {
              this.raf = null
              this.render()
            })
          },
          render() {
            const vh = innerHeight
            for (const item of this.items) {
              const r = item.el.getBoundingClientRect()
              if (r.top > vh + 80 || r.bottom < -80) continue
              const p = item.scene
                ? clamp(-r.top / (r.height - vh))
                : clamp((vh - r.top) / (vh * 0.55))
              const value = p.toFixed(3)
              if (value === item.last) continue
              item.last = value
              item.el.style.setProperty("--p", value)
            }
          }
        }
      </script>

      <%!-- Footer --%>
      <footer class="border-t border-base-content/5 px-4 sm:px-6 lg:px-8 py-8">
        <div class="max-w-6xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-4">
          <a id="footer-brand" href="/" class="flex items-center">
            <GranaWeb.BrandComponents.brand logo_class="size-6" wordmark_class="h-4 w-auto" />
          </a>
          <div class="flex flex-col sm:flex-row items-center gap-2 sm:gap-6 text-sm">
            <a
              id="footer-github"
              href="https://github.com/hjunior29/grana"
              target="_blank"
              rel="noopener"
              class="opacity-60 hover:opacity-100 transition-opacity"
            >
              Código aberto no GitHub
            </a>
            <span>
              Feito com Phoenix LiveView por
              <a href="https://github.com/hjunior29" class="text-primary hover:text-primary/80">
                hjunior29
              </a>
            </span>
          </div>
        </div>
      </footer>
    </div>
    """
  end

  defp facts do
    [
      {"hero-code-bracket", "Código aberto"},
      {"hero-user", "Uma conta: a do dono"},
      {"hero-circle-stack", "Um arquivo SQLite"},
      {"hero-key", "A sua chave de IA"}
    ]
  end

  defp steps do
    [
      {"hero-cloud-arrow-up", "Importe",
       "Extratos e faturas em CSV ou PDF, quantos quiser. O Open Finance preenche o que falta."},
      {"hero-tag", "Organize",
       "Cada transação na sua categoria: pelas suas regras primeiro, pela IA depois."},
      {"hero-chart-pie", "Entenda",
       "Painel, análise do mês e um chat que responde com os seus números."}
    ]
  end

  defp import_bullets do
    [
      {"hero-queue-list", "Sem limite de arquivos: a fila processa um a um, em segundo plano."},
      {"hero-document-text", "Nubank e Bradesco em CSV e PDF. Outros PDFs são lidos pela IA."},
      {"hero-arrow-path",
       "O CSV exportado pelo Grana volta como estava: banco, origem e categoria."}
    ]
  end

  defp import_files do
    [
      {"nubank-2026-03.csv", "Nubank · extrato", "41 transações"},
      {"fatura-nubank-03.pdf", "Nubank · fatura", "63 transações"},
      {"bradesco-marco.csv", "Bradesco · extrato", "58 transações"},
      {"fatura-itau.pdf", "Lido pela IA", "50 transações"}
    ]
  end

  defp category_bullets do
    [
      {"hero-bolt", "Regras suas: \"delivery\" vai para Alimentação, sempre."},
      {"hero-sparkles", "A IA só categoriza o que nenhuma regra pegou, com o seu provedor."},
      {"hero-academic-cap", "Corrigiu uma categoria? Vira regra para as próximas."}
    ]
  end

  defp category_rows do
    [
      {"02/03", "Delivery *Restaurante", "Alimentação", "#F59E0B", "- R$ 67,40", :rule},
      {"03/03", "Corrida *App", "Transporte", "#3B82F6", "- R$ 32,50", :rule},
      {"05/03", "Transferência recebida", "Salário", "#22C55E", "+ R$ 5.500,00", :rule},
      {"07/03", "Aluguel março", "Moradia", "#8B5CF6", "- R$ 1.500,00", :rule},
      {"08/03", "Sp Loja Aurora", "Compras", "#F97316", "- R$ 89,70", :ai},
      {"12/03", "Vida Plena Saúde", "Saúde", "#EF4444", "- R$ 412,00", :ai}
    ]
  end

  defp dash_stats do
    [
      {"Receitas", "R$ 9.650,00", "ui-money-receita", "2 transações"},
      {"Despesas", "R$ 4.987,00", "ui-money-despesa", "47 transações"},
      {"Investimentos", "R$ 1.200,00", nil, "3 aportes"},
      {"Saldo livre", "R$ 3.463,00", "ui-money-receita", "economizou 35,9%"}
    ]
  end

  defp dash_categories do
    [
      %{name: "Alimentação", value: 1847.0, color: "#F59E0B"},
      %{name: "Moradia", value: 1500.0, color: "#8B5CF6"},
      %{name: "Transporte", value: 650.0, color: "#3B82F6"},
      %{name: "Lazer", value: 480.0, color: "#EC4899"},
      %{name: "Saúde", value: 320.0, color: "#EF4444"},
      %{name: "Assinaturas", value: 190.0, color: "#A855F7"}
    ]
  end

  # March 2026: starts on a Sunday, weekends spend more, and the days add up to the
  # month's expenses on the stat cards.
  @march_spending [245.6, 64.9, 41.2, 547.9, 88.3, 52.7, 344.0, 356.8, 35.8, 61.2, 0.0] ++
                    [79.5, 158.0, 441.5, 262.9, 44.6, 0.0, 97.3, 70.1, 133.8, 498.6, 318.2] ++
                    [52.4, 39.9, 88.0, 0.0, 181.6, 389.7, 135.2, 45.0, 112.3]

  # Same cells as the dashboard's calendar (`GranaWeb.SpendingCalendar.heat_grid/1`).
  defp dash_calendar do
    max = Enum.max(@march_spending)
    blank = %{kind: :blank, label: nil, caption: nil, value: nil, intensity: nil, url: nil}

    @march_spending
    |> Enum.with_index(1)
    |> Enum.map(fn {value, day} ->
      cell = %{label: march_date(day, "/2026"), caption: day, url: nil}

      if value > 0,
        do:
          Map.merge(cell, %{kind: :spend, value: value, intensity: Float.round(value / max, 3)}),
        else: Map.merge(cell, %{kind: :empty, value: nil, intensity: nil})
    end)
    |> Enum.chunk_every(7, 7, Stream.cycle([blank]))
    |> Enum.map(&%{label: nil, cells: &1})
  end

  defp dash_daily do
    for {value, day} <- Enum.with_index(@march_spending, 1),
        value > 0,
        do: %{date: march_date(day, ""), value: value}
  end

  defp march_date(day, year),
    do: "#{day |> Integer.to_string() |> String.pad_leading(2, "0")}/03#{year}"

  defp dash_flow do
    targets =
      Enum.map(
        dash_categories(),
        &%{name: &1.name, value: &1.value, color: &1.color, kind: "category"}
      )

    %{
      sources: [
        %{name: "Salário", value: 8450.0, color: "var(--ui-receita)", kind: "category"},
        %{name: "Freela", value: 1200.0, color: "#14B8A6", kind: "category"}
      ],
      targets:
        targets ++
          [
            %{
              name: "Investimentos",
              value: 1200.0,
              color: "var(--color-info)",
              kind: "investment"
            },
            %{name: "Sobra", value: 3463.0, color: "var(--ui-receita)", kind: "surplus"}
          ]
    }
  end

  defp dash_goals do
    [
      {"Limite de gastos · R$ 6.000", 83, "bg-(--ui-receita)"},
      {"Meta de investimento · R$ 1.000", 120, "bg-(--ui-receita)"},
      {"Limite Alimentação · R$ 1.500", 123, "bg-(--ui-despesa)"}
    ]
  end

  defp dash_fixed do
    [
      {"Aluguel", "R$ 1.500,00"},
      {"Internet", "R$ 99,90"},
      {"Academia", "R$ 129,90"},
      {"Spotify", "R$ 21,90"}
    ]
  end

  defp dash_installments do
    [{"iPhone", 4, 12, "R$ 549,90"}, {"Sofá", 1, 8, "R$ 416,50"}, {"Curso", 2, 6, "R$ 199,90"}]
  end

  defp ai_panels do
    [
      {"Inteligência artificial · pesquisa", "Descreva a busca em português",
       "A IA monta a string da pesquisa avançada, olhando os seus estabelecimentos de verdade e validando cada consulta antes de entregar."},
      {"Inteligência artificial · análise", "Nota, resumo e dicas do mês",
       "No painel, uma análise por período: receitas, despesas, onde otimizar e se foi um mês bom. Refeita só quando os dados mudam."},
      {"Inteligência artificial · processamento", "PDFs que nenhum parser conhece",
       "Quando o layout é novo, a IA lê a fatura e devolve as transações. O histórico mostra qual modelo processou cada arquivo."},
      {"Inteligência artificial · chat", "Converse com os seus números",
       "Todo número vem do seu banco de dados, com consultas determinísticas; a IA só redige. A resposta continua mesmo se você sair da tela."}
    ]
  end

  defp analysis_points do
    [
      {"hero-check-circle", "ui-money-receita", "Sobraram R$ 3.463,00, 35,9% da receita."},
      {"hero-x-circle", "ui-money-despesa",
       "Alimentação passou de R$ 1.800,00, 24% acima da média."},
      {"hero-light-bulb", "text-warning",
       "Delivery em dois dias da semana economizaria R$ 350,00."}
    ]
  end

  defp processed_rows do
    [
      {"Farmácia Bem-Estar", "Saúde", "R$ 86,40"},
      {"Posto Shell", "Transporte", "R$ 250,00"},
      {"Streaming Plus", "Assinaturas", "R$ 19,90"}
    ]
  end

  defp chat_rows do
    [
      {"Jan", "R$ 412,00", "R$ 86,40", "R$ 498,40"},
      {"Fev", "R$ 412,00", "R$ 0,00", "R$ 412,00"},
      {"Mar", "R$ 412,00", "R$ 141,90", "R$ 553,90"}
    ]
  end

  defp open_finance_panels do
    [
      {"Open Finance · conexão", "Seus bancos, conectados pelo Open Finance",
       "O Grana usa o Open Finance Brasil, regulado pelo Banco Central, por meio da Pluggy. No Meu Pluggy, o caminho de uso pessoal: gratuito e com até 5 conexões."},
      {"Open Finance · dados", "Do banco direto para o seu servidor",
       "Você autoriza no app do próprio banco, só para leitura, e revoga quando quiser. A Pluggy entrega saldos, cartões e transações, e o Grana guarda tudo no seu banco local."},
      {"Open Finance · hoje", "O retrato de hoje, sem esperar o extrato",
       "Saldos, faturas abertas, limites e vencimentos no topo do painel. Os meses sem upload são preenchidos pelo Open Finance, e o upload sempre vence."}
    ]
  end

  defp of_connections do
    [
      {"Nubank", ~p"/images/nubank-logo.png", "Conta corrente · Mastercard · agora"},
      {"Bradesco", ~p"/images/bradesco-logo.png", "Conta corrente · Visa · agora"}
    ]
  end

  defp of_permissions, do: ["Contas e saldos", "Cartões e faturas", "Transações"]

  defp of_packets do
    [
      {"hero-banknotes", "saldos"},
      {"hero-credit-card", "faturas"},
      {"hero-arrows-right-left", "transações"}
    ]
  end

  defp open_finance_bullets do
    [
      {"hero-shield-check", "Consentimento seu, só de leitura, revogável no app do banco."},
      {"hero-arrow-path", "Leitura no máximo a cada hora, ou na hora com o webhook."},
      {"hero-calendar-days",
       "Preenche os meses sem upload; importou o arquivo, ele passa a valer."}
    ]
  end

  defp of_tiles do
    [
      {"lp-today-bank", "Em conta", "R$ 6.430,00", :neutro, "saldo somado de 2 conta(s)"},
      {"lp-today-card-used", "Faturas abertas", "R$ 2.184,40", :despesa, "somando 2 cartão(ões)"},
      {"lp-today-card-available", "Limite disponível", "R$ 9.815,60", :receita,
       "de R$ 12.000,00 de limite total"}
    ]
  end

  defp of_today_banks do
    [
      %{
        name: "Nubank",
        logo: ~p"/images/nubank-logo.png",
        account: "4821",
        balance: "R$ 4.250,00",
        card: "Mastercard",
        card_number: "7313",
        invoice: "R$ 1.180,40",
        usage: 42,
        dates: "fecha 03/04 · vence 10/04"
      },
      %{
        name: "Bradesco",
        logo: ~p"/images/bradesco-logo.png",
        account: "0937",
        balance: "R$ 2.180,00",
        card: "Visa",
        card_number: "5520",
        invoice: "R$ 1.004,00",
        usage: 17,
        dates: "fecha 20/03 · vence 28/03"
      }
    ]
  end

  # The year on the uploads calendar: Jul and Aug had no upload and came from Open Finance.
  defp of_months do
    kinds =
      List.duplicate("calendar-count-3", 6) ++
        List.duplicate("calendar-count-0", 2) ++
        List.duplicate("calendar-count-3", 2) ++ List.duplicate("calendar-count-future", 2)

    Enum.zip(~w(J F M A M J J A S O N D), kinds)
  end

  defp privacy_rows do
    [
      {"Salário Empresa Ltda", "Salário", "+R$ 8.450,00", "ui-money-receita"},
      {"Pix Ana Souza", "Transferências", "-R$ 320,00", "ui-money-despesa"},
      {"Mercado Pão de Açúcar", "Alimentação", "-R$ 486,20", "ui-money-despesa"},
      {"Aluguel Imobiliária Lar", "Moradia", "-R$ 1.500,00", "ui-money-despesa"}
    ]
  end

  # Self-hosted scene: tags around the company's server ({icon, text, x%, y%}), the links
  # that leave your server ({icon, name, note, y%}), the badges of the last step and the
  # data packets.
  defp cloud_tags do
    [
      {"hero-user-circle", "perfil de consumo", 56, 13},
      {"hero-share", "parceiros", 42, 87},
      {"hero-exclamation-triangle", "vazamentos", 70, 87}
    ]
  end

  defp self_hosted_links do
    [
      {"hero-sparkles", "Sua IA", "com a sua chave", 18},
      {"hero-building-library", "Pluggy", "opcional", 50},
      {"hero-envelope", "Seu email", "SMTP", 82}
    ]
  end

  defp server_badges do
    [
      {"hero-lock-closed", "AES-256-GCM", 40, 16},
      {"hero-envelope", "2FA por email", 70, 16},
      {"hero-archive-box", "backup em 1 arquivo", 56, 86}
    ]
  end

  # {icon, start}: the first three go to the company, the others come home.
  defp self_hosted_packets do
    [
      {"hero-document-text", 0.02},
      {"hero-banknotes", 0.07},
      {"hero-key", 0.12},
      {"hero-document-text", 0.42},
      {"hero-chat-bubble-left-right", 0.47},
      {"hero-tag", 0.52}
    ]
  end

  defp security_items do
    [
      {"hero-circle-stack", "Tudo em um arquivo SQLite",
       "Extratos, transações, análises e conversas ficam no seu banco local. Sem serviços externos para manter."},
      {"hero-key", "Credenciais cifradas",
       "Chaves e senhas usam AES-256-GCM, com uma chave gerada no seu servidor. O que está no .env tem prioridade."},
      {"hero-envelope", "2FA por email",
       "Com o SMTP configurado, todo login pede um código de 6 dígitos. Sem SMTP, só a senha."},
      {"hero-archive-box", "Backup e restauração em um arquivo",
       "Baixe o backup pela tela e restaure em qualquer instância. Quer recomeçar? Apague tudo e volte ao setup."}
    ]
  end

  defp install_methods do
    [
      {"script", "hero-command-line", "Script + systemd"},
      {"docker", "hero-cube", "Docker Compose"},
      {"fly", "hero-cloud", "Fly.io"}
    ]
  end

  @repo_raw "https://raw.githubusercontent.com/hjunior29/grana/main"

  defp install_commands("script"),
    do: ["curl -fsSL #{@repo_raw}/deploy/install.sh -o install.sh", "bash install.sh"]

  defp install_commands("docker"),
    do: ["curl -fsSLO #{@repo_raw}/docker-compose.yml", "docker compose up -d"]

  defp install_commands("fly"),
    do: [
      "curl -fsSLO #{@repo_raw}/deploy/fly.toml",
      "fly apps create meu-grana",
      "fly volumes create grana_data -a meu-grana -r gru -s 1 -y",
      "fly deploy -a meu-grana --ha=false"
    ]

  # What deploy/install.sh and compose print along the way.
  defp install_output("script") do
    [
      {:log, "Procurando a última versão"},
      {:log, "Conferindo o sha256"},
      {:log, "Instalando em /opt/grana"},
      {:log, "Iniciando o serviço"},
      {:text, "Grana instalado e rodando em http://localhost:4000"}
    ]
  end

  defp install_output("docker") do
    [
      {:ok, "Volume grana-data    Created"},
      {:ok, "Container grana      Started"}
    ]
  end

  defp install_output("fly") do
    [
      {:ok, "New app created: meu-grana"},
      {:ok, "Volume grana_data · 1GB · gru"},
      {:text, "Visit your newly deployed app at https://meu-grana.fly.dev/"}
    ]
  end

  defp fly_tips do
    [
      "Auto stop: sem acesso, a máquina para e só o volume é cobrado; o próximo acesso a liga em alguns segundos.",
      "Parada, nada roda em segundo plano: deixe a aba aberta numa importação longa.",
      "Snapshots diários do volume, além do backup pela tela."
    ]
  end

  defp log_commands("script"),
    do: [~s(sudo journalctl -u grana | grep -A3 "configuração inicial")]

  defp log_commands("docker"), do: ["docker compose logs grana"]
  defp log_commands("fly"), do: ["fly logs -a meu-grana --no-tail"]

  # The banner `Grana.Setup` logs on a boot without an owner.
  defp log_output(method) do
    [
      {:text, "GRANA — configuração inicial"},
      {:text, "Abra:   #{setup_url(method)}/setup"},
      {:code, "Código: ", setup_code()}
    ]
  end

  # The fly commands run on your own machine, not on a server.
  defp terminal_title("fly"), do: "seu-computador — bash"
  defp terminal_title(_method), do: "seu-servidor — bash"

  defp setup_host("fly"), do: "meu-grana.fly.dev"
  defp setup_host(_method), do: "seu-servidor:4000"

  defp setup_url("fly"), do: "https://meu-grana.fly.dev"
  defp setup_url(_method), do: "http://seu-servidor:4000"

  defp https_note("fly"), do: "O HTTPS já vem do Fly, no endereço do app ou num domínio seu."

  defp https_note(_method),
    do: "HTTPS fica com o seu proxy reverso: Caddy, Nginx ou Cloudflare Tunnel."

  defp setup_code, do: "K7QF-2M9X"

  defp onboarding_steps do
    [
      {"hero-paint-brush", "Aparência"},
      {"hero-envelope", "Email"},
      {"hero-sparkles", "IA"},
      {"hero-link", "Open Finance"}
    ]
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :commands, :list, required: true
  attr :output, :list, required: true

  defp terminal(assigns) do
    ~H"""
    <div id={@id} class="lp-term lp-rise" style="--d: 0.12">
      <div class="lp-term-bar">
        <span class="lp-term-dots" aria-hidden="true"><i></i><i></i><i></i></span>
        <span class="lp-term-title">{@title}</span>
        <button
          type="button"
          class="lp-copy"
          data-copy={Enum.join(@commands, "\n")}
          aria-label="Copiar os comandos"
        >
          <.icon name="hero-clipboard-document" class="size-4" />
          <span data-copy-label>Copiar</span>
        </button>
      </div>
      <div class="lp-term-body">
        <p :for={command <- @commands} class="lp-term-cmd">
          <span class="lp-term-prompt" aria-hidden="true">$</span>{command}
        </p>
        <p
          :for={{line, i} <- Enum.with_index(@output)}
          class="lp-term-out lp-t lp-t-rise"
          style={"--a: #{0.35 + i * 0.08}; --b: #{0.42 + i * 0.08}"}
        >
          <%= case line do %>
            <% {:log, text} -> %>
              <b class="lp-term-ok">==&gt;</b> {text}
            <% {:ok, text} -> %>
              <b class="lp-term-ok">✔</b> <span class="whitespace-pre-wrap">{text}</span>
            <% {:code, label, code} -> %>
              <span class="whitespace-pre">{label}</span><mark class="lp-term-code">{code}</mark>
            <% {:text, text} -> %>
              <span class="whitespace-pre-wrap">{text}</span>
          <% end %>
        </p>
      </div>
    </div>
    """
  end

  # The line (.lp-steps --f) reaches step n at p = 0.08 + 0.36 * (n - 1): the step lights up
  # on the way there.
  defp step_window(n) do
    b = Float.round(0.08 + 0.36 * (n - 1), 2)
    "--a: #{Float.round(b - 0.08, 2)}; --b: #{b}"
  end

  # Window of the i-th of n panels taking turns in a scene: the first is already on when
  # the stage pins, the last stays until the scene ends.
  defp panel_window(i, n) do
    a = if i == 0, do: -0.04, else: Float.round(i / n, 3)
    b = if i == n - 1, do: 1.5, else: Float.round((i + 1) / n, 3)
    "--a: #{a}; --b: #{b}"
  end

  defp search_request, do: "gastos com saúde nos últimos 3 meses"

  defp brl_float(value), do: Grana.Money.format(Decimal.from_float(value))

  # Despesas de Jan a Dez. A receita sai do saldo que a logo desenha: a pétala tem o
  # tamanho do saldo e a cor diz se sobrou (receita maior) ou faltou.
  @story_expenses [5200, 4900, 8600, 5100, 7400, 4700, 5600, 8300, 5000, 5400, 7600, 5900]
  @story_categories_total 6400

  defp story_months do
    GranaWeb.BrandComponents.geometry().months
    |> Enum.zip(@story_expenses)
    |> Enum.map(fn {%{size: size, positive: positive}, expense} ->
      balance = round((size - 10) * 1000)
      %{income: if(positive, do: expense + balance, else: expense - balance), expense: expense}
    end)
  end

  defp story_income, do: story_months() |> Enum.map(& &1.income) |> Enum.sum()

  defp story_balance,
    do: story_income() - (story_months() |> Enum.map(& &1.expense) |> Enum.sum())

  # As fatias da rosca são as mesmas do anel da logo.
  defp story_categories do
    categories = GranaWeb.BrandComponents.geometry().categories
    spans = categories |> Enum.map(& &1.span) |> Enum.sum()

    Enum.map(categories, fn cat ->
      share = cat.span / spans
      Map.merge(cat, %{share: share, amount: round(share * @story_categories_total)})
    end)
  end

  defp story_categories_total, do: @story_categories_total

  defp brl(reais) do
    int =
      reais
      |> Integer.to_string()
      |> String.reverse()
      |> String.to_charlist()
      |> Enum.chunk_every(3)
      |> Enum.join(".")
      |> String.reverse()

    "R$ #{int},00"
  end

  defp percent(ratio),
    do:
      :erlang.float_to_binary(ratio * 100, decimals: 1)
      |> String.replace(".", ",")
      |> Kernel.<>("%")
end
