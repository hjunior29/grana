defmodule GranaWeb.UiComponents do
  @moduledoc """
  Componentes do padrão de design (ver `doc/DESIGN.md`): card, seção, tag, aviso,
  linha de item, tile de número, campo do `.env`, seletor de arquivo, modais,
  estado vazio, cabeçalho de página, abas, filtros, dinheiro e chip de origem.
  """
  use Phoenix.Component
  use GranaWeb, :verified_routes

  import GranaWeb.CoreComponents, only: [button: 1, icon: 1]

  alias Phoenix.LiveView.JS

  @money_tones [:receita, :despesa, :investimento, :fixa, :variavel, :neutro]

  @doc """
  Card de página. O cabeçalho (ícone, título, descrição alinhada ao título) e o
  respiro até o conteúdo são sempre os mesmos; os blocos internos ficam a 24px.
  """
  attr :id, :string, default: nil
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :icon, :string, default: nil
  attr :tone, :atom, default: :default, values: [:default, :danger]

  attr :spaced, :boolean,
    default: true,
    doc: "false dentro de grades, que já têm o seu espaçamento"

  attr :class, :any, default: nil
  attr :rest, :global

  slot :logo, doc: "ícone customizado (substitui `icon`)"
  slot :title_extra, doc: "ao lado do título"
  slot :aside, doc: "no lado oposto ao título"
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <section
      id={@id}
      class={[
        "card bg-base-200 p-6",
        @spaced && "mb-8",
        @tone == :danger && "border border-error/30",
        @class
      ]}
      {@rest}
    >
      <header>
        <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
          <%= if @logo != [] do %>
            {render_slot(@logo)}
          <% else %>
            <.icon
              :if={@icon}
              name={@icon}
              class={["size-5 shrink-0", @tone == :danger && "text-error"]}
            />
          <% end %>
          <h3 class={["ui-card-title", @tone == :danger && "text-error"]}>{@title}</h3>
          {render_slot(@title_extra)}
          <div :if={@aside != []} class="ml-auto">{render_slot(@aside)}</div>
        </div>
        <p :if={@description} class="ui-body ui-text-secondary mt-1 ml-8">{@description}</p>
      </header>
      <div class="mt-4 flex flex-col gap-6">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  @doc "Subseção de um card; `divider` separa do bloco anterior."
  attr :title, :string, required: true
  attr :divider, :boolean, default: false
  attr :rest, :global
  slot :inner_block, required: true

  def section(assigns) do
    ~H"""
    <div class={[@divider && "border-t border-base-content/10 pt-6"]} {@rest}>
      <h4 class="ui-section-title mb-3">{@title}</h4>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @kinds ~w(env salvo criptografado ativo pendente erro neutro)

  @doc """
  Tag de estado, com vocabulário fixo: `env`, `salvo`, `criptografado`, `ativo`,
  `pendente`, `erro` e `neutro`. O texto padrão é o nome do tipo; o slot o troca
  (ex.: o status de uma conexão).
  """
  attr :kind, :string, required: true, values: @kinds
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block

  def tag(assigns) do
    ~H"""
    <span class={["ui-tag", "ui-tag-#{@kind}", @class]} {@rest}>
      <%= if @inner_block == [] do %>
        {tag_label(@kind)}
      <% else %>
        {render_slot(@inner_block)}
      <% end %>
    </span>
    """
  end

  defp tag_label("env"), do: ".env"
  defp tag_label("salvo"), do: "salvo no Grana"
  defp tag_label(kind), do: kind

  @doc "Aviso em caixa, com ícone fixo por tom."
  attr :tone, :atom, default: :info, values: [:info, :success, :warning, :error]
  attr :title, :string, default: nil
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true
  slot :action, doc: "ação à direita (ex.: botão \"Categorizar\")"

  def notice(assigns) do
    ~H"""
    <div
      class={["ui-notice", "ui-notice-#{@tone}", @class]}
      role={if @tone == :error, do: "alert"}
      {@rest}
    >
      <.icon name={notice_icon(@tone)} class="size-5 shrink-0" />
      <div class="min-w-0">
        <p :if={@title} class="font-semibold">{@title}</p>
        <div>{render_slot(@inner_block)}</div>
      </div>
      <div :if={@action != []} class="ml-auto flex shrink-0 items-center">
        {render_slot(@action)}
      </div>
    </div>
    """
  end

  defp notice_icon(:info), do: "hero-information-circle"
  defp notice_icon(:success), do: "hero-check-circle"
  defp notice_icon(:warning), do: "hero-exclamation-triangle"
  defp notice_icon(:error), do: "hero-exclamation-circle"

  @doc "Linha de uma lista (`<ul>`): provedores, conexões, integrações."
  attr :id, :string, default: nil
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :rest, :global

  slot :leading
  slot :tags
  slot :actions
  slot :inner_block, doc: "linhas extras abaixo do subtítulo"

  def item_row(assigns) do
    ~H"""
    <li id={@id} class="flex min-h-14 items-center gap-3 py-3" {@rest}>
      {render_slot(@leading)}
      <div class="min-w-0 flex-1">
        <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
          <span class="ui-body truncate font-medium">{@title}</span>
          {render_slot(@tags)}
        </div>
        <p :if={@subtitle} class="ui-help truncate">{@subtitle}</p>
        {render_slot(@inner_block)}
      </div>
      <div :if={@actions != []} class="flex shrink-0 items-center gap-1">
        {render_slot(@actions)}
      </div>
    </li>
    """
  end

  @doc """
  Número com rótulo; use dentro de `grid grid-cols-2 sm:grid-cols-3 gap-3`. `tone` colore o
  valor pelo sentido do dinheiro (`receita`, `despesa`, `investimento`) e `caption` é a
  legenda abaixo.
  """
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :tone, :atom, default: :neutro, values: @money_tones
  attr :caption, :string, default: nil
  attr :navigate, :string, default: nil, doc: "vira um link com destaque ao passar o mouse"
  attr :muted, :boolean, default: false, doc: "sem dados: valor e legenda esmaecidos"

  def stat_tile(assigns) do
    ~H"""
    <%= if @navigate do %>
      <.link id={@id} navigate={@navigate} class="ui-stat ui-stat-link">
        <.stat_body
          id={@id}
          label={@label}
          value={@value}
          tone={@tone}
          caption={@caption}
          muted={@muted}
        />
      </.link>
    <% else %>
      <div id={@id} class="ui-stat">
        <.stat_body
          id={@id}
          label={@label}
          value={@value}
          tone={@tone}
          caption={@caption}
          muted={@muted}
        />
      </div>
    <% end %>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :tone, :atom, required: true
  attr :caption, :string, default: nil
  attr :muted, :boolean, required: true

  defp stat_body(assigns) do
    ~H"""
    <p class="ui-caption">{@label}</p>
    <p
      id={"#{@id}-value"}
      class={[
        "text-base font-semibold tabular-nums break-words sm:text-lg",
        @muted && "ui-text-tertiary",
        !@muted && money_class(@tone)
      ]}
    >
      {@value}
    </p>
    <p :if={@caption} class="ui-caption truncate">{@caption}</p>
    """
  end

  @doc """
  Campo somente leitura para um valor que vem do `.env`: mostra só o nome da
  variável (nunca o valor), com a tag `.env` no rótulo. O texto fica esmaecido para
  indicar que não pode ser alterado.
  """
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :var, :string, required: true, doc: "nome da variável de ambiente"
  attr :secret, :boolean, default: false, doc: "escolhe o ícone: chave para segredos"

  def env_field(assigns) do
    ~H"""
    <div class="mb-2">
      <label class="ui-label" for={@id}>{@label} <.tag kind="env" /></label>
      <div class="relative">
        <.icon
          name={if @secret, do: "hero-key", else: "hero-document-text"}
          class="ui-text-tertiary pointer-events-none absolute left-3 top-1/2 z-10 size-4 -translate-y-1/2"
        />
        <input
          id={@id}
          type="text"
          readonly
          value={@var}
          class="input ui-text-tertiary w-full cursor-default pl-9 font-mono text-sm"
        />
      </div>
    </div>
    """
  end

  @doc "Seletor de arquivo de upload (`live_file_input`) com zona de soltar, em português."
  attr :upload, :any, required: true
  attr :label, :string, default: "Escolher arquivo"

  def file_input(assigns) do
    ~H"""
    <div
      class="ui-dropzone"
      phx-drop-target={@upload.ref}
    >
      <.live_file_input upload={@upload} class="sr-only" />
      <label for={@upload.ref} class="ui-dropzone-label">
        <.icon name="hero-arrow-up-tray" class="size-5 shrink-0" />
        <span class="min-w-0">
          <%= case @upload.entries do %>
            <% [entry | _] -> %>
              <span class="ui-body block truncate font-medium">{entry.client_name}</span>
              <span class="ui-help">Clique para trocar o arquivo</span>
            <% [] -> %>
              <span class="ui-body block font-medium">{@label}</span>
              <span class="ui-help">ou solte aqui</span>
          <% end %>
        </span>
      </label>
    </div>
    """
  end

  @doc """
  Modal de confirmação. Sem `open`, é aberto por `show_modal/1` e fechado por
  `hide_modal/1` (sem estado no servidor); com `open`, o servidor controla e
  `on_cancel` deve ser um `JS.push`. Passe `form` para pedir campos (confirmação
  por digitação); o envio vai para `on_confirm` (evento) como `phx-submit`.
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :confirm, :string, required: true, doc: "texto do botão de confirmação"
  attr :loading, :string, required: true, doc: "texto do botão enquanto executa"
  attr :on_confirm, :any, required: true, doc: "JS (sem form) ou nome do evento (com form)"
  attr :on_cancel, :any, default: nil
  attr :open, :boolean, default: false
  attr :form, :any, default: nil
  attr :form_id, :string, default: nil
  attr :confirm_id, :string, default: nil

  slot :inner_block, required: true
  slot :fields, doc: "campos dentro do form"

  def confirm_modal(assigns) do
    assigns =
      assigns
      |> assign_new(:cancel_js, fn -> assigns.on_cancel || hide_modal(assigns.id) end)
      |> assign(:form_id, assigns.form_id || "#{assigns.id}-form")
      |> assign(:confirm_id, assigns.confirm_id || "#{assigns.id}-confirm")

    ~H"""
    <div
      id={@id}
      class={["modal", @open && "modal-open"]}
      role="dialog"
      aria-modal="true"
      aria-labelledby={"#{@id}-title"}
      phx-window-keydown={@cancel_js}
      phx-key="Escape"
    >
      <div class="modal-box">
        <h3 id={"#{@id}-title"} class="ui-card-title">{@title}</h3>
        <div class="ui-body ui-text-secondary py-4">{render_slot(@inner_block)}</div>
        <%= if @form do %>
          <.form for={@form} id={@form_id} phx-submit={@on_confirm}>
            {render_slot(@fields)}
            <div class="modal-action">
              <.button type="button" variant="ghost" phx-click={@cancel_js}>Cancelar</.button>
              <.button id={@confirm_id} variant="danger" loading={@loading}>
                {@confirm}
              </.button>
            </div>
          </.form>
        <% else %>
          <div class="modal-action">
            <.button type="button" variant="ghost" phx-click={@cancel_js}>Cancelar</.button>
            <.button
              id={@confirm_id}
              type="button"
              variant="danger"
              loading={@loading}
              phx-click={hide_modal(@on_confirm, @id)}
            >
              {@confirm}
            </.button>
          </div>
        <% end %>
      </div>
      <div class="modal-backdrop" phx-click={@cancel_js}></div>
    </div>
    """
  end

  @doc ~S|Contagem com milhar e singular/plural: `count_label(1671, "transação", "transações")`.|
  def count_label(1, singular, _plural), do: "1 #{singular}"

  def count_label(n, _singular, plural) do
    formatted = n |> Integer.to_string() |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ".")
    "#{formatted} #{plural}"
  end

  @doc "Percentual com vírgula decimal; acima de 999% vira \">999%\"."
  def format_pct(pct) when pct > 999, do: ">999%"

  def format_pct(pct) do
    "#{pct |> Kernel.*(1.0) |> Float.round(1) |> Float.to_string() |> String.replace(".", ",")}%"
  end

  def show_modal(js \\ %JS{}, id), do: JS.add_class(js, "modal-open", to: "##{id}")
  def hide_modal(js \\ %JS{}, id), do: JS.remove_class(js, "modal-open", to: "##{id}")

  @doc "Estado vazio de uma lista, com uma ação opcional."
  attr :id, :string, default: nil
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :text, :string, default: nil
  slot :action

  def empty_state(assigns) do
    ~H"""
    <div id={@id} class="flex flex-col items-center gap-2 px-4 py-6 text-center">
      <.icon name={@icon} class="ui-text-tertiary size-8" />
      <p class="ui-body font-medium">{@title}</p>
      <p :if={@text} class="ui-help max-w-sm">{@text}</p>
      <div :if={@action != []} class="mt-2">{render_slot(@action)}</div>
    </div>
    """
  end

  @doc "Cabeçalho de página: título, subtítulo e ações à direita."
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :actions

  def page_header(assigns) do
    ~H"""
    <div class="mb-6 flex flex-wrap items-start justify-between gap-3 sm:mb-8">
      <div class="min-w-0">
        <h1 class="ui-page-title">{@title}</h1>
        <p :if={@subtitle} class="ui-help mt-1 sm:text-sm">{@subtitle}</p>
      </div>
      <div :if={@actions != []} class="flex shrink-0 items-center gap-2">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  @doc "Cartão central das telas de autenticação (login, código, esqueci e redefinir senha)."
  attr :id, :string, default: nil
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :inner_block, required: true
  slot :footer

  def auth_card(assigns) do
    ~H"""
    <div id={@id} class="mx-auto w-full max-w-sm">
      <div class="card bg-base-200 p-6 sm:p-8">
        <header class="mb-6 text-center">
          <h1 class="ui-card-title">{@title}</h1>
          <p :if={@subtitle} class="ui-help mt-1 sm:text-sm">{@subtitle}</p>
        </header>
        {render_slot(@inner_block)}
      </div>
      <div :if={@footer != []} class="ui-body ui-text-secondary mt-4 text-center">
        {render_slot(@footer)}
      </div>
    </div>
    """
  end

  @doc """
  Abas. Cada `:tab` navega por `patch` ou dispara `event` com `phx-value-<param>=<value>`;
  `count` mostra um contador como tag neutra.
  """
  attr :id, :string, default: nil

  slot :tab, required: true do
    attr :id, :string
    attr :label, :string, required: true
    attr :icon, :string
    attr :count, :integer
    attr :active, :boolean
    attr :patch, :string
    attr :event, :string
    attr :param, :string
    attr :value, :string
    attr :disabled, :boolean
  end

  def tabs(assigns) do
    ~H"""
    <div id={@id} role="tablist" class="tabs tabs-border mb-6 flex-nowrap overflow-x-auto">
      <%= for tab <- @tab do %>
        <%= if tab[:patch] do %>
          <.link
            id={tab[:id]}
            role="tab"
            patch={tab.patch}
            class={["tab shrink-0 gap-1.5", tab[:active] && "tab-active"]}
          >
            <.tab_label tab={tab} />
          </.link>
        <% else %>
          <button
            id={tab[:id]}
            type="button"
            role="tab"
            disabled={tab[:disabled]}
            class={[
              "tab shrink-0 gap-1.5",
              tab[:active] && "tab-active",
              tab[:disabled] && "tab-disabled"
            ]}
            {tab_event_attrs(tab)}
          >
            <.tab_label tab={tab} />
          </button>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp tab_label(assigns) do
    ~H"""
    <.icon :if={@tab[:icon]} name={@tab.icon} class="size-4" />
    {@tab.label}
    <.tag :if={@tab[:count]} kind="neutro">{@tab.count}</.tag>
    """
  end

  defp tab_event_attrs(tab) do
    %{"phx-click" => tab[:event], "phx-value-#{tab[:param] || "tab"}" => tab[:value]}
  end

  @doc """
  Barra de filtros (período, banco, fonte…), feita de `<.chip_group>` com `<.chip>`.
  É a única barra do app; não copie.
  """
  attr :id, :string, default: nil
  slot :inner_block, required: true

  def filter_bar(assigns) do
    ~H"""
    <div id={@id} class="mb-6 flex flex-wrap items-center gap-x-4 gap-y-2">
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc "Grupo de chips com rótulo opcional."
  attr :label, :string, default: nil
  slot :inner_block, required: true

  def chip_group(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-1" role="group" aria-label={@label}>
      <span :if={@label} class="ui-caption mr-1">{@label}</span>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc "Opção de um filtro; o ativo fica na cor primária. Use `phx-click` e `phx-value-*`."
  attr :active, :boolean, default: false
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def chip(assigns) do
    ~H"""
    <button
      type="button"
      aria-pressed={to_string(@active)}
      class={["ui-chip", @active && "ui-chip-active", @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Valor em reais colorido pelo sentido do dinheiro. `tone={:auto}` colore pelo sinal
  (positivo `receita`, negativo `despesa`); `sign` mostra `+` nos positivos.
  """
  attr :value, :any, required: true, doc: "Decimal ou nil"
  attr :tone, :atom, default: :neutro, values: [:auto | @money_tones]
  attr :sign, :boolean, default: false
  attr :currency, :string, default: "BRL"
  attr :class, :any, default: nil
  attr :rest, :global

  def money(assigns) do
    assigns = assign(assigns, :resolved_tone, resolve_tone(assigns.tone, assigns.value))

    ~H"""
    <span class={["tabular-nums whitespace-nowrap", money_class(@resolved_tone), @class]} {@rest}>
      {format_money(@value, @currency, @sign)}
    </span>
    """
  end

  defp resolve_tone(:auto, %Decimal{} = value) do
    cond do
      Decimal.positive?(value) -> :receita
      Decimal.negative?(value) -> :despesa
      true -> :neutro
    end
  end

  defp resolve_tone(:auto, _value), do: :neutro
  defp resolve_tone(tone, _value), do: tone

  defp money_class(:neutro), do: nil
  defp money_class(tone), do: "ui-money-#{tone}"

  defp format_money(%Decimal{} = value, currency, true) do
    text = Grana.Money.format(value, currency)
    if Decimal.positive?(value), do: "+" <> text, else: text
  end

  defp format_money(value, currency, _sign), do: Grana.Money.format(value, currency)

  @doc """
  Origem de uma transação ou extrato: logo do banco, nome e tipo (Extrato ou Fatura); com
  `open_finance`, mostra também o símbolo do Open Finance.
  """
  attr :bank, :string, required: true
  attr :type, :string, default: nil, doc: "extrato ou fatura"
  attr :open_finance, :boolean, default: false
  attr :rest, :global

  def source_chip(assigns) do
    ~H"""
    <span class="ui-source-chip" {@rest}>
      <span
        :if={@open_finance}
        class="grid size-4 shrink-0 place-items-center rounded-full bg-base-300"
        title="Período sem upload: dado lido via Open Finance"
      >
        <GranaWeb.OpenFinanceComponents.open_finance_logo class="size-3" />
      </span>
      <img src={bank_logo_url(@bank)} alt="" class="size-4 shrink-0 rounded-full" />
      {bank_name(@bank)}
      <span :if={@type} class="ui-text-tertiary">({type_label(@type)})</span>
    </span>
    """
  end

  def bank_logo_url("nubank"), do: ~p"/images/nubank-logo.png"
  def bank_logo_url("bradesco"), do: ~p"/images/bradesco-logo.png"
  def bank_logo_url(_), do: ~p"/images/logo-32.png"

  defp bank_name(bank), do: String.capitalize(bank || "")

  defp type_label("fatura"), do: "Fatura"
  defp type_label("extrato"), do: "Extrato"
  defp type_label(other), do: other

  @doc """
  Modal com formulário (criar ou editar), controlado pelo servidor (`open`). Os campos vão no
  bloco principal; sem o slot `actions`, mostra Cancelar e o botão de envio.
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :open, :boolean, default: true
  attr :form, :any, required: true
  attr :form_id, :string, default: nil
  attr :on_submit, :string, required: true
  attr :on_change, :string, default: nil
  attr :on_cancel, :any, required: true, doc: "JS.push do cancelamento"
  attr :submit, :string, default: "Salvar"
  attr :loading, :string, default: "Salvando…"
  attr :box_class, :any, default: nil, doc: "classes extras do corpo do modal (ex.: largura)"

  slot :inner_block, required: true
  slot :actions

  def form_modal(assigns) do
    assigns = assign(assigns, :form_id, assigns.form_id || "#{assigns.id}-form")

    ~H"""
    <div
      id={@id}
      class={["modal", @open && "modal-open"]}
      role="dialog"
      aria-modal="true"
      aria-labelledby={"#{@id}-title"}
      phx-window-keydown={@on_cancel}
      phx-key="Escape"
    >
      <div class={["modal-box", @box_class]}>
        <h3 id={"#{@id}-title"} class="ui-card-title mb-4">{@title}</h3>
        <.form for={@form} id={@form_id} phx-submit={@on_submit} phx-change={@on_change}>
          {render_slot(@inner_block)}
          <div class="modal-action">
            <%= if @actions != [] do %>
              {render_slot(@actions)}
            <% else %>
              <.button type="button" variant="ghost" phx-click={@on_cancel}>Cancelar</.button>
              <.button id={"#{@id}-submit"} variant="primary" loading={@loading}>{@submit}</.button>
            <% end %>
          </div>
        </.form>
      </div>
      <div class="modal-backdrop" phx-click={@on_cancel}></div>
    </div>
    """
  end

  @doc "Aviso de que falta um provedor de IA, usado onde a IA é necessária (Importar e Análise)."
  attr :id, :string, default: "ai-required-modal"
  attr :reason, :string, required: true, doc: "por que a IA é necessária, em uma frase"
  attr :on_dismiss, :string, default: "dismiss_api_alert"

  def ai_required_modal(assigns) do
    ~H"""
    <div
      id={@id}
      class="modal modal-open"
      role="dialog"
      aria-modal="true"
      aria-labelledby={"#{@id}-title"}
      phx-window-keydown={@on_dismiss}
      phx-key="Escape"
    >
      <div class="modal-box">
        <h3 id={"#{@id}-title"} class="ui-card-title">Provedor de IA não configurado</h3>
        <div class="ui-body ui-text-secondary py-4">
          <p>
            {@reason} Cadastre um provedor de IA (Gemini, OpenAI, Claude ou compatível).
          </p>
          <ol class="mt-3 list-inside list-decimal space-y-1">
            <li>
              Crie uma chave no provedor que preferir:
              <a
                href="https://aistudio.google.com/apikey"
                target="_blank"
                rel="noopener"
                class="link link-primary"
              >
                Google Gemini
              </a>
              ·
              <a
                href="https://platform.openai.com/api-keys"
                target="_blank"
                rel="noopener"
                class="link link-primary"
              >
                OpenAI
              </a>
              ·
              <a
                href="https://console.anthropic.com/settings/keys"
                target="_blank"
                rel="noopener"
                class="link link-primary"
              >
                Claude
              </a>
            </li>
            <li>Cadastre o provedor em Configurações → Inteligência artificial</li>
          </ol>
        </div>
        <div class="modal-action">
          <.button type="button" variant="ghost" phx-click={@on_dismiss}>Fechar</.button>
          <.button navigate={~p"/users/settings"} variant="primary">Ir para Configurações</.button>
        </div>
      </div>
      <div class="modal-backdrop" phx-click={@on_dismiss}></div>
    </div>
    """
  end

  @doc """
  Cartão de escolha (tipo de importação, banco, extrato ou fatura). Use `phx-click` e
  `phx-value-*`; `selected` põe a borda na cor primária.
  """
  attr :selected, :boolean, default: false
  attr :disabled, :boolean, default: false
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :hint, :string, default: nil
  attr :rest, :global

  slot :leading

  def option_card(assigns) do
    ~H"""
    <button
      type="button"
      disabled={@disabled}
      aria-pressed={to_string(@selected)}
      class={["ui-option-card", @selected && "ui-option-card-selected"]}
      {@rest}
    >
      {render_slot(@leading)}
      <span class="min-w-0 text-left">
        <span class="ui-body block font-semibold">{@title}</span>
        <span :if={@description} class="ui-help block">{@description}</span>
        <span :if={@hint} class="ui-caption mt-1 block">{@hint}</span>
      </span>
    </button>
    """
  end
end
