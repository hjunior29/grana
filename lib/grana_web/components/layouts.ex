defmodule GranaWeb.Layouts do
  use GranaWeb, :html

  defp admin_user?(scope) do
    admin_email = Application.get_env(:grana, :admin_email)
    scope && scope.user && admin_email && scope.user.email == admin_email
  end

  defp roadmap_url, do: Application.get_env(:grana, :roadmap_url)

  embed_templates "layouts/*"

  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current scope"

  attr :hide_nav, :boolean,
    default: false,
    doc: "hide the navigation bar"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="app-shell min-h-screen flex flex-col">
      <div class="app-background" aria-hidden="true"></div>
      <header class="app-header">
        <div class="mx-auto flex h-16 max-w-7xl items-center gap-3 px-3 sm:px-6 lg:px-8">
          <.link
            navigate={if @current_scope, do: ~p"/dashboard", else: ~p"/"}
            class="app-brand"
            aria-label="Grana"
          >
            <img src={~p"/images/logo-32.png"} alt="" class="brand-mark" />
            <span class="brand-wordmark text-2xl leading-none">Grana</span>
          </.link>

          <%!-- Desktop nav --%>
          <nav
            :if={@current_scope && !@hide_nav}
            id="main-nav"
            phx-hook="ActiveNav"
            class="ml-2 hidden flex-1 items-center justify-center gap-1 lg:flex"
            aria-label="Navegação principal"
          >
            <.link navigate={~p"/dashboard"} class="nav-pill">
              <.icon name="hero-squares-2x2" class="size-4" /> Dashboard
            </.link>
            <.link navigate={~p"/analysis"} class="nav-pill">
              <.icon name="hero-sparkles" class="size-4" /> Análise
            </.link>
            <.link navigate={~p"/transactions"} class="nav-pill">
              <.icon name="hero-list-bullet" class="size-4" /> Transações
            </.link>
            <.link navigate={~p"/categories"} class="nav-pill">
              <.icon name="hero-tag" class="size-4" /> Categorias
            </.link>
            <.link navigate={~p"/goals"} class="nav-pill">
              <.icon name="hero-flag" class="size-4" /> Metas
            </.link>
            <.link navigate={~p"/upload"} class="nav-pill">
              <.icon name="hero-cloud-arrow-up" class="size-4" /> Uploads
            </.link>
          </nav>

          <div class="ml-auto flex items-center gap-2">
            <div :if={!@current_scope && !@hide_nav} class="hidden items-center gap-2 sm:flex">
              <Layouts.theme_toggle />
              <.link navigate={~p"/users/log-in"} class="btn btn-ghost btn-sm">
                Entrar
              </.link>
              <.link navigate={~p"/users/register"} class="btn btn-primary btn-sm">
                Criar Conta
              </.link>
            </div>

            <div :if={@current_scope && !@hide_nav} class="hidden items-center gap-2 lg:flex">
              <Layouts.theme_toggle />
              <details class="dropdown dropdown-end">
                <summary class="btn btn-ghost btn-sm gap-2 rounded-full px-2">
                  <.icon name="hero-user-circle" class="size-5" />
                  <span class="max-w-28 truncate text-xs font-semibold">
                    {@current_scope.user.email}
                  </span>
                </summary>
                <ul class="dropdown-content menu account-menu-surface w-64 p-2 z-50 mt-3">
                  <li class="px-3 py-2 text-xs opacity-60 truncate">{@current_scope.user.email}</li>
                  <li>
                    <.link navigate={~p"/users/settings"}>
                      <.icon name="hero-cog-6-tooth" class="size-4" /> Configurações
                    </.link>
                  </li>
                  <%= if admin_user?(@current_scope) do %>
                    <li>
                      <.link href="/admin/oban" target="_blank">
                        <.icon name="hero-queue-list" class="size-4" /> Oban Jobs
                      </.link>
                    </li>
                    <li>
                      <.link href="/admin/errors" target="_blank">
                        <.icon name="hero-bug-ant" class="size-4" /> Error Tracker
                      </.link>
                    </li>
                  <% end %>
                  <li :if={roadmap_url()}>
                    <.link href={roadmap_url()} target="_blank">
                      <.icon name="hero-light-bulb" class="size-4" /> Roadmap
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

            <%!-- Mobile menu --%>
            <details
              :if={!@hide_nav}
              class={[
                "dropdown dropdown-end",
                @current_scope && "lg:hidden",
                !@current_scope && "sm:hidden"
              ]}
            >
              <summary class="btn btn-ghost btn-sm px-2">
                <.icon name="hero-bars-3" class="size-5" />
              </summary>
              <ul class="dropdown-content menu mobile-menu-surface w-64 p-2 z-50 mt-3">
                <%= if @current_scope do %>
                  <li class="px-3 py-2 text-xs opacity-60 truncate">{@current_scope.user.email}</li>
                  <li>
                    <.link navigate={~p"/dashboard"}>
                      <.icon name="hero-squares-2x2" class="size-4" /> Dashboard
                    </.link>
                  </li>
                  <li>
                    <.link navigate={~p"/analysis"}>
                      <.icon name="hero-sparkles" class="size-4" /> Análise
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
                      <.icon name="hero-cloud-arrow-up" class="size-4" /> Uploads
                    </.link>
                  </li>
                  <hr class="my-1 opacity-30" />
                  <li>
                    <.link navigate={~p"/users/settings"}>
                      <.icon name="hero-cog-6-tooth" class="size-4" /> Configurações
                    </.link>
                  </li>
                  <li :if={roadmap_url()}>
                    <.link href={roadmap_url()} target="_blank">
                      <.icon name="hero-light-bulb" class="size-4" /> Roadmap
                    </.link>
                  </li>
                  <%= if admin_user?(@current_scope) do %>
                    <li>
                      <.link href="/admin/oban" target="_blank">
                        <.icon name="hero-queue-list" class="size-4" /> Oban Jobs
                      </.link>
                    </li>
                    <li>
                      <.link href="/admin/errors" target="_blank">
                        <.icon name="hero-bug-ant" class="size-4" /> Error Tracker
                      </.link>
                    </li>
                  <% end %>
                  <li>
                    <.link href={~p"/users/log-out"} method="delete">
                      <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Sair
                    </.link>
                  </li>
                <% else %>
                  <li>
                    <.link navigate={~p"/users/log-in"}>
                      <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Entrar
                    </.link>
                  </li>
                  <li>
                    <.link navigate={~p"/users/register"}>
                      <.icon name="hero-user-plus" class="size-4" /> Criar Conta
                    </.link>
                  </li>
                  <li>
                    <.link navigate={~p"/terms"}>
                      <.icon name="hero-shield-check" class="size-4" /> Termos
                    </.link>
                  </li>
                <% end %>
                <li class="px-3 py-2">
                  <Layouts.theme_toggle />
                </li>
              </ul>
            </details>
          </div>
        </div>
      </header>

      <main class={["app-main", @hide_nav && "auth-main"]}>
        {render_slot(@inner_block)}
      </main>
    </div>

    <.flash_group flash={@flash} />
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
      class="fixed bottom-4 right-4 z-50 flex flex-col-reverse gap-3 pointer-events-none"
    >
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <div
        id="connection-error"
        class="hidden alert alert-warning shadow-lg pointer-events-auto text-sm"
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
        <span>{gettext("Reconectando...")}</span>
      </div>
    </div>
    """
  end

  def theme_toggle(assigns) do
    ~H"""
    <div class="theme-toggle relative">
      <div class="theme-toggle-indicator" />

      <button
        type="button"
        class="theme-toggle-button"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label="Usar tema do sistema"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4" />
      </button>

      <button
        type="button"
        class="theme-toggle-button"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label="Usar tema claro"
      >
        <.icon name="hero-sun-micro" class="size-4" />
      </button>

      <button
        type="button"
        class="theme-toggle-button"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label="Usar tema escuro"
      >
        <.icon name="hero-moon-micro" class="size-4" />
      </button>
    </div>
    """
  end
end
