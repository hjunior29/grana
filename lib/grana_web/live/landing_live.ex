defmodule GranaWeb.LandingLive do
  use GranaWeb, :live_view

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: %{}}}} = socket) do
    {:ok, push_navigate(socket, to: ~p"/dashboard")}
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Controle suas finanças")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="lp" class="min-h-screen" phx-hook=".ScrollMotion">
      <nav class="navbar bg-base-100/10 backdrop-blur-xl sticky top-0 z-50 border-b border-base-content/5 px-4 sm:px-6 lg:px-8">
        <div class="flex-1">
          <a id="landing-brand" href="/" class="flex items-center">
            <GranaWeb.BrandComponents.brand />
          </a>
        </div>
        <div class="flex-none">
          <div class="flex items-center gap-3">
            <Layouts.theme_toggle :if={!@current_scope} />
            <.link :if={!@current_scope} navigate={~p"/users/log-in"} class="btn btn-primary btn-sm">
              Entrar
            </.link>
            <.link :if={@current_scope} navigate={~p"/dashboard"} class="btn btn-primary btn-sm">
              Dashboard
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
            <.link id="hero-login" navigate={~p"/users/log-in"} class="btn btn-primary btn-lg">
              Entrar
            </.link>
            <a id="hero-install" href="#instalacao" class="btn btn-ghost btn-lg">
              Instalar no seu servidor
            </a>
          </div>
          <ul class="lp-facts lp-rise" style="--d: 0.4">
            <li :for={{icon, text} <- facts()}>
              <.icon name={icon} class="size-4 text-primary" /> {text}
            </li>
          </ul>
        </div>
      </section>

      <%!-- Como funciona: a linha enche conforme a rolagem --%>
      <section id="como-funciona" class="lp-section lp-alt" data-motion>
        <div class="lp-wrap text-center">
          <p class="lp-kicker lp-rise">Como funciona</p>
          <h2 class="lp-h2 lp-rise" style="--d: 0.05">Três passos, no seu ritmo</h2>
          <p class="lp-lead mx-auto max-w-xl lp-rise" style="--d: 0.1">
            Os seus uploads são o histórico oficial. O resto complementa.
          </p>

          <div class="lp-steps">
            <div class="lp-steps-line" aria-hidden="true">
              <div class="lp-steps-fill"></div>
              <div class="lp-steps-dot"></div>
            </div>
            <div
              :for={{{icon, title, text}, n} <- Enum.with_index(steps(), 1)}
              class="lp-step"
              style={"--a: #{0.15 + (n - 1) * 0.3}; --b: #{0.35 + (n - 1) * 0.3}"}
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
                    {name} <small class="ui-caption">{bank}</small>
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
                <span class="truncate lp-table-desc">{desc}</span>
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
                  "text-right font-medium",
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
                <strong class={tone}>{value}</strong>
                <span class="ui-caption">{help}</span>
              </div>
            </div>

            <div class="lp-dash-grid">
              <div class="lp-card lp-rise" style="--d: 0.3">
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
                      <span class="font-medium">{brl_float(cat.value)}</span>
                    </li>
                  </ul>
                </div>
              </div>

              <div class="lp-card lp-rise" style="--d: 0.35">
                <div class="flex items-center justify-between gap-3">
                  <h3 class="lp-card-title">Gastos diários</h3>
                  <span class="ui-view-toggle" aria-hidden="true">
                    <span class="ui-view-toggle-btn">
                      <.icon name="hero-chart-bar" class="size-4" />
                    </span>
                    <span class="ui-view-toggle-btn is-active">
                      <.icon name="hero-calendar-days" class="size-4" />
                    </span>
                  </span>
                </div>
                <div class="ui-heat lp-heat">
                  <div class="ui-heat-row ui-heat-head">
                    <div
                      :for={day <- ~w(Dom Seg Ter Qua Qui Sex Sáb)}
                      class="ui-heat-column ui-caption"
                    >
                      {day}
                    </div>
                  </div>
                  <div :for={{row, r} <- Enum.with_index(dash_calendar())} class="ui-heat-row">
                    <div
                      :for={{heat, c} <- Enum.with_index(row)}
                      class={[
                        "ui-heat-cell",
                        heat_kind(heat),
                        is_float(heat) and heat >= 0.55 and "is-strong"
                      ]}
                      style={"--i: #{r * 7 + c}; --heat: #{if is_float(heat), do: heat, else: 0}"}
                    >
                      <span :if={heat != :blank} class="ui-heat-caption">{r * 7 + c - 1}</span>
                    </div>
                  </div>
                </div>
                <p class="ui-caption mt-3">
                  Quanto mais vermelho, mais caro foi o dia. Fins de semana saltam aos olhos.
                </p>
              </div>
            </div>

            <div class="lp-card lp-rise" style="--d: 0.4">
              <h3 class="lp-card-title">Fluxo de caixa</h3>
              <div class="lp-wipe" style="--d: 0.45">
                <div
                  id="landing-flow-hook"
                  phx-hook="CashFlowChart"
                  data-flow={Jason.encode!(dash_flow())}
                >
                </div>
              </div>
            </div>

            <div class="lp-dash-grid lp-dash-grid-3">
              <div class="lp-card lp-rise" style="--d: 0.5">
                <h3 class="lp-card-title">Metas</h3>
                <ul class="lp-goals">
                  <li :for={{{label, pct, tone}, i} <- Enum.with_index(dash_goals())}>
                    <div class="flex justify-between ui-help">
                      <span>{label}</span><span>{pct}%</span>
                    </div>
                    <div class="lp-goal-track">
                      <i
                        class={["lp-goal-fill", tone]}
                        style={"--w: #{min(pct, 100)}%; --d: #{0.55 + i * 0.05}"}
                      >
                      </i>
                    </div>
                  </li>
                </ul>
              </div>
              <div class="lp-card lp-rise" style="--d: 0.55">
                <h3 class="lp-card-title">Despesas fixas</h3>
                <ul class="lp-list">
                  <li :for={{name, value} <- dash_fixed()}>
                    <span class="truncate">{name}</span><span class="ui-money-despesa font-medium">{value}</span>
                  </li>
                </ul>
                <p class="ui-caption mt-3">Detectadas sozinhas, mês após mês.</p>
              </div>
              <div class="lp-card lp-rise" style="--d: 0.6">
                <h3 class="lp-card-title">Parcelas</h3>
                <ul class="lp-list">
                  <li :for={{name, cur, total, value} <- dash_installments()}>
                    <span class="truncate">
                      {name} <small class="ui-caption">{cur}/{total}</small>
                    </span>
                    <span class="font-medium">{value}</span>
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
              style={"--a: #{i * 0.25}; --b: #{if i == 3, do: 1.5, else: (i + 1) * 0.25}"}
            >
              <p class="lp-kicker">{kicker}</p>
              <h2 class="lp-h2">{title}</h2>
              <p class="lp-lead">{text}</p>
            </div>
            <ol class="lp-dots" aria-hidden="true">
              <li
                :for={i <- 0..3}
                class="lp-dot"
                style={"--a: #{i * 0.25}; --b: #{if i == 3, do: 1.5, else: (i + 1) * 0.25}"}
              >
              </li>
            </ol>
          </div>

          <div class="lp-stage-mock lp-panels">
            <%!-- 1. Pesquisa avançada --%>
            <div class="lp-panel" style="--a: 0; --b: 0.25">
              <div class="lp-card">
                <div class="lp-search">
                  <.icon name="hero-sparkles" class="size-4 shrink-0 text-primary" />
                  <span class="lp-type lp-t" style="--a: 0.02; --b: 0.1">
                    gastos com saúde nos últimos 3 meses
                  </span>
                  <span class="lp-search-model">
                    <.icon name="hero-cpu-chip" class="size-3.5" /> gemini-flash
                  </span>
                </div>
                <p
                  class="ui-help mt-2 flex items-center gap-2 lp-t lp-t-fade"
                  style="--a: 0.1; --b: 0.14; --reverse: 1"
                >
                  <span class="loading loading-spinner loading-xs"></span> Montando a busca…
                </p>
                <div class="lp-t lp-t-rise" style="--a: 0.13; --b: 0.18">
                  <div class="ui-ai-query mt-3">
                    <code class="ui-query-code">
                      (unimed OR drogasil OR "plano de saúde") AND type:expense AND date>=today-3m
                    </code>
                    <span class="ui-ai-query-action">
                      <.icon name="hero-arrow-down-left" class="size-3.5" /> Usar
                    </span>
                  </div>
                  <p class="ui-help mt-2">
                    Inclui Unimed e Drogasil, que estavam fora da categoria Saúde.
                  </p>
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
                    <span class="ui-text-secondary">{text}</span>
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
                    <span class="truncate">{desc} <small class="ui-caption">{cat}</small></span>
                    <span class="ui-money-despesa font-medium">{value}</span>
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
                      Saúde levou <strong class="ui-money-despesa">R$ 1.264,30</strong>
                      nos últimos três meses,
                      incluindo a Unimed, que estava em Pagamentos.
                    </p>
                    <table class="lp-t lp-t-wipe" style="--a: 0.9; --b: 0.97">
                      <thead>
                        <tr>
                          <th>Mês</th>
                          <th>Unimed</th>
                          <th>Farmácias</th>
                          <th class="text-right">Total</th>
                        </tr>
                      </thead>
                      <tbody>
                        <tr :for={{m, a, b, t} <- chat_rows()}>
                          <td>{m}</td>
                          <td>{a}</td>
                          <td>{b}</td>
                          <td class="text-right ui-money-despesa">{t}</td>
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

      <%!-- Open Finance --%>
      <section id="open-finance" class="lp-section" data-motion>
        <div class="lp-wrap lp-two">
          <div>
            <p class="lp-kicker lp-rise">Opcional</p>
            <h2 class="lp-h2 lp-rise" style="--d: 0.05">O retrato de hoje, pelo Open Finance</h2>
            <p class="lp-lead lp-rise" style="--d: 0.1">
              Conecte os seus bancos pelo Meu Pluggy (uso pessoal, gratuito) e veja saldos, faturas
              abertas, limites e vencimentos sem esperar o extrato do mês.
            </p>
            <ul class="lp-bullets">
              <li
                :for={{{icon, text}, i} <- Enum.with_index(open_finance_bullets())}
                class="lp-rise"
                style={"--d: #{0.2 + i * 0.1}"}
              >
                <.icon name={icon} class="size-5 text-primary" /> <span>{text}</span>
              </li>
            </ul>
          </div>

          <div id="open-finance-preview" class="lp-card lp-rise" style="--d: 0.25">
            <div class="flex items-center justify-between mb-4">
              <h3 class="lp-card-title mb-0">Hoje</h3>
              <span class="ui-tag ui-tag-neutro">Open Finance</span>
            </div>
            <div class="grid grid-cols-2 gap-3 mb-4">
              <div class="lp-stat">
                <span class="ui-caption">Em conta</span>
                <strong>R$ 4.250,00</strong>
              </div>
              <div class="lp-stat">
                <span class="ui-caption">Faturas abertas</span>
                <strong class="ui-money-despesa">R$ 1.180,40</strong>
              </div>
            </div>
            <div class="lp-stat">
              <div class="flex items-center gap-2 mb-2">
                <img src={~p"/images/nubank-logo.png"} alt="" class="size-6 rounded-full" />
                <span class="font-medium ui-body">Nubank</span>
              </div>
              <div class="flex justify-between ui-help mb-1">
                <span>Conta corrente</span><span>R$ 4.250,00</span>
              </div>
              <div class="flex justify-between ui-help mb-2">
                <span>Cartão Mastercard</span><span>R$ 1.180,40</span>
              </div>
              <div class="lp-goal-track">
                <i class="lp-goal-fill bg-primary" style="--w: 42%; --d: 0.4"></i>
              </div>
              <p class="ui-caption mt-1">42% do limite usado · vence em 3 dias</p>
            </div>
          </div>
        </div>
      </section>

      <%!-- Do seu jeito: privacidade, estilos, metas --%>
      <section id="privacidade" class="lp-section lp-alt" data-motion>
        <div class="lp-wrap">
          <div class="text-center mb-12">
            <p class="lp-kicker lp-rise">Do seu jeito</p>
            <h2 class="lp-h2 lp-rise" style="--d: 0.05">Mostre só o que quiser</h2>
          </div>
          <div class="lp-dash-grid lp-dash-grid-3">
            <div class="lp-card lp-rise" style="--d: 0.15">
              <h3 class="lp-card-title">Modo privacidade</h3>
              <p class="ui-help mb-4">
                Esconda valores e nomes com um clique, para gravar a tela ou mostrar o app sem expor nada.
              </p>
              <ul class="lp-list lp-blur" style="--d: 0.45">
                <li>
                  <span>Salário <i class="lp-private lp-private-name">Empresa Ltda</i></span><span class="ui-money-receita font-medium lp-private">R$ 8.450,00</span>
                </li>
                <li>
                  <span>Aluguel</span><span class="ui-money-despesa font-medium lp-private">R$ 1.500,00</span>
                </li>
                <li>
                  <span>Pix para <i class="lp-private lp-private-name">Ana</i></span><span class="ui-money-despesa font-medium lp-private">R$ 320,00</span>
                </li>
              </ul>
            </div>
            <div class="lp-card lp-rise" style="--d: 0.25">
              <h3 class="lp-card-title">Sete estilos, claro e escuro</h3>
              <p class="ui-help mb-4">
                Do minimalista ao cyber, com tema claro, escuro ou o do sistema. A escolha acompanha você em todo aparelho.
              </p>
              <ul class="lp-swatches">
                <li
                  :for={{{name, colors}, i} <- Enum.with_index(visual_styles())}
                  class="lp-rise"
                  style={"--d: #{0.35 + i * 0.05}"}
                >
                  <span class="lp-swatch" style={"--c1: #{elem(colors, 0)}; --c2: #{elem(colors, 1)}"}>
                  </span>
                  <span class="ui-caption">{name}</span>
                </li>
              </ul>
            </div>
            <div class="lp-card lp-rise" style="--d: 0.35">
              <h3 class="lp-card-title">Metas e alertas</h3>
              <p class="ui-help mb-4">
                Limite de gastos, meta de receita ou de investimento e limite por categoria, acompanhados mês a mês.
              </p>
              <ul class="lp-goals">
                <li :for={{{label, pct, tone}, i} <- Enum.with_index(dash_goals())}>
                  <div class="flex justify-between ui-help">
                    <span>{label}</span><span>{pct}%</span>
                  </div>
                  <div class="lp-goal-track">
                    <i
                      class={["lp-goal-fill", tone]}
                      style={"--w: #{min(pct, 100)}%; --d: #{0.45 + i * 0.05}"}
                    >
                    </i>
                  </div>
                </li>
              </ul>
            </div>
          </div>
        </div>
      </section>

      <%!-- Segurança --%>
      <section id="seguranca" class="lp-section" data-motion>
        <div class="lp-wrap">
          <div class="text-center mb-12">
            <p class="lp-kicker lp-rise">Segurança</p>
            <h2 class="lp-h2 lp-rise" style="--d: 0.05">Seus dados, no seu servidor</h2>
            <p class="lp-lead mx-auto max-w-xl lp-rise" style="--d: 0.1">
              Nada de nuvem de terceiros: o Grana roda na sua máquina, com a sua chave de IA.
            </p>
          </div>
          <div class="lp-dash-grid">
            <div
              :for={{{icon, title, text}, i} <- Enum.with_index(security_items())}
              class="lp-card lp-feature lp-rise"
              style={"--d: #{0.15 + i * 0.08}"}
            >
              <span class="lp-feature-icon"><.icon name={icon} class="size-5" /></span>
              <div>
                <p class="font-semibold mb-1">{title}</p>
                <p class="ui-help">{text}</p>
              </div>
            </div>
          </div>
        </div>
      </section>

      <%!-- Instalação --%>
      <section id="instalacao" class="lp-section lp-alt" data-motion>
        <div class="lp-wrap lp-narrow">
          <div class="text-center mb-12">
            <p class="lp-kicker lp-rise">Em três passos</p>
            <h2 class="lp-h2 lp-rise" style="--d: 0.05">Instale no seu servidor</h2>
            <p class="lp-lead lp-rise" style="--d: 0.1">
              Release Elixir com systemd (recomendado), tarball ou Docker Compose.
            </p>
          </div>

          <ol class="lp-install">
            <li id="instalacao-passo-1" class="lp-rise" style="--d: 0.2">
              <span class="lp-install-number">1</span>
              <div class="min-w-0 flex-1">
                <h3 class="font-semibold mb-2">Instale</h3>
                <p class="ui-help mb-2">Em Debian 12+ ou Ubuntu 22.04+, com o script:</p>
                <pre class="lp-pre" phx-no-curly-interpolation>curl -fsSL https://raw.githubusercontent.com/hjunior29/grana/main/deploy/install.sh -o install.sh
    bash install.sh</pre>
                <p class="ui-help mb-2">Ou com Docker Compose:</p>
                <pre class="lp-pre" phx-no-curly-interpolation>curl -fsSLO https://raw.githubusercontent.com/hjunior29/grana/main/docker-compose.yml
    docker compose up -d</pre>
              </div>
            </li>
            <li id="instalacao-passo-2" class="lp-rise" style="--d: 0.3">
              <span class="lp-install-number">2</span>
              <div class="min-w-0 flex-1">
                <h3 class="font-semibold mb-2">Pegue o código do primeiro acesso</h3>
                <p class="ui-help mb-2">
                  Abra a URL do servidor (porta 4000). O código de uso único aparece no log:
                </p>
                <pre class="lp-pre" phx-no-curly-interpolation>sudo journalctl -u grana | grep -A3 "configuração inicial"
    docker compose logs grana</pre>
              </div>
            </li>
            <li id="instalacao-passo-3" class="lp-rise" style="--d: 0.4">
              <span class="lp-install-number">3</span>
              <div class="min-w-0 flex-1">
                <h3 class="font-semibold mb-2">Configure a sua instância</h3>
                <p class="ui-help">
                  O assistente cria a conta e, se quiser, configura email, IA e Open Finance, ou restaura
                  um backup. HTTPS fica por conta do seu proxy reverso (Caddy, Nginx, Cloudflare Tunnel).
                </p>
              </div>
            </li>
          </ol>

          <p class="text-center mt-10 lp-rise" style="--d: 0.5">
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

      <%!-- CTA --%>
      <section id="cta" class="lp-section" data-motion>
        <div class="lp-wrap lp-narrow text-center">
          <GranaWeb.BrandComponents.logo class="block size-20 mx-auto mb-6 lp-rise" />
          <h2 class="lp-h2 lp-rise" style="--d: 0.1">Pronto para organizar as suas finanças?</h2>
          <p class="lp-lead lp-rise" style="--d: 0.2">
            Entre na sua instância ou instale o Grana no seu próprio servidor.
          </p>
          <div class="lp-actions lp-rise" style="--d: 0.3">
            <.link id="cta-login" navigate={~p"/users/log-in"} class="btn btn-primary btn-lg">
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
            this.items = [...this.el.querySelectorAll("[data-motion], [data-scene]")].map(el => ({
              el, scene: el.hasAttribute("data-scene"), last: null
            }))
            if (matchMedia("(prefers-reduced-motion: reduce)").matches) {
              this.items.forEach(({el}) => el.style.setProperty("--p", "1"))
              return
            }
            this.onScroll = () => this.queue()
            addEventListener("scroll", this.onScroll, {passive: true})
            addEventListener("resize", this.onScroll)
            this.render()
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
      {"hero-bolt", "Regras suas: \"ifood\" vai para Alimentação, sempre."},
      {"hero-sparkles", "A IA só categoriza o que nenhuma regra pegou, com o seu provedor."},
      {"hero-academic-cap", "Corrigiu uma categoria? Vira regra para as próximas."}
    ]
  end

  defp category_rows do
    [
      {"02/03", "iFood *Restaurante", "Alimentação", "#F59E0B", "- R$ 67,40", :rule},
      {"03/03", "Uber *Trip", "Transporte", "#3B82F6", "- R$ 32,50", :rule},
      {"05/03", "Transferência recebida", "Salário", "#22C55E", "+ R$ 5.500,00", :rule},
      {"07/03", "Aluguel março", "Moradia", "#8B5CF6", "- R$ 1.500,00", :rule},
      {"08/03", "Sp Brilliant Labs", "Compras", "#F97316", "- R$ 89,70", :ai},
      {"12/03", "Unimed Goiânia", "Saúde", "#EF4444", "- R$ 412,00", :ai}
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

  # March 2026 starts on a Sunday: 31 days over five weeks. Weekends spend more.
  defp dash_calendar do
    heats = [
      0.4,
      0.15,
      0.1,
      1.0,
      0.2,
      0.12,
      0.55,
      0.6,
      0.08,
      0.14,
      0.0,
      0.18,
      0.35,
      0.7,
      0.45,
      0.1,
      0.0,
      0.22,
      0.16,
      0.3,
      0.8,
      0.5,
      0.12,
      0.09,
      0.2,
      0.0,
      0.4,
      0.65,
      0.3,
      0.1,
      0.25
    ]

    (heats ++ List.duplicate(:blank, 4))
    |> Enum.chunk_every(7)
  end

  defp heat_kind(:blank), do: "ui-heat-blank"
  defp heat_kind(heat) when heat > 0, do: "ui-heat-spend"
  defp heat_kind(_heat), do: "ui-heat-empty"

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
      {"Drogaria São Paulo", "Saúde", "R$ 86,40"},
      {"Posto Shell", "Transporte", "R$ 250,00"},
      {"Amazon Prime", "Assinaturas", "R$ 19,90"}
    ]
  end

  defp chat_rows do
    [
      {"Jan", "R$ 412,00", "R$ 86,40", "R$ 498,40"},
      {"Fev", "R$ 412,00", "R$ 0,00", "R$ 412,00"},
      {"Mar", "R$ 412,00", "R$ 141,90", "R$ 553,90"}
    ]
  end

  defp open_finance_bullets do
    [
      {"hero-banknotes",
       "Hoje: saldos, faturas abertas, limites e vencimentos no topo do painel."},
      {"hero-calendar-days", "Preenche os meses sem upload, marcados como Open Finance."},
      {"hero-shield-check",
       "O upload sempre vence: importou o arquivo do mês, ele passa a valer."}
    ]
  end

  defp visual_styles do
    [
      {"Padrão", {"#6366F1", "#1E293B"}},
      {"Signal", {"#22C55E", "#0F172A"}},
      {"Bossa", {"#F59E0B", "#FFF7ED"}},
      {"Papel", {"#78716C", "#FAFAF9"}},
      {"Caderneta", {"#2563EB", "#EFF6FF"}},
      {"Planetário", {"#A855F7", "#0B1020"}},
      {"Cyber", {"#06B6D4", "#111827"}}
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
