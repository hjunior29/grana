defmodule GranaWeb.Layouts do
  use GranaWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current scope"

  attr :hide_nav, :boolean,
    default: false,
    doc: "hide the navigation bar"

  attr :show_appearance, :boolean,
    default: false,
    doc: "mostra tema e estilo visual no header (telas sem login, como o setup)"

  attr :import_queue, :map,
    default: nil,
    doc: "andamento da importação (`@import_queue`), mostrado como aviso flutuante"

  attr :import_toast, :atom,
    default: :bottom,
    values: [:bottom, :top],
    doc: "onde ficam os avisos flutuantes (no alto em telas com campo fixo embaixo, como o chat)"

  attr :ai_notice, :map,
    default: nil,
    doc:
      "trabalho de IA concluído em outra tela (`@ai_notice`): resposta do chat ou busca montada"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div
      id="app-shell"
      class={[
        "grana-app-shell min-h-screen flex flex-col",
        @current_scope && @current_scope.user.hide_values && "ui-hide-values",
        @current_scope && @current_scope.user.hide_names && "ui-hide-names"
      ]}
    >
      <header class="grana-app-header navbar bg-base-100/20 backdrop-blur-xl sticky top-0 z-50 border-b border-base-content/5 px-3 sm:px-6 lg:px-8 min-h-12">
        <div class="flex-1">
          <.link
            navigate={if @current_scope, do: ~p"/dashboard", else: ~p"/"}
            id="header-brand"
            class="flex items-center"
          >
            <GranaWeb.BrandComponents.brand
              logo_class="size-6 sm:size-7"
              wordmark_class="h-4 sm:h-5 w-auto"
            />
          </.link>
        </div>
        <div :if={@show_appearance} id="header-appearance" class="flex flex-none items-center gap-2">
          <.theme_toggle />
          <details class="dropdown dropdown-end">
            <summary
              id="header-visual-style"
              class="btn btn-ghost btn-sm btn-circle list-none"
              title="Estilo visual"
            >
              <.icon name="hero-paint-brush" class="size-5" />
            </summary>
            <div class="dropdown-content z-50 mt-2 max-h-[70vh] w-[min(22rem,90vw)] overflow-y-auto rounded-box bg-base-200 p-3 shadow-xl">
              <.visual_style_toggle />
            </div>
          </details>
        </div>
        <%!-- Desktop nav --%>
        <div :if={@current_scope && !@hide_nav} class="hidden md:flex flex-none">
          <ul class="menu menu-horizontal gap-1 items-center" id="main-nav" phx-hook="ActiveNav">
            <li>
              <.link navigate={~p"/dashboard"} class="text-sm">Painel</.link>
            </li>
            <li>
              <.link navigate={~p"/analysis"} class="text-sm">Análise</.link>
            </li>
            <li>
              <.link navigate={~p"/chat"} class="text-sm">Chat</.link>
            </li>
            <li>
              <.link navigate={~p"/transactions"} class="text-sm">Transações</.link>
            </li>
            <li>
              <.link navigate={~p"/categories"} class="text-sm">Categorias</.link>
            </li>
            <li>
              <.link navigate={~p"/goals"} class="text-sm">Metas</.link>
            </li>
            <li>
              <.link navigate={~p"/upload"} class="text-sm">Importar</.link>
            </li>
            <li>
              <details class="dropdown dropdown-end">
                <summary class="btn btn-md btn-ghost list-none" aria-label="Conta">
                  <.icon name="hero-user-circle" class="size-5" />
                </summary>
                <ul class="dropdown-content menu bg-base-200 rounded-box w-56 p-2 shadow-xl z-50 mt-2">
                  <li class="ui-help px-3 py-2">{@current_scope.user.email}</li>
                  <li>
                    <.link navigate={~p"/users/settings"}>
                      <.icon name="hero-cog-6-tooth" class="size-4" /> Configurações
                    </.link>
                  </li>
                  <li>
                    <.link href={~p"/users/log-out"} method="delete">
                      <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Sair
                    </.link>
                  </li>
                </ul>
              </details>
            </li>
          </ul>
        </div>
        <%!-- Mobile hamburger menu --%>
        <div :if={@current_scope && !@hide_nav} class="flex md:hidden flex-none">
          <details class="dropdown dropdown-end">
            <summary class="btn btn-ghost btn-sm px-2" aria-label="Menu">
              <.icon name="hero-bars-3" class="size-5" />
            </summary>
            <ul class="dropdown-content menu bg-base-200 rounded-box w-52 p-2 shadow-xl z-50 mt-2">
              <li>
                <.link navigate={~p"/dashboard"}>
                  <.icon name="hero-chart-bar" class="size-4" /> Painel
                </.link>
              </li>
              <li>
                <.link navigate={~p"/analysis"}>
                  <.icon name="hero-sparkles" class="size-4" /> Análise
                </.link>
              </li>
              <li>
                <.link navigate={~p"/chat"}>
                  <.icon name="hero-chat-bubble-left-right" class="size-4" /> Chat
                </.link>
              </li>
              <li>
                <.link navigate={~p"/transactions"}>
                  <.icon name="hero-list-bullet" class="size-4" /> Transações
                </.link>
              </li>
              <li>
                <.link navigate={~p"/categories"}>
                  <.icon name="hero-tag" class="size-4" /> Categorias
                </.link>
              </li>
              <li>
                <.link navigate={~p"/goals"}>
                  <.icon name="hero-flag" class="size-4" /> Metas
                </.link>
              </li>
              <li>
                <.link navigate={~p"/upload"}>
                  <.icon name="hero-cloud-arrow-up" class="size-4" /> Importar
                </.link>
              </li>
              <hr class="my-1 border-base-content/10" />
              <li class="ui-help py-1">{@current_scope.user.email}</li>
              <li>
                <.link navigate={~p"/users/settings"}>
                  <.icon name="hero-cog-6-tooth" class="size-4" /> Configurações
                </.link>
              </li>
              <li>
                <.link href={~p"/users/log-out"} method="delete">
                  <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Sair
                </.link>
              </li>
            </ul>
          </details>
        </div>
      </header>

      <main class="grana-app-main flex-1 px-3 py-4 sm:px-6 sm:py-8 lg:px-8">
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
      <div
        id="floating-notices"
        class={[
          "fixed right-4 left-4 z-40 flex flex-col gap-3 sm:left-auto sm:w-96",
          if(@import_toast == :top, do: "top-20", else: "bottom-4")
        ]}
      >
        <GranaWeb.ImportComponents.import_toast queue={@import_queue} />
        <GranaWeb.AiNoticeComponents.ai_toast notice={@ai_notice} />
      </div>
    </div>
    """
  end

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="NotificationStack"
      aria-live="polite"
      class="fixed right-4 top-20 z-50 flex flex-col gap-3 pointer-events-none"
    >
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <div
        id="connection-error"
        class="ui-notice ui-notice-warning ui-toast pointer-events-auto hidden shadow-lg"
        phx-disconnected={
          JS.show(
            to: "#connection-error",
            transition: {"ease-out duration-300", "opacity-0", "opacity-100"},
            time: 3000
          )
        }
        phx-connected={
          JS.hide(
            to: "#connection-error",
            transition: {"ease-in duration-200", "opacity-100", "opacity-0"}
          )
        }
      >
        <.icon name="hero-arrow-path" class="size-4 motion-safe:animate-spin" />
        <span>Reconectando…</span>
      </div>
    </div>
    """
  end

  # Aplica na hora no navegador (JS) e, quando `persist`, também grava no servidor.
  defp set_preference(event, key, value, persist) do
    js = JS.dispatch(event)
    if persist, do: JS.push(js, "set_preference", value: %{key => value}), else: js
  end

  attr :persist, :boolean,
    default: false,
    doc: "salva a escolha no servidor (só em LiveViews autenticadas)"

  def theme_toggle(assigns) do
    ~H"""
    <div class="theme-toggle card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        aria-label="Tema do sistema"
        title="Tema do sistema"
        phx-click={set_preference("phx:set-theme", "theme", "system", @persist)}
        data-phx-theme="system"
      >
        <.icon
          name="hero-computer-desktop-micro"
          class="ui-text-secondary size-4 hover:text-base-content"
        />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        aria-label="Tema claro"
        title="Tema claro"
        phx-click={set_preference("phx:set-theme", "theme", "light", @persist)}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="ui-text-secondary size-4 hover:text-base-content" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        aria-label="Tema escuro"
        title="Tema escuro"
        phx-click={set_preference("phx:set-theme", "theme", "dark", @persist)}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="ui-text-secondary size-4 hover:text-base-content" />
      </button>
    </div>
    """
  end

  attr :persist, :boolean, default: false
  attr :grid, :boolean, default: false, doc: "opções em 2 colunas, com prévia menor"

  def visual_style_toggle(assigns) do
    ~H"""
    <div
      id="visual-style-toggle"
      class="visual-style-toggle"
      data-grid={@grid && "true"}
      role="group"
      aria-label="Estilo visual"
    >
      <button
        type="button"
        class="visual-style-option"
        phx-click={set_preference("phx:set-visual-style", "visual_style", "default", @persist)}
        data-phx-visual-style="default"
      >
        <span class="visual-style-copy">
          <span class="visual-style-name">
            <.icon name="hero-squares-2x2-micro" class="size-4" /> Default
          </span>
          <span class="visual-style-description">
            Neutro, limpo e próximo do visual original do app.
          </span>
        </span>
        <span class="visual-style-preview visual-style-preview-default" aria-hidden="true">
          <span class="visual-preview-header"></span>
          <span class="visual-preview-body">
            <span></span>
            <span></span>
          </span>
        </span>
      </button>

      <button
        type="button"
        class="visual-style-option"
        phx-click={set_preference("phx:set-visual-style", "visual_style", "signal", @persist)}
        data-phx-visual-style="signal"
      >
        <span class="visual-style-copy">
          <span class="visual-style-name">
            <.icon name="hero-command-line-micro" class="size-4" /> Signal
          </span>
          <span class="visual-style-description">
            Técnico, preciso e com contraste de painel operacional.
          </span>
        </span>
        <span class="visual-style-preview visual-style-preview-signal" aria-hidden="true">
          <span class="visual-preview-header"></span>
          <span class="visual-preview-body">
            <span></span>
            <span></span>
          </span>
        </span>
      </button>

      <button
        type="button"
        class="visual-style-option"
        phx-click={set_preference("phx:set-visual-style", "visual_style", "bossa", @persist)}
        data-phx-visual-style="bossa"
      >
        <span class="visual-style-copy">
          <span class="visual-style-name">
            <.icon name="hero-bolt-micro" class="size-4" /> Bossa
          </span>
          <span class="visual-style-description">
            Editorial, gráfico e com personalidade mais marcada.
          </span>
        </span>
        <span class="visual-style-preview visual-style-preview-bossa" aria-hidden="true">
          <span class="visual-preview-header"></span>
          <span class="visual-preview-body">
            <span></span>
            <span></span>
          </span>
        </span>
      </button>

      <button
        type="button"
        class="visual-style-option"
        phx-click={set_preference("phx:set-visual-style", "visual_style", "papel", @persist)}
        data-phx-visual-style="papel"
      >
        <span class="visual-style-copy">
          <span class="visual-style-name">
            <.icon name="hero-newspaper-micro" class="size-4" /> Papel
          </span>
          <span class="visual-style-description">
            Tipográfico, claro e com o rigor de grelha de uma revista suíça.
          </span>
        </span>
        <span class="visual-style-preview visual-style-preview-papel" aria-hidden="true">
          <span class="visual-preview-header"></span>
          <span class="visual-preview-body">
            <span></span>
            <span></span>
          </span>
        </span>
      </button>

      <button
        type="button"
        class="visual-style-option"
        phx-click={set_preference("phx:set-visual-style", "visual_style", "caderneta", @persist)}
        data-phx-visual-style="caderneta"
      >
        <span class="visual-style-copy">
          <span class="visual-style-name">
            <.icon name="hero-book-open-micro" class="size-4" /> Caderneta
          </span>
          <span class="visual-style-description">
            Retrô, caloroso e com o charme de uma caderneta de poupança.
          </span>
        </span>
        <span class="visual-style-preview visual-style-preview-caderneta" aria-hidden="true">
          <span class="visual-preview-header"></span>
          <span class="visual-preview-body">
            <span></span>
            <span></span>
          </span>
        </span>
      </button>

      <button
        type="button"
        class="visual-style-option"
        phx-click={set_preference("phx:set-visual-style", "visual_style", "planetario", @persist)}
        data-phx-visual-style="planetario"
      >
        <span class="visual-style-copy">
          <span class="visual-style-name">
            <.icon name="hero-sparkles-micro" class="size-4" /> Planetário
          </span>
          <span class="visual-style-description">
            Noturno, sereno e contemplativo como uma carta celeste.
          </span>
        </span>
        <span class="visual-style-preview visual-style-preview-planetario" aria-hidden="true">
          <span class="visual-preview-header"></span>
          <span class="visual-preview-body">
            <span></span>
            <span></span>
          </span>
        </span>
      </button>

      <button
        type="button"
        class="visual-style-option"
        phx-click={set_preference("phx:set-visual-style", "visual_style", "cyber", @persist)}
        data-phx-visual-style="cyber"
      >
        <span class="visual-style-copy">
          <span class="visual-style-name">
            <.icon name="hero-command-line-micro" class="size-4" /> Cyber Dev
          </span>
          <span class="visual-style-description">
            Escuro, neon e feito para quem vive no terminal.
          </span>
        </span>
        <span class="visual-style-preview visual-style-preview-cyber" aria-hidden="true">
          <span class="visual-preview-header"></span>
          <span class="visual-preview-body">
            <span></span>
            <span></span>
          </span>
        </span>
      </button>
    </div>
    """
  end
end
