defmodule GranaiWeb.Layouts do
  use GranaiWeb, :html

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
    <div class="min-h-screen flex flex-col">
      <header class="navbar bg-base-100/20 backdrop-blur-xl sticky top-0 z-50 border-b border-base-content/5 px-3 sm:px-6 lg:px-8 min-h-12">
        <div class="flex-1">
          <.link
            navigate={if @current_scope, do: ~p"/dashboard", else: ~p"/"}
            class="flex items-center gap-2 text-xl font-bold tracking-tight"
          >
            <img src={~p"/images/logo-32.png"} alt="" class="w-6 h-6 sm:w-7 sm:h-7" />
            <span style="font-family: 'Grand Hotel', cursive" class="text-xl sm:text-2xl">
              Granai
            </span>
          </.link>
        </div>
        <%!-- Desktop nav --%>
        <div :if={@current_scope && !@hide_nav} class="hidden md:flex flex-none">
          <ul class="menu menu-horizontal gap-1 items-center" id="main-nav" phx-hook="ActiveNav">
            <li>
              <.link navigate={~p"/dashboard"} class="text-sm">Dashboard</.link>
            </li>
            <li>
              <.link navigate={~p"/analysis"} class="text-sm">Análise</.link>
            </li>
            <li>
              <.link navigate={~p"/transactions"} class="text-sm">Transações</.link>
            </li>
            <li>
              <.link navigate={~p"/categories"} class="text-sm">Categorias</.link>
            </li>
            <li>
              <.link navigate={~p"/upload"} class="text-sm">Uploads</.link>
            </li>
            <li>
              <details class="dropdown dropdown-end">
                <summary class="btn-md btn-ghost">
                  <.icon name="hero-user-circle" class="size-5" />
                </summary>
                <ul class="dropdown-content menu bg-base-200 rounded-box w-56 p-2 shadow-xl z-50 mt-2">
                  <li class="px-3 py-2 text-xs opacity-50">{@current_scope.user.email}</li>
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
            <summary class="btn btn-ghost btn-sm px-2">
              <.icon name="hero-bars-3" class="size-5" />
            </summary>
            <ul class="dropdown-content menu bg-base-200 rounded-box w-52 p-2 shadow-xl z-50 mt-2">
              <li>
                <.link navigate={~p"/dashboard"}>
                  <.icon name="hero-chart-bar" class="size-4" /> Dashboard
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
                <.link navigate={~p"/upload"}>
                  <.icon name="hero-cloud-arrow-up" class="size-4" /> Uploads
                </.link>
              </li>
              <hr class="my-1 opacity-30" />
              <li class="py-1 text-xs opacity-50">{@current_scope.user.email}</li>
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

      <main class="flex-1 px-3 py-4 sm:px-6 sm:py-8 lg:px-8">
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

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Tentando reconectar...")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Algo deu errado!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Tentando reconectar...")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
