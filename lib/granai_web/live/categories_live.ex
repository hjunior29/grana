defmodule GranaiWeb.CategoriesLive do
  use GranaiWeb, :live_view

  alias Granai.Banking
  alias GranaiWeb.Layouts

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
      |> assign(:form, new_form())
      |> assign(:delete_target, nil)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-6xl mx-auto">
        <div class="mb-4 sm:mb-8 flex flex-col sm:flex-row items-center sm:justify-between gap-3">
          <div class="text-center sm:text-left">
            <h1 class="text-2xl sm:text-3xl font-bold tracking-tight">Categorias</h1>
            <p class="text-xs sm:text-sm opacity-60 mt-1">
              Gerencie as categorias de suas transações
            </p>
          </div>
          <button phx-click="new_category" class="btn btn-primary btn-sm">
            <.icon name="hero-plus" class="size-4" /> Nova Categoria
          </button>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <div :for={cat <- @categories} class="card bg-base-200 p-4">
            <div class="flex items-center gap-3 mb-3">
              <div
                class="w-10 h-10 rounded-full flex items-center justify-center shrink-0"
                style={"background-color: #{cat.color || "#9CA3AF"}20"}
              >
                <span style={"color: #{cat.color || "#9CA3AF"}"}>
                  <.icon name={cat.icon || "hero-tag"} class="size-5" />
                </span>
              </div>
              <div class="flex-1 min-w-0">
                <h3 class="font-semibold truncate">{cat.name}</h3>
                <div class="flex gap-3 text-xs opacity-60">
                  <span>{get_stat(cat.id, @stats, :transaction_count)} transações</span>
                  <span>{get_stat(cat.id, @stats, :rule_count)} regras</span>
                </div>
              </div>
              <div :if={cat.kind == "investment"} class="badge badge-sm badge-info shrink-0">
                Investimento
              </div>
              <div :if={cat.kind == "income"} class="badge badge-sm badge-success shrink-0">
                Receita
              </div>
              <div
                :if={cat.is_system && cat.kind == "expense"}
                class="badge badge-sm badge-ghost shrink-0"
              >
                Sistema
              </div>
            </div>
            <div class="flex gap-2 justify-end">
              <button
                phx-click="edit_category"
                phx-value-id={cat.id}
                class="btn btn-ghost btn-xs"
              >
                <.icon name="hero-pencil" class="size-3" /> Editar
              </button>
              <button
                :if={!cat.is_system}
                phx-click="confirm_delete"
                phx-value-id={cat.id}
                class="btn btn-ghost btn-xs text-error"
              >
                <.icon name="hero-trash" class="size-3" /> Remover
              </button>
            </div>
          </div>
        </div>
      </div>

      <%!-- Create/Edit Modal --%>
      <dialog
        :if={@form_mode}
        id="category_modal"
        class="modal modal-open"
        phx-window-keydown="cancel_form"
        phx-key="Escape"
      >
        <div class="modal-box max-w-lg">
          <h3 class="text-lg font-bold mb-4">
            {if @form_mode == :new, do: "Nova Categoria", else: "Editar Categoria"}
          </h3>
          <form phx-submit="save_category" phx-change="update_form">
            <div class="form-control mb-4">
              <label class="label"><span class="label-text">Nome</span></label>
              <input
                type="text"
                name="name"
                value={@form["name"]}
                class="input input-bordered w-full"
                required
                placeholder="Nome da categoria"
                autofocus
                phx-debounce="100"
              />
            </div>

            <div class="form-control mb-4">
              <label class="label"><span class="label-text">Ícone</span></label>
              <div class="flex flex-wrap gap-2">
                <button
                  :for={icon <- available_icons()}
                  type="button"
                  phx-click="select_icon"
                  phx-value-icon={icon}
                  class={[
                    "btn btn-sm btn-square",
                    if(@form["icon"] == icon, do: "btn-primary", else: "btn-ghost")
                  ]}
                >
                  <.icon name={icon} class="size-4" />
                </button>
              </div>
            </div>

            <div class="form-control mb-4">
              <label class="label"><span class="label-text">Cor</span></label>
              <div class="flex flex-wrap gap-2">
                <button
                  :for={color <- available_colors()}
                  type="button"
                  phx-click="select_color"
                  phx-value-color={color}
                  class={[
                    "w-8 h-8 rounded-full cursor-pointer border-2 transition-all",
                    if(@form["color"] == color,
                      do: "border-base-content scale-110",
                      else: "border-transparent"
                    )
                  ]}
                  style={"background-color: #{color}"}
                >
                </button>
              </div>
            </div>

            <div class="form-control mb-4">
              <label class="label"><span class="label-text">Tipo</span></label>
              <div class="flex gap-2">
                <button
                  :for={
                    {value, label} <- [
                      {"expense", "Despesa"},
                      {"investment", "Investimento"},
                      {"income", "Receita"}
                    ]
                  }
                  type="button"
                  phx-click="select_kind"
                  phx-value-kind={value}
                  class={[
                    "btn btn-sm flex-1",
                    cond do
                      @form["kind"] == value && value == "expense" -> "btn-error"
                      @form["kind"] == value && value == "investment" -> "btn-info"
                      @form["kind"] == value && value == "income" -> "btn-success"
                      true -> "btn-ghost"
                    end
                  ]}
                >
                  {label}
                </button>
              </div>
              <label class="label">
                <span class="label-text-alt opacity-50">
                  {case @form["kind"] do
                    "investment" -> "Excluída dos gastos no dashboard"
                    "income" -> "Contabilizada como receita"
                    _ -> "Contabilizada como gasto"
                  end}
                </span>
              </label>
            </div>

            <div class="flex items-center gap-3 p-3 bg-base-300 rounded-lg mb-4">
              <div
                class="w-10 h-10 rounded-full flex items-center justify-center"
                style={"background-color: #{@form["color"]}20"}
              >
                <span style={"color: #{@form["color"]}"}>
                  <.icon name={@form["icon"]} class="size-5" />
                </span>
              </div>
              <span class="font-medium">
                {if @form["name"] == "", do: "Pré-visualização", else: @form["name"]}
              </span>
            </div>

            <div class="modal-action">
              <button type="button" phx-click="cancel_form" class="btn btn-ghost">
                Cancelar
              </button>
              <button type="submit" class="btn btn-primary">Salvar</button>
            </div>
          </form>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button type="button" phx-click="cancel_form">close</button>
        </form>
      </dialog>

      <%!-- Delete Confirmation Modal --%>
      <dialog
        :if={@delete_target}
        id="delete_modal"
        class="modal modal-open"
        phx-window-keydown="cancel_delete"
        phx-key="Escape"
      >
        <div class="modal-box">
          <h3 class="text-lg font-bold">Remover categoria</h3>
          <p class="py-4 opacity-70">
            Tem certeza que deseja remover a categoria <span class="font-semibold">{@delete_target.name}</span>?
          </p>
          <p
            :if={get_stat(@delete_target.id, @stats, :transaction_count) > 0}
            class="text-sm opacity-60 mb-2"
          >
            {get_stat(@delete_target.id, @stats, :transaction_count)} transações ficarão sem categoria.
          </p>
          <p
            :if={get_stat(@delete_target.id, @stats, :rule_count) > 0}
            class="text-sm opacity-60 mb-2"
          >
            {get_stat(@delete_target.id, @stats, :rule_count)} regras serão removidas.
          </p>
          <div class="modal-action">
            <button phx-click="cancel_delete" class="btn btn-ghost">Cancelar</button>
            <button phx-click="delete" class="btn btn-error">Remover</button>
          </div>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button type="button" phx-click="cancel_delete">close</button>
        </form>
      </dialog>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("new_category", _params, socket) do
    socket =
      socket
      |> assign(:form_mode, :new)
      |> assign(:form, new_form())

    {:noreply, socket}
  end

  def handle_event("edit_category", %{"id" => id}, socket) do
    category = Banking.get_category!(String.to_integer(id))

    socket =
      socket
      |> assign(:form_mode, {:edit, category})
      |> assign(:form, %{
        "name" => category.name,
        "icon" => category.icon || "hero-tag",
        "color" => category.color || "#6366F1",
        "kind" => category.kind || "expense"
      })

    {:noreply, socket}
  end

  def handle_event("cancel_form", _params, socket) do
    {:noreply, assign(socket, :form_mode, nil)}
  end

  def handle_event("update_form", %{"name" => name}, socket) do
    {:noreply, assign(socket, :form, Map.put(socket.assigns.form, "name", name))}
  end

  def handle_event("select_icon", %{"icon" => icon}, socket) do
    {:noreply, assign(socket, :form, Map.put(socket.assigns.form, "icon", icon))}
  end

  def handle_event("select_color", %{"color" => color}, socket) do
    {:noreply, assign(socket, :form, Map.put(socket.assigns.form, "color", color))}
  end

  def handle_event("select_kind", %{"kind" => kind}, socket) do
    {:noreply, assign(socket, :form, Map.put(socket.assigns.form, "kind", kind))}
  end

  def handle_event("save_category", %{"name" => name}, socket) do
    user_id = socket.assigns.current_scope.user.id
    form = socket.assigns.form

    attrs = %{
      name: String.trim(name),
      icon: form["icon"],
      color: form["color"],
      kind: form["kind"],
      user_id: user_id
    }

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
            do: "Categoria criada!",
            else: "Categoria atualizada!"

        socket =
          socket
          |> assign(:categories, categories)
          |> assign(:stats, stats)
          |> assign(:form_mode, nil)
          |> put_flash(:info, msg)

        {:noreply, socket}

      {:error, changeset} ->
        msg =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
          |> Enum.map_join("; ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)

        {:noreply, put_flash(socket, :error, msg)}
    end
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    category = Banking.get_category!(String.to_integer(id))
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
          |> put_flash(:info, "Categoria removida")

        {:noreply, socket}

      {:error, :system_category} ->
        socket =
          socket
          |> assign(:delete_target, nil)
          |> put_flash(:error, "Categorias do sistema não podem ser removidas")

        {:noreply, socket}
    end
  end

  defp new_form do
    %{"name" => "", "icon" => "hero-tag", "color" => "#6366F1", "kind" => "expense"}
  end

  defp available_icons, do: @available_icons
  defp available_colors, do: @available_colors

  defp get_stat(category_id, stats, key) do
    case Map.get(stats, category_id) do
      nil -> 0
      s -> Map.get(s, key, 0)
    end
  end
end
