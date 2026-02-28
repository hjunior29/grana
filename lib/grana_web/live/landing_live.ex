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
    <div class="min-h-screen">
      <nav class="navbar bg-base-100/10 backdrop-blur-xl sticky top-0 z-50 border-b border-base-content/5 px-4 sm:px-6 lg:px-8">
        <div class="flex-1">
          <a href="/" class="flex items-center gap-2 text-xl font-bold tracking-tight">
            <img src={~p"/images/logo-32.png"} alt="" class="w-7 h-7" />
            <span style="font-family: 'Grand Hotel', cursive" class="text-2xl">Grana</span>
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
            alt="Grana"
            class="w-40 h-40 mx-auto mb-8 drop-shadow-xl"
          />
          <h1 class="text-5xl md:text-7xl font-bold tracking-tight leading-tight mb-6">
            Controle total das <br />
            <span
              style="font-family: 'Grand Hotel', cursive"
              class="text-primary text-6xl md:text-8xl font-normal"
            >
              suas finanças
            </span>
          </h1>
          <p class="text-lg md:text-xl opacity-60 max-w-2xl mx-auto mb-10">
            Importe extratos bancários e acompanhe seus investimentos em um só lugar.
            Categorização automática, gráficos intuitivos, carteira em tempo real e análises com IA.
          </p>
          <div class="flex flex-col sm:flex-row gap-4 justify-center">
            <.link navigate={~p"/users/log-in"} class="btn btn-primary btn-lg">
              Começar Agora
            </.link>
            <a href="#como-funciona" class="btn btn-ghost btn-lg">
              Ver como funciona
            </a>
          </div>
        </div>
      </section>

      <%!-- How it works --%>
      <section id="como-funciona" class="py-24 px-4 bg-base-200/50">
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

          <div class="relative">
            <div class="steps-line hidden md:block">
              <div class="steps-line-bg"></div>
              <div class="steps-line-fill"></div>
              <div class="steps-dot"></div>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
              <div class="flex flex-col items-center">
                <div class="step-circle step-circle-1 w-16 h-16 rounded-full bg-base-200 border border-primary/20 flex items-center justify-center mb-4 text-2xl font-bold text-primary relative z-10">
                  1
                </div>
                <h3 class="font-semibold mb-2">Faça Upload</h3>
                <p class="text-sm opacity-60">
                  Importe extratos bancários, faturas de cartão e negociações de investimentos. Suporte a CSV, XLSX e PDF.
                </p>
              </div>

              <div class="flex flex-col items-center">
                <div class="step-circle step-circle-2 w-16 h-16 rounded-full bg-base-200 border border-primary/20 flex items-center justify-center mb-4 text-2xl font-bold text-primary relative z-10">
                  2
                </div>
                <h3 class="font-semibold mb-2">Processamento Automático</h3>
                <p class="text-sm opacity-60">
                  A IA categoriza suas transações automaticamente com base em padrões e regras personalizadas.
                </p>
              </div>

              <div class="flex flex-col items-center">
                <div class="step-circle step-circle-3 w-16 h-16 rounded-full bg-base-200 border border-primary/20 flex items-center justify-center mb-4 text-2xl font-bold text-primary relative z-10">
                  3
                </div>
                <h3 class="font-semibold mb-2">Analise e Economize</h3>
                <p class="text-sm opacity-60">
                  Visualize gráficos, receba insights da IA e descubra onde economizar.
                </p>
              </div>
            </div>
          </div>

          <style>
            .steps-line {
              position: absolute;
              top: 2rem;
              left: 16.67%;
              right: 16.67%;
              height: 2px;
              transform: translateY(-50%);
              z-index: 0;
            }
            .steps-line-bg {
              position: absolute;
              inset: 0;
              background: oklch(58% 0.233 277.117 / 0.15);
              border-radius: 1px;
            }
            .steps-line-fill {
              position: absolute;
              top: 0;
              bottom: 0;
              left: 0;
              width: 0;
              background: linear-gradient(90deg, oklch(58% 0.233 277.117 / 0.3), oklch(58% 0.233 277.117 / 0.6));
              border-radius: 1px;
              animation: stepLineFill 5s ease-in-out infinite;
            }
            .steps-dot {
              position: absolute;
              top: 50%;
              left: 0;
              width: 10px;
              height: 10px;
              border-radius: 50%;
              background: oklch(58% 0.233 277.117);
              box-shadow: 0 0 14px 4px oklch(58% 0.233 277.117 / 0.5);
              transform: translate(-50%, -50%);
              animation: stepDotMove 5s ease-in-out infinite;
            }

            .step-circle-1 { animation: stepPulse1 5s ease-in-out infinite; }
            .step-circle-2 { animation: stepPulse2 5s ease-in-out infinite; }
            .step-circle-3 { animation: stepPulse3 5s ease-in-out infinite; }

            @keyframes stepLineFill {
              0%, 5%   { width: 0; opacity: 1; }
              35%      { width: 50%; }
              42%      { width: 50%; }
              72%      { width: 100%; }
              80%, 85% { width: 100%; opacity: 1; }
              95%      { width: 100%; opacity: 0; }
              100%     { width: 0; opacity: 0; }
            }
            @keyframes stepDotMove {
              0%, 5%   { left: 0%; opacity: 1; }
              35%      { left: 50%; }
              42%      { left: 50%; }
              72%      { left: 100%; }
              80%      { left: 100%; opacity: 1; }
              90%      { opacity: 0; }
              100%     { left: 0%; opacity: 0; }
            }
            @keyframes stepPulse1 {
              0%       { box-shadow: 0 0 0 0 oklch(58% 0.233 277.117 / 0); }
              5%       { box-shadow: 0 0 20px 4px oklch(58% 0.233 277.117 / 0.3); }
              30%      { box-shadow: 0 0 20px 4px oklch(58% 0.233 277.117 / 0.3); }
              40%      { box-shadow: 0 0 0 0 oklch(58% 0.233 277.117 / 0); }
              100%     { box-shadow: 0 0 0 0 oklch(58% 0.233 277.117 / 0); }
            }
            @keyframes stepPulse2 {
              0%, 30%  { box-shadow: 0 0 0 0 oklch(58% 0.233 277.117 / 0); }
              38%      { box-shadow: 0 0 20px 4px oklch(58% 0.233 277.117 / 0.3); }
              65%      { box-shadow: 0 0 20px 4px oklch(58% 0.233 277.117 / 0.3); }
              75%      { box-shadow: 0 0 0 0 oklch(58% 0.233 277.117 / 0); }
              100%     { box-shadow: 0 0 0 0 oklch(58% 0.233 277.117 / 0); }
            }
            @keyframes stepPulse3 {
              0%, 65%  { box-shadow: 0 0 0 0 oklch(58% 0.233 277.117 / 0); }
              72%      { box-shadow: 0 0 20px 4px oklch(58% 0.233 277.117 / 0.3); }
              85%      { box-shadow: 0 0 20px 4px oklch(58% 0.233 277.117 / 0.3); }
              95%      { box-shadow: 0 0 0 0 oklch(58% 0.233 277.117 / 0); }
              100%     { box-shadow: 0 0 0 0 oklch(58% 0.233 277.117 / 0); }
            }
          </style>
        </div>
      </section>

      <%!-- Step 1: Supported Banks / Upload --%>
      <section class="py-24 px-4">
        <style>
          .import-stage { position: relative; min-height: 220px; overflow: hidden; }

          .csv-raw, .csv-raw-2 { animation: csvRaw 12s ease-in-out infinite; }
          @keyframes csvRaw {
            0%, 3%   { opacity: 0; }
            8%       { opacity: 1; }
            40%      { opacity: 1; }
            48%, 100%{ opacity: 0; }
          }

          .csv-lines, .csv-lines-2 { animation: csvLines 12s ease-in-out infinite; }
          @keyframes csvLines {
            0%, 3%   { clip-path: inset(0 0 100% 0); }
            10%      { clip-path: inset(0 0 80% 0); }
            15%      { clip-path: inset(0 0 60% 0); }
            20%      { clip-path: inset(0 0 40% 0); }
            25%      { clip-path: inset(0 0 20% 0); }
            30%, 100%{ clip-path: inset(0 0 0% 0); }
          }

          .csv-structured, .csv-structured-2 {
            position: absolute; inset: 0;
            animation: csvStruct 12s ease-in-out infinite;
          }
          @keyframes csvStruct {
            0%, 42%  { opacity: 0; transform: translateY(8px); }
            50%      { opacity: 1; transform: translateY(0); }
            85%      { opacity: 1; transform: translateY(0); }
            93%, 100%{ opacity: 0; transform: translateY(-4px); }
          }

          .struct-row, .struct-row-2 { animation: structRow 12s ease-out infinite; }
          @keyframes structRow {
            0%, 44%  { opacity: 0; transform: translateX(-12px); }
            50%      { opacity: 1; transform: translateX(0); }
            85%      { opacity: 1; }
            93%, 100%{ opacity: 0; }
          }
          .struct-row:nth-child(2), .struct-row-2:nth-child(2) { animation-delay: 0.15s; }
          .struct-row:nth-child(3), .struct-row-2:nth-child(3) { animation-delay: 0.3s; }
          .struct-row:nth-child(4), .struct-row-2:nth-child(4) { animation-delay: 0.45s; }
        </style>

        <div class="max-w-6xl mx-auto">
          <div class="text-center mb-16">
            <div class="badge badge-primary badge-outline mb-4">Passo 1</div>
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
              Importe extratos bancários e negociações de investimentos em segundos
            </p>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-8">
            <%!-- Nubank --%>
            <div class="card bg-base-200/50 border border-base-content/5 p-6">
              <div class="flex items-center gap-3 mb-5">
                <img src={~p"/images/nubank-logo.png"} alt="Nubank" class="w-8 h-8 rounded" />
                <h3 class="font-semibold text-lg">Nubank</h3>
              </div>
              <div class="import-stage">
                <div class="mockup-code text-xs csv-raw">
                  <div class="csv-lines">
                    <pre data-prefix="1"><code>Data,Valor,Identificador,Descrição</code></pre>
                    <pre data-prefix="2"><code>02/01/2026,-45.90,abc123,Supermercado Extra</code></pre>
                    <pre data-prefix="3"><code>03/01/2026,-12.50,def456,Uber *Trip</code></pre>
                    <pre data-prefix="4" class="text-warning"><code>07/01/2026,3500.00,jkl012,Transferência recebida</code></pre>
                  </div>
                </div>
                <div class="csv-structured rounded-xl bg-base-300/80 p-3 space-y-1.5">
                  <div class="struct-row flex items-center justify-between p-2 rounded-lg bg-base-100/60">
                    <div class="flex items-center gap-3">
                      <div class="w-7 h-7 rounded-full bg-error/15 flex items-center justify-center">
                        <.icon name="hero-shopping-cart" class="size-4 text-error" />
                      </div>
                      <div>
                        <p class="text-sm font-medium">Supermercado Extra</p>
                        <p class="text-xs opacity-50">02/01/2026</p>
                      </div>
                    </div>
                    <span class="text-sm font-mono font-semibold text-error">-R$ 45,90</span>
                  </div>
                  <div class="struct-row flex items-center justify-between p-2 rounded-lg bg-base-100/60">
                    <div class="flex items-center gap-3">
                      <div class="w-7 h-7 rounded-full bg-error/15 flex items-center justify-center">
                        <.icon name="hero-truck" class="size-4 text-error" />
                      </div>
                      <div>
                        <p class="text-sm font-medium">Uber *Trip</p>
                        <p class="text-xs opacity-50">03/01/2026</p>
                      </div>
                    </div>
                    <span class="text-sm font-mono font-semibold text-error">-R$ 12,50</span>
                  </div>
                  <div class="struct-row flex items-center justify-between p-2 rounded-lg bg-base-100/60">
                    <div class="flex items-center gap-3">
                      <div class="w-7 h-7 rounded-full bg-success/15 flex items-center justify-center">
                        <.icon name="hero-arrow-down-tray" class="size-4 text-success" />
                      </div>
                      <div>
                        <p class="text-sm font-medium">Transferência recebida</p>
                        <p class="text-xs opacity-50">07/01/2026</p>
                      </div>
                    </div>
                    <span class="text-sm font-mono font-semibold text-success">+R$ 3.500,00</span>
                  </div>
                </div>
              </div>
            </div>

            <%!-- Bradesco --%>
            <div class="card bg-base-200/50 border border-base-content/5 p-6">
              <div class="flex items-center gap-3 mb-5">
                <img src={~p"/images/bradesco-logo.png"} alt="Bradesco" class="w-8 h-8 rounded" />
                <h3 class="font-semibold text-lg">Bradesco</h3>
              </div>
              <div class="import-stage">
                <div class="mockup-code text-xs csv-raw-2">
                  <div class="csv-lines-2">
                    <pre data-prefix="1"><code>Data;Histórico;Docto.;Crédito;Débito;Saldo</code></pre>
                    <pre data-prefix="2"><code>06/02/2026;PIX TRANSF;98765;;150,00;4.850,00</code></pre>
                    <pre data-prefix="3"><code>07/02/2026;PGTO BOLETO;54321;;890,00;3.960,00</code></pre>
                    <pre data-prefix="4" class="text-warning"><code>10/02/2026;REND B3;33445;245,80;;4.138,30</code></pre>
                  </div>
                </div>
                <div class="csv-structured-2 rounded-xl bg-base-300/80 p-3 space-y-1.5">
                  <div class="struct-row-2 flex items-center justify-between p-2 rounded-lg bg-base-100/60">
                    <div class="flex items-center gap-3">
                      <div class="w-7 h-7 rounded-full bg-error/15 flex items-center justify-center">
                        <.icon name="hero-arrow-up-tray" class="size-4 text-error" />
                      </div>
                      <div>
                        <p class="text-sm font-medium">PIX Transferência</p>
                        <p class="text-xs opacity-50">06/02/2026</p>
                      </div>
                    </div>
                    <span class="text-sm font-mono font-semibold text-error">-R$ 150,00</span>
                  </div>
                  <div class="struct-row-2 flex items-center justify-between p-2 rounded-lg bg-base-100/60">
                    <div class="flex items-center gap-3">
                      <div class="w-7 h-7 rounded-full bg-error/15 flex items-center justify-center">
                        <.icon name="hero-document-text" class="size-4 text-error" />
                      </div>
                      <div>
                        <p class="text-sm font-medium">Pagamento Boleto</p>
                        <p class="text-xs opacity-50">07/02/2026</p>
                      </div>
                    </div>
                    <span class="text-sm font-mono font-semibold text-error">-R$ 890,00</span>
                  </div>
                  <div class="struct-row-2 flex items-center justify-between p-2 rounded-lg bg-base-100/60">
                    <div class="flex items-center gap-3">
                      <div class="w-7 h-7 rounded-full bg-success/15 flex items-center justify-center">
                        <.icon name="hero-chart-bar" class="size-4 text-success" />
                      </div>
                      <div>
                        <p class="text-sm font-medium">Rendimento B3</p>
                        <p class="text-xs opacity-50">10/02/2026</p>
                      </div>
                    </div>
                    <span class="text-sm font-mono font-semibold text-success">+R$ 245,80</span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <%!-- Investment Providers --%>
          <div class="mt-16 text-center mb-10">
            <div class="badge badge-success badge-outline mb-4">Investimentos</div>
            <h3 class="text-2xl md:text-3xl font-bold tracking-tight mb-3">
              Acompanhe sua carteira
            </h3>
            <p class="text-base opacity-60 max-w-xl mx-auto">
              Importe negociações da B3 e extratos da GCB para ter uma visão completa do seu patrimônio
            </p>
          </div>

          <style>
            .inv-raw, .inv-raw-2 { animation: invRaw 12s ease-in-out infinite; }
            @keyframes invRaw {
              0%, 3%   { opacity: 0; }
              8%       { opacity: 1; }
              40%      { opacity: 1; }
              48%, 100%{ opacity: 0; }
            }

            .inv-lines, .inv-lines-2 { animation: invLines 12s ease-in-out infinite; }
            @keyframes invLines {
              0%, 3%   { clip-path: inset(0 0 100% 0); }
              10%      { clip-path: inset(0 0 80% 0); }
              15%      { clip-path: inset(0 0 60% 0); }
              20%      { clip-path: inset(0 0 40% 0); }
              25%      { clip-path: inset(0 0 20% 0); }
              30%, 100%{ clip-path: inset(0 0 0% 0); }
            }

            .inv-structured, .inv-structured-2 {
              position: absolute; inset: 0;
              animation: invStruct 12s ease-in-out infinite;
            }
            @keyframes invStruct {
              0%, 42%  { opacity: 0; transform: translateY(8px); }
              50%      { opacity: 1; transform: translateY(0); }
              85%      { opacity: 1; transform: translateY(0); }
              93%, 100%{ opacity: 0; transform: translateY(-4px); }
            }

            .inv-row, .inv-row-2 { animation: invRow 12s ease-out infinite; }
            @keyframes invRow {
              0%, 44%  { opacity: 0; transform: translateX(-12px); }
              50%      { opacity: 1; transform: translateX(0); }
              85%      { opacity: 1; }
              93%, 100%{ opacity: 0; }
            }
            .inv-row:nth-child(2), .inv-row-2:nth-child(2) { animation-delay: 0.15s; }
            .inv-row:nth-child(3), .inv-row-2:nth-child(3) { animation-delay: 0.3s; }
          </style>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-8">
            <%!-- B3 --%>
            <div class="card bg-base-200/50 border border-base-content/5 p-6">
              <div class="flex items-center gap-3 mb-5">
                <img src={~p"/images/b3-logo.png"} alt="B3" class="w-8 h-8 rounded" />
                <div>
                  <h3 class="font-semibold text-lg">B3</h3>
                  <p class="text-xs opacity-50">Negociações da bolsa brasileira</p>
                </div>
              </div>
              <div class="import-stage">
                <div class="mockup-code text-xs inv-raw">
                  <div class="inv-lines">
                    <pre data-prefix="1"><code>Data;Tipo;Ativo;Qtd;Preço;Total</code></pre>
                    <pre data-prefix="2"><code>02/01/2026;Compra;PETR4;100;38,42;3842,00</code></pre>
                    <pre data-prefix="3"><code>05/01/2026;Compra;MXRF11;250;9,90;2475,00</code></pre>
                    <pre data-prefix="4" class="text-warning"><code>10/01/2026;Compra;VALE3;50;58,30;2915,00</code></pre>
                  </div>
                </div>
                <div class="inv-structured rounded-xl bg-base-300/80 p-3 space-y-1.5">
                  <div
                    :for={
                      {ticker, type, qty, val} <- [
                        {"PETR4", "Ação", "100 un.", "R$ 3.842,00"},
                        {"MXRF11", "FII", "250 un.", "R$ 2.475,00"},
                        {"VALE3", "Ação", "50 un.", "R$ 2.915,00"}
                      ]
                    }
                    class="inv-row flex items-center justify-between p-2 rounded-lg bg-base-100/60"
                  >
                    <div class="flex items-center gap-3">
                      <div class="w-7 h-7 rounded-full bg-success/15 flex items-center justify-center">
                        <.icon name="hero-chart-bar" class="size-4 text-success" />
                      </div>
                      <div>
                        <p class="text-sm font-medium font-mono">{ticker}</p>
                        <p class="text-xs opacity-50">{type}</p>
                      </div>
                    </div>
                    <div class="text-right">
                      <span class="text-sm font-mono font-semibold text-info">{val}</span>
                      <p class="text-xs opacity-50">{qty}</p>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <%!-- GCB --%>
            <div class="card bg-base-200/50 border border-base-content/5 p-6">
              <div class="flex items-center gap-3 mb-5">
                <div class="w-8 h-8 rounded overflow-hidden bg-base-300">
                  <img src={~p"/images/gcb-logo.png"} alt="GCB" />
                </div>
                <div>
                  <h3 class="font-semibold text-lg">GCB</h3>
                  <p class="text-xs opacity-50">Notas fiscais, debêntures e precatórios</p>
                </div>
              </div>
              <div class="import-stage">
                <div class="mockup-code text-xs inv-raw-2">
                  <div class="inv-lines-2">
                    <pre data-prefix="1"><code>Tipo;Nome;Emissão;Vencimento;Valor</code></pre>
                    <pre data-prefix="2"><code>CRI;CSHG 2028;15/03/2024;15/03/2028;15000,00</code></pre>
                    <pre data-prefix="3"><code>DEB;VALE 2027;01/06/2023;01/06/2027;10250,00</code></pre>
                    <pre data-prefix="4" class="text-warning"><code>PREC;SP 2026;10/01/2025;10/01/2026;8400,00</code></pre>
                  </div>
                </div>
                <div class="inv-structured-2 rounded-xl bg-base-300/80 p-3 space-y-1.5">
                  <div
                    :for={
                      {name, type, val} <- [
                        {"CRI CSHG 2028", "Renda Fixa", "R$ 15.000,00"},
                        {"DEB VALE 2027", "Debênture", "R$ 10.250,00"},
                        {"PREC SP 2026", "Precatório", "R$ 8.400,00"}
                      ]
                    }
                    class="inv-row-2 flex items-center justify-between p-2 rounded-lg bg-base-100/60"
                  >
                    <div class="flex items-center gap-3">
                      <div class="w-7 h-7 rounded-full bg-info/15 flex items-center justify-center">
                        <.icon name="hero-document-text" class="size-4 text-info" />
                      </div>
                      <div>
                        <p class="text-sm font-medium">{name}</p>
                        <p class="text-xs opacity-50">{type}</p>
                      </div>
                    </div>
                    <span class="text-sm font-mono font-semibold text-info">{val}</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <%!-- Step 2: Transaction Categorization --%>
      <section class="py-24 px-4 bg-base-200/50">
        <div class="max-w-6xl mx-auto">
          <div class="text-center mb-16">
            <div class="badge badge-primary badge-outline mb-4">Passo 2</div>
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
            <div class="card bg-base-200 p-4 mb-4">
              <div class="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-3">
                <div class="col-span-2">
                  <input
                    type="search"
                    placeholder="Buscar transações..."
                    class="input input-bordered input-sm w-full"
                    disabled
                  />
                </div>
                <div>
                  <select class="select select-bordered select-sm w-full" disabled>
                    <option>Todos os bancos</option>
                  </select>
                </div>
                <div>
                  <select class="select select-bordered select-sm w-full" disabled>
                    <option>Extrato e Fatura</option>
                  </select>
                </div>
                <div>
                  <select class="select select-bordered select-sm w-full" disabled>
                    <option>Todas transações</option>
                  </select>
                </div>
                <div>
                  <select class="select select-bordered select-sm w-full" disabled>
                    <option>Todas categorias</option>
                  </select>
                </div>
              </div>
              <div class="grid grid-cols-2 md:grid-cols-5 gap-3 mt-3">
                <div>
                  <label class="text-xs opacity-50 mb-1 block">Data início</label>
                  <input type="date" class="input input-bordered input-sm w-full" disabled />
                </div>
                <div>
                  <label class="text-xs opacity-50 mb-1 block">Data fim</label>
                  <input type="date" class="input input-bordered input-sm w-full" disabled />
                </div>
                <div>
                  <label class="text-xs opacity-50 mb-1 block">Valor mínimo</label>
                  <input
                    type="number"
                    placeholder="0,00"
                    class="input input-bordered input-sm w-full"
                    disabled
                  />
                </div>
                <div>
                  <label class="text-xs opacity-50 mb-1 block">Valor máximo</label>
                  <input
                    type="number"
                    placeholder="0,00"
                    class="input input-bordered input-sm w-full"
                    disabled
                  />
                </div>
                <div>
                  <label class="text-xs opacity-50 mb-1 block">Internas</label>
                  <select class="select select-bordered select-sm w-full" disabled>
                    <option>Todas</option>
                  </select>
                </div>
              </div>
              <div class="flex justify-end mt-3">
                <span class="btn btn-error btn-xs cursor-default">Limpar filtros</span>
              </div>
            </div>

            <div class="flex items-center gap-4 text-sm mb-3 flex-wrap">
              <span class="opacity-60">8 transações</span>
              <span class="text-error font-medium">Despesas: R$ 1.991,30</span>
              <span class="text-success font-medium">Receitas: R$ 5.745,80</span>
              <span class="text-info font-medium">Investimentos: R$ 245,80</span>
              <a class="btn btn-sm gap-1 ml-auto cursor-default">
                <.icon name="hero-arrow-down-tray" class="size-4" /> Exportar CSV
              </a>
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
                  <tr
                    :for={
                      {date, desc, bank, cat, color, val, type} <- [
                        {"02/01/2026", "Supermercado Extra", "nubank", "Alimentação", "#F59E0B",
                         "- R$ 245,80", "debit"},
                        {"03/01/2026", "Uber *Trip São Paulo", "nubank", "Transporte", "#3B82F6",
                         "- R$ 32,50", "debit"},
                        {"05/01/2026", "Transferência recebida", "nubank", "Salário", "#22C55E",
                         "+ R$ 5.500,00", "credit"},
                        {"06/01/2026", "Netflix.com", "bradesco", "Assinaturas", "#A855F7",
                         "- R$ 55,90", "debit"},
                        {"07/01/2026", "Aluguel Fevereiro", "bradesco", "Moradia", "#8B5CF6",
                         "- R$ 1.500,00", "debit"},
                        {"08/01/2026", "Drogasil - Medicamentos", "nubank", "Saúde", "#EF4444",
                         "- R$ 89,70", "debit"},
                        {"10/01/2026", "Rendimento RDB", "bradesco", "Investimentos", "#10B981",
                         "+ R$ 245,80", "credit"},
                        {"12/01/2026", "iFood *Restaurante", "nubank", "Alimentação", "#F59E0B",
                         "- R$ 67,40", "debit"}
                      ]
                    }
                    class="hover"
                  >
                    <td class="text-sm whitespace-nowrap">{date}</td>
                    <td class="text-sm max-w-xs">
                      <span class="truncate block">{desc}</span>
                    </td>
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
                      "text-right text-sm font-medium whitespace-nowrap",
                      (type == "credit" && "text-success") || "text-error"
                    ]}>
                      {val}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div class="flex justify-center gap-2 mt-4">
              <button class="btn btn-sm btn-primary">1</button>
              <button class="btn btn-sm btn-ghost">2</button>
              <button class="btn btn-sm btn-ghost">3</button>
              <span class="px-2 opacity-40 self-center">...</span>
              <button class="btn btn-sm btn-ghost">12</button>
              <button class="btn btn-sm btn-ghost">
                <.icon name="hero-chevron-right" class="size-4" />
              </button>
            </div>
          </div>
        </div>
      </section>

      <%!-- Dashboard Preview --%>
      <section id="dashboard-preview" class="py-24 px-4">
        <div class="text-center mb-16">
          <div class="badge badge-primary badge-outline mb-4">Passo 3</div>
        </div>
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
            <div class="mb-4 sm:mb-6 space-y-2">
              <div class="flex flex-wrap items-center gap-1 sm:gap-2">
                <div class="flex gap-1">
                  <span class="btn btn-xs sm:btn-sm btn-ghost cursor-default">2025</span>
                  <span class="btn btn-xs sm:btn-sm btn-primary cursor-default">2026</span>
                </div>
                <div class="divider divider-horizontal mx-0 hidden sm:flex"></div>
                <div class="flex flex-wrap gap-1">
                  <span class="btn btn-xs btn-ghost cursor-default">Ano</span>
                  <span class="btn btn-xs btn-primary cursor-default">Jan</span>
                  <span class="btn btn-xs btn-ghost cursor-default">Fev</span>
                  <span class="btn btn-xs btn-ghost cursor-default">Mar</span>
                  <span class="btn btn-xs btn-ghost cursor-default">Abr</span>
                  <span class="btn btn-xs btn-ghost cursor-default">Mai</span>
                  <span class="btn btn-xs btn-ghost cursor-default">Jun</span>
                  <span class="btn btn-xs btn-ghost cursor-default">Jul</span>
                  <span class="btn btn-xs btn-ghost cursor-default">Ago</span>
                </div>
              </div>
              <div class="flex flex-wrap items-center gap-2 sm:gap-3">
                <div class="flex items-center gap-1">
                  <span class="text-xs opacity-40 mr-0.5 sm:mr-1">Banco</span>
                  <span class="btn btn-xs btn-primary cursor-default">Todos</span>
                  <span class="btn btn-xs btn-ghost gap-1 cursor-default">
                    <img src={~p"/images/nubank-logo.png"} alt="" class="w-4 h-4 rounded-full" />
                    <span class="hidden sm:inline cursor-default">Nubank</span>
                  </span>
                  <span class="btn btn-xs btn-ghost gap-1 cursor-default">
                    <img src={~p"/images/bradesco-logo.png"} alt="" class="w-4 h-4 rounded-full" />
                    <span class="hidden sm:inline cursor-default">Bradesco</span>
                  </span>
                </div>
                <div class="flex items-center gap-1">
                  <span class="text-xs opacity-40 mr-0.5 sm:mr-1">Fonte</span>
                  <span class="btn btn-xs btn-primary cursor-default">Todas</span>
                  <span class="btn btn-xs btn-ghost gap-1 cursor-default">
                    <.icon name="hero-banknotes" class="size-3" />
                    <span class="hidden sm:inline cursor-default">Extrato</span>
                  </span>
                  <span class="btn btn-xs btn-ghost gap-1 cursor-default">
                    <.icon name="hero-credit-card" class="size-3" />
                    <span class="hidden sm:inline cursor-default">Fatura</span>
                  </span>
                </div>
                <div class="flex items-center gap-1">
                  <span class="text-xs opacity-40 mr-0.5 sm:mr-1">Tipo</span>
                  <span class="btn btn-xs btn-primary cursor-default">Todas</span>
                  <span class="btn btn-xs btn-ghost cursor-default">Despesas</span>
                  <span class="btn btn-xs btn-ghost cursor-default">Receitas</span>
                  <span class="btn btn-xs btn-ghost cursor-default">
                    <span class="hidden sm:inline">Investimentos</span>
                    <span class="sm:hidden">Invest.</span>
                  </span>
                </div>
              </div>
            </div>

            <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-2 sm:gap-4 mb-4 sm:mb-8">
              <div class="stat bg-base-200 rounded-xl p-3 sm:p-4">
                <div class="stat-title text-[10px] sm:text-xs">Receitas</div>
                <div class="stat-value text-success text-sm sm:text-lg">R$ 8.450,00</div>
                <div class="stat-desc text-[10px] sm:text-xs">12 transações</div>
              </div>
              <div class="stat bg-base-200 rounded-xl p-3 sm:p-4">
                <div class="stat-title text-[10px] sm:text-xs">Despesas</div>
                <div class="stat-value text-error text-sm sm:text-lg">R$ 5.797,40</div>
                <div class="stat-desc text-[10px] sm:text-xs">47 transações</div>
              </div>
              <div class="stat bg-base-200 rounded-xl p-3 sm:p-4">
                <div class="stat-title text-[10px] sm:text-xs">Investimentos</div>
                <div class="stat-value text-info text-sm sm:text-lg">R$ 1.200,00</div>
                <div class="stat-desc text-[10px] sm:text-xs">3 transações</div>
              </div>
              <div class="stat bg-base-200 rounded-xl p-3 sm:p-4">
                <div class="stat-title text-[10px] sm:text-xs">Saldo Livre</div>
                <div class="stat-value text-success text-sm sm:text-lg">R$ 2.652,60</div>
                <div class="stat-desc text-[10px] sm:text-xs">Categorizado</div>
              </div>
              <div class="stat bg-base-200 rounded-xl p-3 sm:p-4">
                <div class="stat-title text-[10px] sm:text-xs">Média Diária</div>
                <div class="stat-value text-sm sm:text-lg">R$ 193,24</div>
                <div class="stat-desc text-[10px] sm:text-xs">em despesas</div>
              </div>
              <div class="stat bg-base-200 rounded-xl p-3 sm:p-4">
                <div class="stat-title text-[10px] sm:text-xs">Transações</div>
                <div class="stat-value text-sm sm:text-lg">62</div>
                <div class="stat-desc text-[10px] sm:text-xs">Alimentação lidera</div>
              </div>
            </div>

            <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 sm:gap-6 mb-4 sm:mb-6">
              <div class="card bg-base-200 p-4 sm:p-6">
                <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">
                  Despesas por Categoria
                </h3>
                <div
                  id="landing-cat-hook"
                  phx-hook="CategoryChart"
                  data-categories={
                    Jason.encode!([
                      %{name: "Alimentação", value: 1847.0, color: "#F59E0B"},
                      %{name: "Moradia", value: 1500.0, color: "#8B5CF6"},
                      %{name: "Transporte", value: 650.0, color: "#3B82F6"},
                      %{name: "Compras", value: 520.0, color: "#F97316"},
                      %{name: "Lazer", value: 480.0, color: "#EC4899"},
                      %{name: "Saúde", value: 320.0, color: "#EF4444"},
                      %{name: "Pagamentos", value: 290.0, color: "#64748B"},
                      %{name: "Assinaturas", value: 190.0, color: "#A855F7"}
                    ])
                  }
                >
                  <div class="space-y-3">
                    <div
                      :for={
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
                      }
                      class="flex items-center gap-3 rounded-lg px-2 py-1 -mx-2"
                    >
                      <div
                        class="w-3 h-3 rounded-full shrink-0"
                        style={"background-color: #{color}"}
                      />
                      <span class="flex-1 text-sm truncate">{name}</span>
                      <span class="text-sm font-medium">{value}</span>
                      <span class="text-xs opacity-50">{pct}</span>
                    </div>
                  </div>
                </div>
              </div>

              <div class="card bg-base-200 p-4 sm:p-6">
                <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">Gastos Diários</h3>
                <div
                  id="landing-daily-hook"
                  phx-hook="DailyChart"
                  data-daily={
                    Jason.encode!([
                      %{date: "02/01", value: 145.90},
                      %{date: "03/01", value: 47.50},
                      %{date: "05/01", value: 320.00},
                      %{date: "07/01", value: 587.32},
                      %{date: "08/01", value: 68.90},
                      %{date: "10/01", value: 487.32},
                      %{date: "12/01", value: 175.00},
                      %{date: "14/01", value: 89.90},
                      %{date: "15/01", value: 245.00},
                      %{date: "17/01", value: 382.50},
                      %{date: "19/01", value: 120.00},
                      %{date: "22/01", value: 289.90},
                      %{date: "25/01", value: 198.00},
                      %{date: "27/01", value: 410.80},
                      %{date: "30/01", value: 259.36}
                    ])
                  }
                >
                  <div class="space-y-1">
                    <div
                      :for={
                        {day, pct, val} <- [
                          {"02/01", 25, "R$ 145,90"},
                          {"03/01", 8, "R$ 47,50"},
                          {"05/01", 55, "R$ 320,00"},
                          {"07/01", 100, "R$ 587,32"},
                          {"08/01", 12, "R$ 68,90"},
                          {"10/01", 83, "R$ 487,32"},
                          {"12/01", 30, "R$ 175,00"},
                          {"14/01", 15, "R$ 89,90"},
                          {"15/01", 42, "R$ 245,00"},
                          {"17/01", 65, "R$ 382,50"},
                          {"19/01", 20, "R$ 120,00"},
                          {"22/01", 50, "R$ 289,90"},
                          {"25/01", 35, "R$ 198,00"},
                          {"27/01", 70, "R$ 410,80"},
                          {"30/01", 45, "R$ 259,36"}
                        ]
                      }
                      class="flex items-center gap-2"
                    >
                      <span class="text-xs w-10 opacity-60">{day}</span>
                      <div class="flex-1 bg-base-300 rounded-full h-4 overflow-hidden">
                        <div
                          class="bg-primary h-full rounded-full"
                          style={"width: #{pct}%"}
                        />
                      </div>
                      <span class="text-xs font-medium w-20 text-right">{val}</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 sm:gap-6 mb-4 sm:mb-6">
              <div class="card bg-base-200 p-4 sm:p-6">
                <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">Top Despesas</h3>
                <div class="space-y-1">
                  <div
                    :for={
                      {date, desc, cat, color, val} <- [
                        {"03/01", "Aluguel Janeiro", "Moradia", "#8B5CF6", "R$ 1.500,00"},
                        {"10/01", "Supermercado Extra", "Alimentação", "#F59E0B", "R$ 487,32"},
                        {"17/01", "Farmácia São João", "Saúde", "#EF4444", "R$ 320,00"},
                        {"22/01", "Shopping - Roupas", "Compras", "#F97316", "R$ 289,90"},
                        {"07/01", "Posto Shell", "Transporte", "#3B82F6", "R$ 250,00"},
                        {"15/01", "Conta de Luz", "Moradia", "#8B5CF6", "R$ 245,00"},
                        {"19/01", "iFood", "Alimentação", "#F59E0B", "R$ 198,00"}
                      ]
                    }
                    class="flex items-center gap-3 rounded-lg px-2 py-1 -mx-2"
                  >
                    <span class="text-xs opacity-50 w-12">{date}</span>
                    <span class="flex-1 text-sm truncate">{desc}</span>
                    <span
                      class="badge badge-xs shrink-0"
                      style={"background-color: #{color}20; color: #{color}; border-color: #{color}40"}
                    >
                      {cat}
                    </span>
                    <span class="text-sm font-medium text-error whitespace-nowrap">{val}</span>
                  </div>
                </div>
              </div>

              <div class="card bg-base-200 p-4 sm:p-6">
                <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">Top Receitas</h3>
                <div class="space-y-1">
                  <div
                    :for={
                      {date, desc, cat, color, val} <- [
                        {"05/01", "Salário", "Salário", "#22C55E", "R$ 5.800,00"},
                        {"15/01", "Freelance Design", "Salário", "#22C55E", "R$ 1.500,00"},
                        {"20/01", "Rendimento CDB", "Investimentos", "#3B82F6", "R$ 850,00"},
                        {"25/01", "Cashback Nubank", "Outros", "#64748B", "R$ 187,50"},
                        {"28/01", "Venda Marketplace", "Outros", "#64748B", "R$ 112,50"}
                      ]
                    }
                    class="flex items-center gap-3 rounded-lg px-2 py-1 -mx-2"
                  >
                    <span class="text-xs opacity-50 w-12">{date}</span>
                    <span class="flex-1 text-sm truncate">{desc}</span>
                    <span
                      class="badge badge-xs shrink-0"
                      style={"background-color: #{color}20; color: #{color}; border-color: #{color}40"}
                    >
                      {cat}
                    </span>
                    <span class="text-sm font-medium text-success whitespace-nowrap">{val}</span>
                  </div>
                </div>
              </div>
            </div>

            <div class="card bg-base-200 p-4 sm:p-6 mb-4 sm:mb-6">
              <div class="flex flex-wrap items-center justify-between gap-2 mb-4">
                <h3 class="font-semibold text-sm sm:text-base">Receitas vs Despesas</h3>
                <div class="flex items-center gap-3 text-sm">
                  <span class="font-semibold text-success">+R$ 2.652,60</span>
                  <span class="badge badge-sm badge-success">economizou 31,4%</span>
                </div>
              </div>
              <div
                id="landing-ie-hook"
                phx-hook="IncomeExpensesChart"
                data-monthly={
                  Jason.encode!([
                    %{label: "Jan", income: 8450.0, expenses: 5797.0}
                  ])
                }
              >
              </div>
            </div>

            <div class="card bg-base-200 p-4 sm:p-6 mb-4 sm:mb-6">
              <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">Parcelas Ativas</h3>
              <div class="overflow-x-auto">
                <table class="table">
                  <thead>
                    <tr>
                      <th>Descrição</th>
                      <th>Categoria</th>
                      <th>Valor/mês</th>
                      <th>Progresso</th>
                      <th class="text-right">Restante</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr
                      :for={
                        {desc, cat, color, val, curr, total, remaining} <- [
                          {"iPhone 15 Pro Max", "Compras", "#F97316", "R$ 549,90", 4, 12,
                           "R$ 4.399,20"},
                          {"TV Samsung 65 pol.", "Compras", "#F97316", "R$ 283,25", 7, 10,
                           "R$ 849,75"},
                          {"Curso Data Science", "Educação", "#3B82F6", "R$ 199,90", 2, 6,
                           "R$ 799,60"},
                          {"Sofá Retrátil", "Moradia", "#8B5CF6", "R$ 416,50", 1, 8, "R$ 2.915,50"},
                          {"PlayStation 5", "Lazer", "#EC4899", "R$ 449,90", 3, 5, "R$ 899,80"}
                        ]
                      }
                      class="hover"
                    >
                      <td class="text-sm max-w-xs truncate">{desc}</td>
                      <td>
                        <span
                          class="badge badge-sm"
                          style={"background-color: #{color}20; color: #{color}; border-color: #{color}40"}
                        >
                          {cat}
                        </span>
                      </td>
                      <td class="text-sm font-medium">{val}</td>
                      <td>
                        <div class="flex items-center gap-2">
                          <progress
                            class="progress progress-warning w-20"
                            value={curr}
                            max={total}
                          />
                          <span class="text-xs opacity-60">{curr}/{total}</span>
                        </div>
                      </td>
                      <td class="text-right text-sm font-medium text-warning">{remaining}</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>

            <div class="card bg-base-200 p-4 sm:p-6 mb-4 sm:mb-6">
              <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">Projeção de Parcelas</h3>
              <div
                id="landing-projection-hook"
                phx-hook="ProjectionChart"
                data-projections={
                  Jason.encode!([
                    %{label: "Fev", value: 1899.45},
                    %{label: "Mar", value: 1899.45},
                    %{label: "Abr", value: 1449.55},
                    %{label: "Mai", value: 1166.30},
                    %{label: "Jun", value: 966.40},
                    %{label: "Jul", value: 966.40},
                    %{label: "Ago", value: 966.40},
                    %{label: "Set", value: 549.90}
                  ])
                }
              >
              </div>
            </div>

            <div class="grid grid-cols-3 gap-2 sm:gap-4">
              <div class="stat bg-base-200 rounded-xl p-3 sm:p-4">
                <div class="stat-title text-[10px] sm:text-xs">Parcelas Ativas</div>
                <div class="stat-value text-warning text-sm sm:text-lg">5</div>
                <div class="stat-desc text-[10px] sm:text-xs">parceladas</div>
              </div>
              <div class="stat bg-base-200 rounded-xl p-3 sm:p-4">
                <div class="stat-title text-[10px] sm:text-xs">Mensal Parcelas</div>
                <div class="stat-value text-warning text-sm sm:text-lg">R$ 1.899,45</div>
                <div class="stat-desc text-[10px] sm:text-xs">por mês</div>
              </div>
              <div class="stat bg-base-200 rounded-xl p-3 sm:p-4">
                <div class="stat-title text-[10px] sm:text-xs">Total Restante</div>
                <div class="stat-value text-warning text-sm sm:text-lg">R$ 9.863,85</div>
                <div class="stat-desc text-[10px] sm:text-xs">futuras</div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <%!-- Investments Portfolio Preview --%>
      <section class="py-24 px-4 bg-base-200/50">
        <div class="max-w-6xl mx-auto">
          <div class="text-center mb-16">
            <p
              style="font-family: 'Grand Hotel', cursive"
              class="text-primary text-5xl mb-3"
            >
              Patrimônio
            </p>
            <h2 class="text-3xl md:text-4xl font-bold tracking-tight mb-4">
              Seus investimentos em tempo real
            </h2>
            <p class="text-lg opacity-60 max-w-xl mx-auto">
              Acompanhe ações, FIIs, renda fixa e mais com cotações ao vivo e análise de rentabilidade
            </p>
          </div>

          <div class="rounded-2xl border border-base-content/10 bg-base-200/30 p-4 md:p-8 shadow-xl">
            <%!-- Filters (mirrors real investments page) --%>
            <div class="mb-4 sm:mb-6 space-y-2">
              <div class="flex flex-wrap items-center gap-1 sm:gap-2">
                <div class="flex gap-1">
                  <span class="btn btn-xs sm:btn-sm btn-ghost cursor-default">Todos</span>
                  <span class="btn btn-xs sm:btn-sm btn-ghost cursor-default">2025</span>
                  <span class="btn btn-xs sm:btn-sm btn-primary cursor-default">2026</span>
                </div>
                <div class="divider divider-horizontal mx-0 hidden sm:flex"></div>
                <div class="flex flex-wrap gap-1">
                  <span class="btn btn-xs btn-ghost cursor-default">Ano</span>
                  <span class="btn btn-xs btn-primary cursor-default">Jan</span>
                  <span class="btn btn-xs btn-ghost cursor-default">Fev</span>
                </div>
              </div>
              <div class="flex flex-wrap items-center gap-2 sm:gap-3">
                <div class="flex items-center gap-1">
                  <span class="text-xs opacity-40 mr-0.5 sm:mr-1">Instituição</span>
                  <span class="btn btn-xs btn-primary cursor-default">Todas</span>
                  <span class="btn btn-xs btn-ghost gap-1 cursor-default">
                    <img src={~p"/images/b3-logo.png"} alt="" class="w-4 h-4 rounded-full" />
                    <span class="hidden sm:inline">B3</span>
                  </span>
                  <span class="btn btn-xs btn-ghost gap-1 cursor-default">
                    <div class="w-4 h-4 rounded-full overflow-hidden bg-base-300 shrink-0">
                      <img src={~p"/images/gcb-logo.png"} alt="" />
                    </div>
                    <span class="hidden sm:inline">GCB</span>
                  </span>
                </div>
                <div class="flex flex-wrap items-center gap-1">
                  <span class="text-xs opacity-40 mr-0.5 sm:mr-1">Tipo</span>
                  <span class="btn btn-xs btn-primary cursor-default">Todos</span>
                  <span class="btn btn-xs btn-ghost cursor-default">Ações</span>
                  <span class="btn btn-xs btn-ghost cursor-default">FIIs</span>
                  <span class="btn btn-xs btn-ghost cursor-default">RF</span>
                </div>
              </div>
            </div>

            <%!-- Investment Stats (6 cards like real dashboard) --%>
            <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-2 sm:gap-4 mb-4 sm:mb-8">
              <div class="stat bg-base-200 rounded-xl p-3 sm:p-4 hover:scale-[1.03] hover:shadow-lg transition-all cursor-pointer">
                <div class="stat-title text-[10px] sm:text-xs">
                  Patrimônio <span class="ml-1 text-success">●</span>
                </div>
                <div class="stat-value text-info text-sm sm:text-lg">R$ 47.832,00</div>
                <div class="stat-desc text-[10px] sm:text-xs">preço ao vivo</div>
              </div>
              <div class="stat bg-base-200 rounded-xl p-3 sm:p-4 hover:scale-[1.03] hover:shadow-lg transition-all cursor-pointer">
                <div class="stat-title text-[10px] sm:text-xs">Investido</div>
                <div class="stat-value text-sm sm:text-lg opacity-70">R$ 42.500,00</div>
                <div class="stat-desc text-[10px] sm:text-xs">custo-base</div>
              </div>
              <div class="stat bg-base-200 rounded-xl p-3 sm:p-4 hover:scale-[1.03] hover:shadow-lg transition-all cursor-pointer">
                <div class="stat-title text-[10px] sm:text-xs">Ativos</div>
                <div class="stat-value text-sm sm:text-lg opacity-70">8</div>
                <div class="stat-desc text-[10px] sm:text-xs">3 Ação, 2 FII, 3 RF</div>
              </div>
              <div class="stat bg-base-200 rounded-xl p-3 sm:p-4 hover:scale-[1.03] hover:shadow-lg transition-all cursor-pointer">
                <div class="stat-title text-[10px] sm:text-xs">Dividendos</div>
                <div class="stat-value text-success text-sm sm:text-lg">R$ 780,40</div>
                <div class="stat-desc text-[10px] sm:text-xs">renda passiva</div>
              </div>
              <div class="stat bg-base-200 rounded-xl p-3 sm:p-4 hover:scale-[1.03] hover:shadow-lg transition-all cursor-pointer">
                <div class="stat-title text-[10px] sm:text-xs">Lucro em Vendas</div>
                <div class="stat-value text-success text-sm sm:text-lg">R$ 467,20</div>
                <div class="stat-desc text-[10px] sm:text-xs">ganho realizado</div>
              </div>
              <div class="stat bg-base-200 rounded-xl p-3 sm:p-4 hover:scale-[1.03] hover:shadow-lg transition-all cursor-pointer">
                <div class="stat-title text-[10px] sm:text-xs">Rentabilidade</div>
                <div class="stat-value text-success text-sm sm:text-lg">+ R$ 5.332,00</div>
                <div class="stat-desc text-[10px] sm:text-xs font-medium text-success">+12,55%</div>
              </div>
            </div>

            <%!-- Charts Row 1: Carteira por Ativo (with donut) + Dividendos e Ganhos --%>
            <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 sm:gap-6 mb-4 sm:mb-6">
              <div class="card bg-base-200 p-4 sm:p-6">
                <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">Carteira por Ativo</h3>
                <div
                  id="landing-inv-asset-hook"
                  phx-hook="CategoryChart"
                  data-categories={
                    Jason.encode!([
                      %{name: "PETR4", value: 12450.0, color: "#3B82F6"},
                      %{name: "VALE3", value: 9830.0, color: "#60A5FA"},
                      %{name: "MXRF11", value: 8250.0, color: "#22C55E"},
                      %{name: "ITUB4", value: 6120.0, color: "#818CF8"},
                      %{name: "XPLG11", value: 5890.0, color: "#34D399"},
                      %{name: "CDB 120%", value: 5292.0, color: "#F59E0B"}
                    ])
                  }
                >
                  <div class="space-y-2">
                    <div
                      :for={
                        {ticker, type, val, pct, color} <- [
                          {"PETR4", "Ação", "R$ 12.450", "26.0%", "#3B82F6"},
                          {"VALE3", "Ação", "R$ 9.830", "20.6%", "#60A5FA"},
                          {"MXRF11", "FII", "R$ 8.250", "17.2%", "#22C55E"},
                          {"ITUB4", "Ação", "R$ 6.120", "12.8%", "#818CF8"},
                          {"XPLG11", "FII", "R$ 5.890", "12.3%", "#34D399"},
                          {"CDB 120%", "RF", "R$ 5.292", "11.1%", "#F59E0B"}
                        ]
                      }
                      class="flex items-center gap-3 rounded-lg px-2 py-1 -mx-2 hover:bg-base-300 transition-all cursor-pointer"
                    >
                      <div class="w-3 h-3 rounded-full shrink-0" style={"background-color: #{color}"} />
                      <div class="flex-1 min-w-0">
                        <span class="text-sm font-medium">{ticker}</span>
                        <span class="text-xs opacity-40 ml-1">{type}</span>
                      </div>
                      <span class="text-sm font-medium">{val}</span>
                      <span class="text-xs opacity-50 w-12 text-right">{pct}</span>
                    </div>
                  </div>
                </div>
              </div>

              <div class="card bg-base-200 p-4 sm:p-6">
                <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">Dividendos e Ganhos</h3>
                <div
                  id="landing-inv-proventos-hook"
                  phx-hook="DailyChart"
                  data-daily={
                    Jason.encode!([
                      %{date: "03/01", value: 39.20},
                      %{date: "06/01", value: 19.00},
                      %{date: "10/01", value: 490.04},
                      %{date: "12/01", value: 22.80},
                      %{date: "13/01", value: 23.76},
                      %{date: "19/01", value: 8.97},
                      %{date: "20/01", value: 43.65}
                    ])
                  }
                  data-bar-fill="fill-success"
                >
                  <div class="space-y-1">
                    <div
                      :for={
                        {date, pct, val} <- [
                          {"06/01", 4, "R$ 19,00"},
                          {"10/01", 100, "R$ 490,04"},
                          {"12/01", 5, "R$ 22,80"},
                          {"13/01", 5, "R$ 23,76"},
                          {"19/01", 2, "R$ 8,97"},
                          {"20/01", 9, "R$ 43,65"}
                        ]
                      }
                      class="flex items-center gap-2"
                    >
                      <span class="text-xs w-10 opacity-60">{date}</span>
                      <div class="flex-1 bg-base-300 rounded-full h-4 overflow-hidden">
                        <div class="bg-success h-full rounded-full" style={"width: #{pct}%"} />
                      </div>
                      <span class="text-xs font-medium w-20 text-right text-success">{val}</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <%!-- Holdings Table (faithful to real page) --%>
            <div class="card bg-base-200 p-4 sm:p-6 mb-4 sm:mb-6">
              <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">Carteira de Ativos</h3>
              <div class="overflow-x-auto">
                <table class="table">
                  <thead>
                    <tr>
                      <th>Ativo</th>
                      <th>Tipo</th>
                      <th class="text-right">Qtd</th>
                      <th class="text-right hidden sm:table-cell">Preço Atual</th>
                      <th class="text-right">Valor Atual</th>
                      <th class="text-right hidden sm:table-cell">Investido</th>
                      <th class="text-right">Rent. %</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr
                      :for={
                        {ticker, name, type, badge_class, qty, price, val, invested, rent, rent_class, logo} <- [
                          {"PETR4", "Petrobras PN", "Ação", "badge-info", "100", "R$ 124,50", "R$ 12.450", "R$ 10.540", "+18,2%", "text-success", ~p"/images/b3-logo.png"},
                          {"VALE3", "Vale ON", "Ação", "badge-info", "50", "R$ 196,60", "R$ 9.830", "R$ 9.040", "+8,7%", "text-success", ~p"/images/b3-logo.png"},
                          {"MXRF11", "Maxi Renda FII", "FII", "badge-success", "250", "R$ 33,00", "R$ 8.250", "R$ 7.835", "+5,3%", "text-success", ~p"/images/b3-logo.png"},
                          {"ITUB4", "Itaú Unibanco PN", "Ação", "badge-info", "80", "R$ 76,50", "R$ 6.120", "R$ 5.460", "+12,1%", "text-success", ~p"/images/b3-logo.png"},
                          {"XPLG11", "XP Log FII", "FII", "badge-success", "60", "R$ 98,17", "R$ 5.890", "R$ 6.035", "-2,4%", "text-error", ~p"/images/b3-logo.png"},
                          {"CDB 120%", "CDB 120% CDI", "RF", "badge-warning", "1", "R$ 5.292", "R$ 5.292", "R$ 4.610", "+14,8%", "text-success", ~p"/images/gcb-logo.png"}
                        ]
                      }
                      class="hover cursor-pointer"
                    >
                      <td>
                        <div class="flex items-center gap-2">
                          <div :if={logo} class="w-6 h-6 rounded-full overflow-hidden bg-base-300 shrink-0">
                            <img src={logo} alt="" />
                          </div>
                          <div class="flex flex-col">
                            <span class="font-medium text-sm">{ticker}</span>
                            <span class="text-xs opacity-50 truncate max-w-[120px] sm:max-w-xs">{name}</span>
                          </div>
                        </div>
                      </td>
                      <td><span class={"badge badge-sm whitespace-nowrap #{badge_class}"}>{type}</span></td>
                      <td class="text-right text-sm">{qty}</td>
                      <td class="text-right text-sm hidden sm:table-cell">{price}</td>
                      <td class="text-right text-sm font-medium text-info whitespace-nowrap">{val}</td>
                      <td class="text-right text-sm opacity-60 hidden sm:table-cell">{invested}</td>
                      <td class={"text-right text-sm font-medium #{rent_class}"}>{rent}</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>

            <%!-- Proventos por Ativo --%>
            <div class="card bg-base-200 p-4 sm:p-6">
              <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">
                Ganhos por Ativo
              </h3>
              <div class="overflow-x-auto">
                <table class="table">
                  <thead>
                    <tr>
                      <th>Ativo</th>
                      <th>Tipo</th>
                      <th class="text-right">Total</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr
                      :for={
                        {ticker, name, type, badge_class, total, logo} <- [
                          {"MXRF11", "Maxi Renda FII", "FII", "badge-success", "R$ 312,50", ~p"/images/b3-logo.png"},
                          {"XPLG11", "XP Log FII", "FII", "badge-success", "R$ 198,40", ~p"/images/b3-logo.png"},
                          {"PETR4", "Petrobras PN", "Ação", "badge-info", "R$ 156,30", ~p"/images/b3-logo.png"},
                          {"ITUB4", "Itaú Unibanco PN", "Ação", "badge-info", "R$ 113,20", ~p"/images/b3-logo.png"},
                          {"CDB 120%", "CDB 120% CDI", "RF", "badge-warning", "R$ 467,20", ~p"/images/gcb-logo.png"}
                        ]
                      }
                      class="hover cursor-pointer"
                    >
                      <td>
                        <div class="flex items-center gap-2">
                          <div :if={logo} class="w-6 h-6 rounded-full overflow-hidden bg-base-300 shrink-0">
                            <img src={logo} alt="" />
                          </div>
                          <div class="flex flex-col">
                            <span class="font-medium text-sm">{ticker}</span>
                            <span :if={ticker != name} class="text-xs opacity-50 truncate max-w-xs">{name}</span>
                          </div>
                        </div>
                      </td>
                      <td><span class={"badge badge-sm whitespace-nowrap #{badge_class}"}>{type}</span></td>
                      <td class="text-right text-sm font-medium text-success whitespace-nowrap">{total}</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>
      </section>

      <%!-- Step 3: AI Analysis --%>
      <section class="py-24 px-4">
        <style>
          .ai-demo { display: grid; overflow: hidden; }
          .ai-demo-phase {
            grid-area: 1 / 1;
            transition: opacity 500ms ease, transform 500ms ease;
          }
          .ai-skeleton {
            background: linear-gradient(90deg, rgba(255,255,255,0.03) 25%, rgba(255,255,255,0.08) 50%, rgba(255,255,255,0.03) 75%);
            background-size: 200% 100%;
            animation: skeletonPulse 1.5s ease-in-out infinite;
            border-radius: 0.5rem;
          }
          @keyframes skeletonPulse {
            0%   { background-position: 200% 0; }
            100% { background-position: -200% 0; }
          }
        </style>

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
                Analise suas despesas e investimentos com inteligência artificial.
                Receba insights personalizados, alertas e dicas para otimizar suas finanças.
              </p>
              <div class="space-y-4">
                <div class="flex items-start gap-3">
                  <div class="w-8 h-8 rounded-lg bg-warning/10 flex items-center justify-center shrink-0 mt-0.5">
                    <.icon name="hero-light-bulb" class="size-4 text-warning" />
                  </div>
                  <div>
                    <p class="font-medium text-sm">Insights automáticos</p>
                    <p class="text-sm opacity-60">Identifica padrões de gasto e tendências de investimento</p>
                  </div>
                </div>
                <div class="flex items-start gap-3">
                  <div class="w-8 h-8 rounded-lg bg-error/10 flex items-center justify-center shrink-0 mt-0.5">
                    <.icon name="hero-exclamation-triangle" class="size-4 text-error" />
                  </div>
                  <div>
                    <p class="font-medium text-sm">Alertas inteligentes</p>
                    <p class="text-sm opacity-60">Avisa sobre gastos fora do normal e riscos na carteira</p>
                  </div>
                </div>
                <div class="flex items-start gap-3">
                  <div class="w-8 h-8 rounded-lg bg-success/10 flex items-center justify-center shrink-0 mt-0.5">
                    <.icon name="hero-check-circle" class="size-4 text-success" />
                  </div>
                  <div>
                    <p class="font-medium text-sm">Despesas e investimentos</p>
                    <p class="text-sm opacity-60">Analisa gastos, proventos, rentabilidade e diversificação</p>
                  </div>
                </div>
              </div>
            </div>

            <div>
              <div role="tablist" class="tabs tabs-border mb-6">
                <button role="tab" class="tab tab-active cursor-default">
                  <.icon name="hero-banknotes" class="size-4 mr-1" /> Bancário
                </button>
                <button role="tab" class="tab cursor-default">
                  <.icon name="hero-chart-bar" class="size-4 mr-1" /> Investimentos
                </button>
              </div>

              <div id="landing-ai-demo" phx-hook="LandingAIDemo" class="ai-demo">
              <%!-- Phase 1: Input --%>
              <div data-ai-input class="ai-demo-phase">
                <div class="mb-3 space-y-2">
                  <div class="flex flex-wrap items-center gap-1 sm:gap-2">
                    <div class="flex gap-1">
                      <span class="btn btn-xs sm:btn-sm btn-primary cursor-default">2026</span>
                    </div>
                    <div class="divider divider-horizontal mx-0 hidden sm:flex"></div>
                    <div class="flex flex-wrap gap-1">
                      <span class="btn btn-xs btn-ghost cursor-default">Ano</span>
                      <span class="btn btn-xs btn-primary cursor-default">Jan</span>
                      <span class="btn btn-xs btn-ghost cursor-default">Fev</span>
                    </div>
                  </div>
                  <div class="flex flex-wrap items-center gap-2 sm:gap-3">
                    <div class="flex items-center gap-1">
                      <span class="text-xs opacity-40 mr-0.5 sm:mr-1">Banco</span>
                      <span class="btn btn-xs btn-ghost cursor-default">Todos</span>
                      <span class="btn btn-xs btn-primary gap-1 cursor-default">
                        <img src={~p"/images/nubank-logo.png"} alt="" class="w-4 h-4 rounded-full" />
                        <span class="hidden sm:inline">Nubank</span>
                      </span>
                    </div>
                    <div class="flex items-center gap-1">
                      <span class="text-xs opacity-40 mr-0.5 sm:mr-1">Fonte</span>
                      <span class="btn btn-xs btn-primary cursor-default">Todas</span>
                      <span class="btn btn-xs btn-ghost gap-1 cursor-default">
                        <.icon name="hero-banknotes" class="size-3" />
                        <span class="hidden sm:inline">Extrato</span>
                      </span>
                    </div>
                    <div class="flex items-center gap-1">
                      <span class="text-xs opacity-40 mr-0.5 sm:mr-1">Tipo</span>
                      <span class="btn btn-xs btn-primary cursor-default">Todas</span>
                      <span class="btn btn-xs btn-ghost cursor-default">Despesas</span>
                    </div>
                  </div>
                </div>

                <div class="card bg-base-200 p-4 sm:p-6">
                  <div class="mb-3 sm:mb-4">
                    <label class="block text-sm font-semibold leading-6 mb-1">
                      Pergunte algo sobre suas finanças (opcional)
                    </label>
                    <textarea
                      data-ai-textarea
                      placeholder="Ex: Onde posso economizar? Como está minha carteira de investimentos?"
                      class="textarea textarea-bordered w-full text-sm"
                      rows="2"
                      readonly
                      tabindex="-1"
                    ></textarea>
                  </div>
                  <button
                    data-ai-button
                    class="btn btn-primary btn-sm sm:btn-md gap-2 transition-transform cursor-default"
                    tabindex="-1"
                  >
                    <.icon name="hero-sparkles" class="size-4" /> Analisar com IA
                  </button>
                </div>
              </div>

              <%!-- Phase 2: Loading --%>
              <div
                data-ai-loading
                class="ai-demo-phase"
                style="opacity: 0; transform: translateY(6px)"
              >
                <div class="card bg-base-200 p-4 sm:p-6 mb-4">
                  <div class="flex items-center gap-3">
                    <span class="loading loading-spinner loading-sm text-primary"></span>
                    <span class="text-sm opacity-60">Analisando seus dados com IA...</span>
                  </div>
                </div>

                <div class="card bg-gradient-to-br from-primary/5 to-secondary/5 border border-primary/10 p-5 sm:p-6 shadow-xl">
                  <div class="flex items-center gap-3 mb-5">
                    <div class="ai-skeleton w-10 h-10 rounded-lg shrink-0"></div>
                    <div class="flex-1 space-y-2">
                      <div class="ai-skeleton h-4 w-3/5"></div>
                      <div class="ai-skeleton h-3 w-2/5"></div>
                    </div>
                  </div>

                  <div class="space-y-3">
                    <div class="ai-skeleton h-4 w-full"></div>
                    <div class="ai-skeleton h-4 w-4/5"></div>
                    <div class="ai-skeleton h-3 w-3/5 mt-4"></div>
                    <div class="ai-skeleton h-3 w-4/5"></div>
                    <div class="ai-skeleton h-3 w-3/4"></div>
                    <div class="ai-skeleton h-3 w-2/3"></div>
                    <div class="ai-skeleton h-3 w-4/5"></div>
                    <div class="ai-skeleton h-10 w-full mt-4"></div>
                    <div class="ai-skeleton h-16 w-full mt-4 rounded-lg"></div>
                  </div>
                </div>
              </div>

              <%!-- Phase 3: Result --%>
              <div data-ai-result class="ai-demo-phase" style="opacity: 0; transform: translateY(6px)">
                <div class="card bg-gradient-to-br from-primary/5 to-secondary/5 border border-primary/10 p-5 sm:p-6 shadow-xl">
                  <div class="flex items-start justify-between gap-3 mb-3">
                    <div class="flex-1 min-w-0">
                      <div class="flex items-center gap-3 mb-1">
                        <span class="inline-flex items-center justify-center w-10 h-10 rounded-lg text-sm font-bold border shrink-0 text-success bg-success/15 border-success/30">
                          7.8
                        </span>
                        <div class="min-w-0">
                          <h4 class="font-semibold text-sm">Saúde financeira de Janeiro</h4>
                          <div class="flex flex-wrap items-center gap-1 mt-0.5">
                            <span class="text-xs opacity-40">19/02/2026 às 14:32</span>
                            <span class="badge badge-xs badge-ghost">Janeiro</span>
                            <span class="badge badge-xs badge-ghost">Nubank</span>
                          </div>
                        </div>
                      </div>
                      <p class="text-xs opacity-30 italic mt-1 truncate ml-11 sm:ml-13">
                        "Onde posso economizar nesse mês?"
                      </p>
                    </div>
                  </div>

                  <p class="text-sm opacity-80 mb-4">
                    Seus gastos com alimentação representam 32% do total — acima da média recomendada de 25%.
                    Sua carteira de investimentos rendeu +12,5% no período, com boa diversificação entre ações e FIIs.
                  </p>

                  <div class="space-y-2 mb-4">
                    <div class="flex items-start gap-2 text-sm">
                      <.icon name="hero-check-circle" class="size-4 text-success shrink-0 mt-0.5" />
                      <span class="opacity-80">
                        Receita mensal consistente com média de R$ 8.450 — bom controle de renda
                      </span>
                    </div>
                    <div class="flex items-start gap-2 text-sm">
                      <.icon name="hero-check-circle" class="size-4 text-success shrink-0 mt-0.5" />
                      <span class="opacity-80">
                        Carteira de investimentos com rentabilidade de +12,5% — acima do CDI no período
                      </span>
                    </div>
                    <div class="flex items-start gap-2 text-sm">
                      <.icon name="hero-check-circle" class="size-4 text-success shrink-0 mt-0.5" />
                      <span class="opacity-80">
                        Proventos de R$ 780,40 recebidos — renda passiva crescente
                      </span>
                    </div>
                    <div class="flex items-start gap-2 text-sm">
                      <.icon name="hero-x-circle" class="size-4 text-error shrink-0 mt-0.5" />
                      <span class="opacity-80">
                        Alimentação a 32% do total — acima do recomendado de 25%
                      </span>
                    </div>
                    <div class="flex items-start gap-2 text-sm">
                      <.icon name="hero-light-bulb" class="size-4 text-warning shrink-0 mt-0.5" />
                      <span class="opacity-80">
                        XPLG11 com rentabilidade negativa (-2,4%) — considere reavaliar posição
                      </span>
                    </div>
                    <div class="flex items-start gap-2 text-sm">
                      <.icon name="hero-light-bulb" class="size-4 text-warning shrink-0 mt-0.5" />
                      <span class="opacity-80">
                        Cozinhar em casa 3x por semana pode economizar até R$ 400/mês
                      </span>
                    </div>
                  </div>

                  <div class="alert alert-warning text-sm py-2 mb-3">
                    <.icon name="hero-exclamation-triangle" class="size-4" />
                    <span>
                      Atenção: concentração de 46,6% da carteira em ações — diversifique em renda fixa
                    </span>
                  </div>

                  <div class="bg-primary/5 border border-primary/10 rounded-lg p-3">
                    <div class="flex items-center gap-1.5 mb-1">
                      <.icon name="hero-chat-bubble-left-right" class="size-3.5 text-primary" />
                      <span class="text-xs font-medium text-primary">Resposta</span>
                    </div>
                    <p class="text-sm opacity-80">
                      Para economizar, reduza gastos com delivery e alimentação fora de casa.
                      Seus investimentos estão bem, mas considere rebalancear: XPLG11 está com prejuízo e
                      sua exposição em ações é alta. Redirecione parte dos aportes para renda fixa.
                    </p>
                  </div>
                </div>
              </div>
            </div>
            </div>
          </div>
        </div>
      </section>

      <%!-- Features --%>
      <section id="features" class="py-24 px-4 bg-base-200/50">
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
                Envie até 12 extratos de uma vez. Múltiplos meses e bancos processados simultaneamente.
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

            <div class="card bg-base-200/50 p-6 hover:shadow-lg transition-shadow">
              <div class="w-12 h-12 rounded-xl bg-success/10 flex items-center justify-center mb-4">
                <.icon name="hero-chart-bar" class="size-6 text-success" />
              </div>
              <h3 class="font-semibold text-lg mb-2">Carteira de Investimentos</h3>
              <p class="opacity-60 text-sm">
                Acompanhe ações, FIIs e renda fixa com cotações ao vivo, dividendos e análise de rentabilidade.
              </p>
            </div>

            <div class="card bg-base-200/50 p-6 hover:shadow-lg transition-shadow">
              <div class="w-12 h-12 rounded-xl bg-info/10 flex items-center justify-center mb-4">
                <.icon name="hero-building-library" class="size-6 text-info" />
              </div>
              <h3 class="font-semibold text-lg mb-2">Múltiplas Fontes</h3>
              <p class="opacity-60 text-sm">
                Nubank, Bradesco, B3, GCB e mais. Importação via CSV, XLSX ou PDF com processamento inteligente.
              </p>
            </div>

            <div :if={@roadmap_url} class="card bg-base-200/50 p-6 hover:shadow-lg transition-shadow">
              <div class="w-12 h-12 rounded-xl bg-warning/10 flex items-center justify-center mb-4">
                <.icon name="hero-light-bulb" class="size-6 text-warning" />
              </div>
              <h3 class="font-semibold text-lg mb-2">Roadmap Público</h3>
              <p class="opacity-60 text-sm">
                Vote e sugira funcionalidades. O futuro do Grana é construído junto com a comunidade.
              </p>
            </div>
          </div>
        </div>
      </section>

      <%!-- BYOK + Security --%>
      <section class="py-24 px-4 overflow-hidden">
        <style>
          .shield-container { position: relative; width: 200px; height: 200px; margin: 0 auto; }

          .shield-glow {
            position: absolute; inset: -20px;
            border-radius: 50%;
            background: radial-gradient(circle, oklch(58% 0.233 277.117 / 0.15), transparent 70%);
            animation: shieldGlow 4s ease-in-out infinite;
          }
          @keyframes shieldGlow {
            0%, 100% { transform: scale(1); opacity: 0.5; }
            50%      { transform: scale(1.15); opacity: 1; }
          }

          .shield-ring {
            position: absolute; inset: 0;
            border: 2px solid oklch(58% 0.233 277.117 / 0.2);
            border-radius: 50%;
            animation: shieldRing 6s linear infinite;
          }
          .shield-ring-2 {
            position: absolute; inset: -15px;
            border: 1px dashed oklch(58% 0.233 277.117 / 0.1);
            border-radius: 50%;
            animation: shieldRing 8s linear infinite reverse;
          }
          @keyframes shieldRing {
            from { transform: rotate(0deg); }
            to   { transform: rotate(360deg); }
          }

          .shield-pulse {
            position: absolute; inset: 10px;
            border-radius: 50%;
            border: 2px solid oklch(58% 0.233 277.117 / 0);
            animation: shieldPulse 3s ease-out infinite;
          }
          @keyframes shieldPulse {
            0%   { transform: scale(0.8); border-color: oklch(58% 0.233 277.117 / 0.4); }
            100% { transform: scale(1.5); border-color: oklch(58% 0.233 277.117 / 0); }
          }

          .data-particle {
            position: absolute;
            width: 4px; height: 4px;
            border-radius: 50%;
            background: oklch(58% 0.233 277.117 / 0.6);
          }
          .data-particle:nth-child(1) { animation: particle1 5s ease-in-out infinite; }
          .data-particle:nth-child(2) { animation: particle2 5s ease-in-out 0.8s infinite; }
          .data-particle:nth-child(3) { animation: particle3 5s ease-in-out 1.6s infinite; }
          .data-particle:nth-child(4) { animation: particle4 5s ease-in-out 2.4s infinite; }

          @keyframes particle1 {
            0%   { top: 50%; left: -30px; opacity: 0; }
            20%  { opacity: 1; }
            50%  { top: 50%; left: 50%; opacity: 0; }
            100% { top: 50%; left: 50%; opacity: 0; }
          }
          @keyframes particle2 {
            0%   { top: -30px; left: 50%; opacity: 0; }
            20%  { opacity: 1; }
            50%  { top: 50%; left: 50%; opacity: 0; }
            100% { top: 50%; left: 50%; opacity: 0; }
          }
          @keyframes particle3 {
            0%   { top: 50%; right: -30px; left: auto; opacity: 0; }
            20%  { opacity: 1; }
            50%  { top: 50%; right: 50%; left: auto; opacity: 0; }
            100% { top: 50%; right: 50%; left: auto; opacity: 0; }
          }
          @keyframes particle4 {
            0%   { bottom: -30px; top: auto; left: 50%; opacity: 0; }
            20%  { opacity: 1; }
            50%  { bottom: 50%; top: auto; left: 50%; opacity: 0; }
            100% { bottom: 50%; top: auto; left: 50%; opacity: 0; }
          }
        </style>

        <div class="max-w-6xl mx-auto">
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-16 items-center">
            <div class="order-2 lg:order-1 flex justify-center">
              <div class="shield-container">
                <div class="shield-glow"></div>
                <div class="shield-ring"></div>
                <div class="shield-ring-2"></div>
                <div class="shield-pulse"></div>
                <div class="data-particle"></div>
                <div class="data-particle"></div>
                <div class="data-particle"></div>
                <div class="data-particle"></div>
                <div class="absolute inset-0 flex items-center justify-center">
                  <div class="w-24 h-24 rounded-2xl bg-base-100 border border-primary/20 flex items-center justify-center shadow-xl">
                    <.icon name="hero-shield-check" class="size-12 text-primary" />
                  </div>
                </div>
              </div>
            </div>

            <div class="order-1 lg:order-2">
              <p
                style="font-family: 'Grand Hotel', cursive"
                class="text-primary text-5xl mb-3"
              >
                Segurança total
              </p>
              <h2 class="text-3xl md:text-4xl font-bold tracking-tight mb-4">
                Seus dados, sua chave
              </h2>
              <p class="text-lg opacity-60 mb-8">
                O Grana funciona com a <strong class="text-base-content">sua própria API Key</strong>
                do Google Gemini.
                Isso significa que a plataforma não tem custo de infraestrutura de IA.
              </p>

              <div class="space-y-5">
                <div class="flex items-start gap-4">
                  <div class="w-10 h-10 rounded-xl bg-success/10 flex items-center justify-center shrink-0">
                    <.icon name="hero-key" class="size-5 text-success" />
                  </div>
                  <div>
                    <p class="font-semibold text-sm mb-1">Traga sua própria API Key (BYOK)</p>
                    <p class="text-sm opacity-60">
                      Você usa sua chave. A IA roda diretamente na sua conta, sem intermediários.
                    </p>
                  </div>
                </div>

                <div class="flex items-start gap-4">
                  <div class="w-10 h-10 rounded-xl bg-info/10 flex items-center justify-center shrink-0">
                    <.icon name="hero-currency-dollar" class="size-5 text-info" />
                  </div>
                  <div>
                    <p class="font-semibold text-sm mb-1">Custo zero</p>
                    <p class="text-sm opacity-60">
                      Como você traz sua própria chave, não cobramos nada pelo uso da plataforma.
                    </p>
                  </div>
                </div>

                <div class="flex items-start gap-4">
                  <div class="w-10 h-10 rounded-xl bg-warning/10 flex items-center justify-center shrink-0">
                    <.icon name="hero-lock-closed" class="size-5 text-warning" />
                  </div>
                  <div>
                    <p class="font-semibold text-sm mb-1">100% dos dados sob seu controle</p>
                    <p class="text-sm opacity-60">
                      Seus extratos são processados localmente. As análises de IA são feitas diretamente entre você e sua LLM. Nenhum dado financeiro é armazenado em servidores terceiros.
                    </p>
                  </div>
                </div>

                <div class="flex items-start gap-4">
                  <div class="w-10 h-10 rounded-xl bg-error/10 flex items-center justify-center shrink-0">
                    <.icon name="hero-trash" class="size-5 text-error" />
                  </div>
                  <div>
                    <p class="font-semibold text-sm mb-1">Exclusão completa a qualquer momento</p>
                    <p class="text-sm opacity-60">
                      Você pode excluir sua conta e todos os dados associados a qualquer momento nas configurações. Sem burocracia.
                    </p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <%!-- Roadmap / Community --%>
      <section :if={@roadmap_url} class="py-24 px-4 bg-base-200/50">
        <style>
          .vote-btn {
            animation: votePulse 3s ease-in-out infinite;
          }
          @keyframes votePulse {
            0%, 100% { transform: scale(1); }
            50% { transform: scale(1.05); }
          }
        </style>

        <div class="max-w-4xl mx-auto text-center">
          <p
            style="font-family: 'Grand Hotel', cursive"
            class="text-primary text-5xl mb-3"
          >
            Comunidade
          </p>
          <h2 class="text-3xl md:text-4xl font-bold tracking-tight mb-4">
            Construído com você
          </h2>
          <p class="text-lg opacity-60 max-w-xl mx-auto mb-12">
            Nosso roadmap é público. Vote nas funcionalidades que importam para você
            e sugira novos bancos, corretoras e recursos.
          </p>

          <div class="max-w-lg mx-auto space-y-3 mb-10">
            <div
              :for={
                {votes, title, tag, tag_color} <- [
                  {"47", "Suporte ao Banco Inter", "Novo banco", "badge-info"},
                  {"32", "App mobile (iOS / Android)", "Feature", "badge-primary"},
                  {"28", "Importar notas de corretagem da XP", "Nova corretora", "badge-success"},
                  {"19", "Orçamento mensal por categoria", "Feature", "badge-primary"}
                ]
              }
              class="flex items-center gap-4 p-3 rounded-xl bg-base-200/50 border border-base-content/5 text-left"
            >
              <div class="vote-btn flex flex-col items-center justify-center w-12 h-12 rounded-lg bg-primary/10 border border-primary/20 shrink-0">
                <.icon name="hero-chevron-up" class="size-4 text-primary -mb-1" />
                <span class="text-sm font-bold text-primary">{votes}</span>
              </div>
              <div class="flex-1 min-w-0">
                <p class="text-sm font-medium truncate">{title}</p>
                <span class={"badge badge-xs #{tag_color} mt-1"}>{tag}</span>
              </div>
            </div>
          </div>

          <a href={@roadmap_url} target="_blank" class="btn btn-primary btn-lg gap-2">
            <.icon name="hero-light-bulb" class="size-5" />
            Acessar Roadmap
          </a>
        </div>
      </section>

      <%!-- CTA --%>
      <section class="py-24 px-4">
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
              Criar Conta
            </.link>
            <.link navigate={~p"/users/log-in"} class="btn btn-ghost btn-lg">
              Já tenho conta
            </.link>
          </div>
        </div>
      </section>

      <%!-- Footer --%>
      <footer class="border-t border-base-content/5 px-4 sm:px-6 lg:px-8 py-8">
        <div class="max-w-6xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-4">
          <a href="/" class="flex items-center gap-2 text-xl font-bold tracking-tight">
            <img src={~p"/images/logo-32.png"} alt="" class="w-7 h-7" />
            <span style="font-family: 'Grand Hotel', cursive">Grana</span>
          </a>
          <div class="flex items-center gap-6 text-sm">
            <.link navigate={~p"/terms"} class="opacity-50 hover:opacity-80 transition-opacity">
              Termos de Uso e Privacidade
            </.link>
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
end
