defmodule GranaWeb.CategoriesLive do
  use GranaWeb, :live_view

  alias Grana.Banking
  alias Grana.Banking.Category
  alias GranaWeb.Layouts

  @available_icons [
    "hero-cake",
    "hero-truck",
    "hero-home",
    "hero-heart",
    "hero-musical-note",
    "hero-academic-cap",
    "hero-shopping-bag",
    "hero-arrows-right-left",
    "hero-chart-bar",
    "hero-credit-card",
    "hero-receipt-percent",
    "hero-banknotes",
    "hero-arrow-path",
    "hero-question-mark-circle",
    "hero-tag",
    "hero-gift",
    "hero-wrench",
    "hero-briefcase",
    "hero-building-storefront",
    "hero-phone",
    "hero-globe-alt",
    "hero-fire",
    "hero-bolt",
    "hero-star",
    "hero-sparkles",
    "hero-rocket-launch"
  ]

  @available_colors [
    "#F59E0B",
    "#3B82F6",
    "#8B5CF6",
    "#EF4444",
    "#EC4899",
    "#06B6D4",
    "#F97316",
    "#6366F1",
    "#10B981",
    "#64748B",
    "#22C55E",
    "#A855F7",
    "#9CA3AF",
    "#DC2626",
    "#0891B2",
    "#7C3AED",
    "#DB2777",
    "#059669",
    "#D97706",
    "#4F46E5"
  ]

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id
    categories = Banking.list_categories(user_id)
    stats = Banking.category_stats(user_id)

    socket =
      socket
      |> assign(:page_title, "Categorias")
      |> assign(:categories, categories)
      |> assign(:stats, stats)
      |> assign(:form_mode, nil)
      |> assign(:form, to_form(Category.changeset(%Category{}, %{}), as: "category"))
      |> assign(:form_icon, "hero-tag")
      |> assign(:form_color, "#6366F1")
      |> assign(:form_kind, "expense")
      |> assign(:delete_target, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"action" => "new"}, _uri, socket) do
    socket = new_category_form(socket)

    socket =
      if connected?(socket),
        do: push_patch(socket, to: ~p"/categories", replace: true),
        else: socket

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      import_queue={@import_queue}
      ai_notice={@ai_notice}
    >
      <div class="max-w-6xl mx-auto">
        <.page_header title="Categorias" subtitle="Gerencie as categorias de suas transações">
          <:actions>
            <.button
              id="new-category"
              type="button"
              variant="primary"
              size="sm"
              icon="hero-plus"
              phx-click="new_category"
            >
              Nova categoria
            </.button>
          </:actions>
        </.page_header>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <div :for={cat <- @categories} id={"category-#{cat.id}"} class="card bg-base-200 p-4">
            <div class="flex items-center gap-3 mb-3">
              <div
                class="w-10 h-10 rounded-full flex items-center justify-center shrink-0"
                style={"background-color: #{cat.color || "#9CA3AF"}20"}
              >
                <span class="flex" style={"color: #{cat.color || "#9CA3AF"}"}>
                  <.icon name={cat.icon || "hero-tag"} class="size-5" />
                </span>
              </div>
              <div class="flex-1 min-w-0">
                <h3 class="ui-body font-semibold truncate" title={cat.name}>{cat.name}</h3>
                <div class="ui-help flex gap-3">
                  <span>
                    {count_label(
                      get_stat(cat.id, @stats, :transaction_count),
                      "transação",
                      "transações"
                    )}
                  </span>
                  <span>{count_label(get_stat(cat.id, @stats, :rule_count), "regra", "regras")}</span>
                </div>
              </div>
              <.tag :if={cat.kind == "investment"} kind="neutro" class="shrink-0">
                <span class="size-1.5 rounded-full bg-(--ui-investimento)"></span> Investimento
              </.tag>
              <.tag :if={cat.kind == "income"} kind="neutro" class="shrink-0">
                <span class="size-1.5 rounded-full bg-(--ui-receita)"></span> Receita
              </.tag>
              <.tag :if={cat.is_system && cat.kind == "expense"} kind="neutro" class="shrink-0">
                Sistema
              </.tag>
            </div>
            <div class="flex gap-2 justify-end">
              <.button
                type="button"
                variant="ghost"
                size="sm"
                icon="hero-pencil"
                phx-click="edit_category"
                phx-value-id={cat.id}
              >
                Editar
              </.button>
              <.button
                :if={!cat.is_system}
                type="button"
                variant="ghost"
                size="sm"
                icon="hero-trash"
                class="text-error"
                phx-click="confirm_delete"
                phx-value-id={cat.id}
              >
                Remover
              </.button>
            </div>
          </div>
        </div>
      </div>

      <.form_modal
        :if={@form_mode}
        id="category_modal"
        title={if @form_mode == :new, do: "Nova categoria", else: "Editar categoria"}
        form={@form}
        form_id="category-form"
        on_submit="save_category"
        on_cancel={JS.push("cancel_form")}
        box_class="max-w-2xl"
      >
        <div class="flex flex-col gap-6">
          <.input
            field={@form[:name]}
            type="text"
            label="Nome"
            placeholder="Nome da categoria"
            autofocus
            phx-debounce="100"
            readonly={match?({:edit, %{is_system: true}}, @form_mode)}
          />

          <input type="hidden" name="category[icon]" value={@form_icon} />
          <input type="hidden" name="category[color]" value={@form_color} />
          <input type="hidden" name="category[kind]" value={@form_kind} />

          <div>
            <span class="ui-label">Ícone</span>
            <div class="category-icon-grid">
              <.button
                :for={icon <- available_icons()}
                type="button"
                variant={if(@form_icon == icon, do: "primary", else: "ghost")}
                size="sm"
                class="btn-square"
                aria-label={"Ícone " <> String.replace_prefix(icon, "hero-", "")}
                aria-pressed={to_string(@form_icon == icon)}
                phx-click="select_icon"
                phx-value-icon={icon}
              >
                <.icon name={icon} class="size-4" />
              </.button>
            </div>
          </div>

          <div>
            <span class="ui-label">Cor</span>
            <div class="category-color-grid">
              <button
                :for={color <- available_colors()}
                type="button"
                phx-click="select_color"
                phx-value-color={color}
                aria-label={"Cor #{color}"}
                class={[
                  "category-color-swatch rounded-full cursor-pointer border-2 transition-all",
                  if(@form_color == color,
                    do: "border-base-content scale-110",
                    else: "border-transparent"
                  )
                ]}
                style={"background-color: #{color}"}
              >
              </button>
            </div>
          </div>

          <div>
            <span class="ui-label">Tipo</span>
            <.chip_group>
              <.chip
                :for={
                  {value, label} <- [
                    {"expense", "Despesa"},
                    {"investment", "Investimento"},
                    {"income", "Receita"}
                  ]
                }
                active={@form_kind == value}
                phx-click="select_kind"
                phx-value-kind={value}
              >
                {label}
              </.chip>
            </.chip_group>
          </div>

          <div class="category-preview-panel ui-rounded-box flex items-center gap-3 bg-base-300">
            <div
              class="w-10 h-10 rounded-full flex items-center justify-center"
              style={"background-color: #{@form_color}20"}
            >
              <span class="flex" style={"color: #{@form_color}"}>
                <.icon name={@form_icon} class="size-5" />
              </span>
            </div>
            <span class="ui-body font-medium">
              {if @form[:name].value in [nil, ""], do: "Pré-visualização", else: @form[:name].value}
            </span>
          </div>
        </div>
      </.form_modal>

      <.confirm_modal
        :if={@delete_target}
        id="delete_modal"
        open
        title="Remover categoria"
        confirm="Remover"
        loading="Removendo…"
        on_confirm={JS.push("delete")}
        on_cancel={JS.push("cancel_delete")}
      >
        <p>
          Tem certeza que deseja remover a categoria <span class="font-semibold">{@delete_target.name}</span>?
        </p>
        <p
          :if={get_stat(@delete_target.id, @stats, :transaction_count) > 0}
          class="ui-help mt-2"
        >
          {count_label(
            get_stat(@delete_target.id, @stats, :transaction_count),
            "transação ficará",
            "transações ficarão"
          )} sem categoria.
        </p>
        <p :if={get_stat(@delete_target.id, @stats, :rule_count) > 0} class="ui-help mt-2">
          {count_label(
            get_stat(@delete_target.id, @stats, :rule_count),
            "regra será removida",
            "regras serão removidas"
          )}.
        </p>
      </.confirm_modal>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("new_category", _params, socket) do
    {:noreply, new_category_form(socket)}
  end

  def handle_event("edit_category", %{"id" => id}, socket) do
    user_id = socket.assigns.current_scope.user.id
    category = Banking.get_category!(GranaWeb.Params.to_int(id, -1), user_id)
    changeset = Category.changeset(category, %{})

    {:noreply,
     assign(socket,
       form_mode: {:edit, category},
       form: to_form(changeset, as: "category"),
       form_icon: category.icon || "hero-tag",
       form_color: category.color || "#6366F1",
       form_kind: category.kind || "expense"
     )}
  end

  def handle_event("cancel_form", _params, socket) do
    {:noreply, assign(socket, :form_mode, nil)}
  end

  def handle_event("select_icon", %{"icon" => icon}, socket) do
    {:noreply, assign(socket, :form_icon, icon)}
  end

  def handle_event("select_color", %{"color" => color}, socket) do
    {:noreply, assign(socket, :form_color, color)}
  end

  def handle_event("select_kind", %{"kind" => kind}, socket) do
    {:noreply, assign(socket, :form_kind, kind)}
  end

  def handle_event("save_category", %{"category" => params}, socket) do
    user_id = socket.assigns.current_scope.user.id
    attrs = Map.put(params, "user_id", user_id)

    result =
      case socket.assigns.form_mode do
        :new -> Banking.create_category(attrs)
        {:edit, category} -> Banking.update_category(category, attrs)
      end

    case result do
      {:ok, _} ->
        categories = Banking.list_categories(user_id)
        stats = Banking.category_stats(user_id)

        msg =
          if socket.assigns.form_mode == :new,
            do: "Categoria criada.",
            else: "Categoria atualizada."

        socket =
          socket
          |> assign(:categories, categories)
          |> assign(:stats, stats)
          |> assign(:form_mode, nil)
          |> put_flash(:info, msg)

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "category"))}
    end
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    user_id = socket.assigns.current_scope.user.id
    category = Banking.get_category!(GranaWeb.Params.to_int(id, -1), user_id)
    {:noreply, assign(socket, :delete_target, category)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :delete_target, nil)}
  end

  def handle_event("delete", _params, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Banking.delete_category(socket.assigns.delete_target) do
      {:ok, _} ->
        categories = Banking.list_categories(user_id)
        stats = Banking.category_stats(user_id)

        socket =
          socket
          |> assign(:categories, categories)
          |> assign(:stats, stats)
          |> assign(:delete_target, nil)
          |> put_flash(:info, "Categoria removida.")

        {:noreply, socket}

      {:error, :system_category} ->
        socket =
          socket
          |> assign(:delete_target, nil)
          |> put_flash(:error, "Categorias do sistema não podem ser removidas.")

        {:noreply, socket}
    end
  end

  defp available_icons, do: @available_icons
  defp available_colors, do: @available_colors

  defp get_stat(category_id, stats, key) do
    case Map.get(stats, category_id) do
      nil -> 0
      s -> Map.get(s, key, 0)
    end
  end

  defp new_category_form(socket) do
    changeset = Category.changeset(%Category{}, %{})

    assign(socket,
      form_mode: :new,
      form: to_form(changeset, as: "category"),
      form_icon: "hero-tag",
      form_color: "#6366F1",
      form_kind: "expense"
    )
  end
end
