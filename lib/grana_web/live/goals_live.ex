defmodule GranaWeb.GoalsLive do
  use GranaWeb, :live_view

  alias Grana.Banking
  alias Grana.Banking.FinancialGoal

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id
    categories = Banking.list_categories(user_id)

    {year, month} =
      case Banking.available_months(user_id) do
        [{y, m} | _] -> {y, m}
        [] -> {Date.utc_today().year, Date.utc_today().month}
      end

    socket =
      socket
      |> assign(:page_title, "Metas")
      |> assign(:categories, categories)
      |> assign(:show_form, false)
      |> assign(:editing_goal, nil)
      |> assign(:delete_target, nil)
      |> assign(:form_type, "expense_limit")
      |> assign(:form, to_form(FinancialGoal.changeset(%FinancialGoal{}, %{}), as: "goal"))
      |> load_goals(year, month)

    {:ok, socket}
  end

  defp load_goals(socket, year, month) do
    user_id = socket.assigns.current_scope.user.id
    progress = Banking.goals_progress(user_id, year, month)
    suggestions = Banking.suggest_goals(user_id)

    socket
    |> assign(:goals_progress, progress)
    |> assign(:suggestions, suggestions)
    |> assign(:year, year)
    |> assign(:month, month)
  end

  # ── Events ──

  @impl true
  def handle_event("show_form", _params, socket) do
    changeset = FinancialGoal.changeset(%FinancialGoal{}, %{})

    {:noreply,
     assign(socket,
       show_form: true,
       editing_goal: nil,
       form_type: "expense_limit",
       form: to_form(changeset, as: "goal")
     )}
  end

  def handle_event("hide_form", _params, socket) do
    {:noreply, assign(socket, show_form: false, editing_goal: nil)}
  end

  def handle_event("select_type", %{"goal" => %{"type" => type}}, socket) do
    {:noreply, assign(socket, :form_type, type)}
  end

  def handle_event("edit_goal", %{"id" => id}, socket) do
    user_id = socket.assigns.current_scope.user.id
    goal = Banking.get_financial_goal!(String.to_integer(id), user_id)
    changeset = FinancialGoal.changeset(goal, %{})

    {:noreply,
     assign(socket,
       show_form: true,
       editing_goal: goal,
       form_type: goal.type,
       form: to_form(changeset, as: "goal")
     )}
  end

  def handle_event("save_goal", %{"goal" => params}, socket) do
    user_id = socket.assigns.current_scope.user.id
    %{year: year, month: month} = socket.assigns

    params = Map.put(params, "user_id", user_id)

    result =
      case socket.assigns.editing_goal do
        nil -> Banking.create_financial_goal(params)
        goal -> Banking.update_financial_goal(goal, params)
      end

    case result do
      {:ok, _goal} ->
        socket =
          socket
          |> assign(:show_form, false)
          |> assign(:editing_goal, nil)
          |> load_goals(year, month)
          |> put_flash(:info, "Meta salva!")

        {:noreply, socket}

      {:error, changeset} ->
        if has_unique_error?(changeset) do
          {:noreply,
           socket
           |> assign(:show_form, false)
           |> assign(:editing_goal, nil)
           |> put_flash(:info, "Já existe uma meta ativa desse tipo.")}
        else
          {:noreply, assign(socket, form: to_form(changeset, as: "goal"))}
        end
    end
  end

  def handle_event("accept_suggestion", %{"type" => type, "amount" => amount}, socket) do
    user_id = socket.assigns.current_scope.user.id
    %{year: year, month: month} = socket.assigns

    case Banking.create_financial_goal(%{
           "type" => type,
           "target_value" => amount,
           "user_id" => user_id
         }) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_goals(year, month)
         |> put_flash(:info, "Meta criada!")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Erro ao criar meta. Verifique se já não existe uma meta desse tipo.")}
    end
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :delete_target, String.to_integer(id))}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :delete_target, nil)}
  end

  def handle_event("delete_goal", _params, socket) do
    user_id = socket.assigns.current_scope.user.id
    %{year: year, month: month, delete_target: id} = socket.assigns

    goal = Banking.get_financial_goal!(id, user_id)
    {:ok, _} = Banking.delete_financial_goal(goal)

    {:noreply,
     socket
     |> assign(:delete_target, nil)
     |> load_goals(year, month)
     |> put_flash(:info, "Meta removida")}
  end

  # ── Render ──

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-6xl mx-auto">
        <div class="flex items-center justify-between mb-4 sm:mb-8">
          <div>
            <h1 class="text-2xl sm:text-3xl font-bold tracking-tight">Metas</h1>
            <p class="text-xs sm:text-sm opacity-60 mt-1">Acompanhe seus objetivos financeiros</p>
          </div>
          <button phx-click="show_form" class="btn btn-primary btn-sm">
            <.icon name="hero-plus" class="size-4" /> Nova Meta
          </button>
        </div>

        <div :if={@goals_progress != []} class="flex items-center justify-center mb-6">
          <span class="badge badge-ghost text-xs">
            Referência: {month_name(@month)} {@year}
          </span>
        </div>

        <%!-- Suggestions --%>
        <div :if={@suggestions != [] and @goals_progress == []} class="mb-6 space-y-3">
          <h2 class="text-sm font-semibold opacity-60">Sugestões baseadas no seu histórico</h2>
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            <div :for={s <- @suggestions} class="card bg-base-200 p-4">
              <div class="flex items-center gap-2 mb-2">
                <.icon name={FinancialGoal.type_icon(s.type)} class="size-5 text-primary" />
                <span class="font-medium text-sm">{FinancialGoal.type_label(s.type)}</span>
              </div>
              <p class="text-xs opacity-60 mb-3">
                Média dos últimos 3 meses: {format_currency(s.avg)}
              </p>
              <% v90 = Decimal.round(Decimal.mult(s.avg, Decimal.from_float(0.9)), 0) %>
              <% v80 = Decimal.round(Decimal.mult(s.avg, Decimal.from_float(0.8)), 0) %>
              <div class="flex flex-wrap gap-2">
                <button
                  type="button"
                  phx-click="accept_suggestion"
                  phx-value-type={s.type}
                  phx-value-amount={Decimal.to_string(s.avg, :normal)}
                  class="btn btn-primary btn-xs"
                >
                  {format_currency(s.avg)}
                </button>
                <button
                  type="button"
                  phx-click="accept_suggestion"
                  phx-value-type={s.type}
                  phx-value-amount={Decimal.to_string(v90, :normal)}
                  class="btn btn-ghost btn-xs"
                >
                  {format_currency(v90)}
                </button>
                <button
                  type="button"
                  phx-click="accept_suggestion"
                  phx-value-type={s.type}
                  phx-value-amount={Decimal.to_string(v80, :normal)}
                  class="btn btn-ghost btn-xs"
                >
                  {format_currency(v80)}
                </button>
              </div>
            </div>
          </div>
        </div>

        <%!-- Active Goals --%>
        <div :if={@goals_progress != []} class="space-y-4">
          <div :for={gp <- @goals_progress} class="card bg-base-200 p-4 sm:p-6">
            <div class="flex items-center justify-between mb-3">
              <div class="flex items-center gap-2">
                <.icon
                  name={FinancialGoal.type_icon(gp.goal.type)}
                  class={"size-5 #{status_color(gp.status)}"}
                />
                <div>
                  <span class="font-semibold text-sm sm:text-base">
                    {FinancialGoal.type_label(gp.goal.type)}
                  </span>
                  <span
                    :if={gp.goal.category}
                    class="badge badge-sm ml-2"
                    style={"background-color: #{gp.goal.category.color}20; color: #{gp.goal.category.color}; border-color: #{gp.goal.category.color}40"}
                  >
                    {gp.goal.category.name}
                  </span>
                </div>
              </div>
              <div class="flex items-center gap-1">
                <button
                  phx-click="edit_goal"
                  phx-value-id={gp.goal.id}
                  class="btn btn-ghost btn-xs"
                >
                  <.icon name="hero-pencil" class="size-3.5" />
                </button>
                <button
                  phx-click="confirm_delete"
                  phx-value-id={gp.goal.id}
                  class="btn btn-ghost btn-xs text-error"
                >
                  <.icon name="hero-trash" class="size-3.5" />
                </button>
              </div>
            </div>

            <div class="flex items-end justify-between mb-2">
              <span class={"text-lg sm:text-xl font-bold #{status_color(gp.status)}"}>
                {format_currency(gp.current)}
              </span>
              <span class="text-sm opacity-60">
                / {format_currency(gp.target)}
              </span>
            </div>

            <div class="w-full bg-base-300 rounded-full h-3 mb-1">
              <div
                class={"h-3 rounded-full transition-all #{status_bg(gp.status)}"}
                style={"width: #{min(gp.pct, 100)}%"}
              />
            </div>

            <div class="flex justify-between text-xs opacity-60">
              <span>{status_label(gp.status)}</span>
              <span class={"font-medium #{status_color(gp.status)}"}>{gp.pct}%</span>
            </div>
          </div>
        </div>

        <%!-- Empty State --%>
        <div :if={@goals_progress == [] and @suggestions == []} class="text-center py-16">
          <.icon name="hero-flag" class="size-16 mx-auto mb-4 opacity-20" />
          <h2 class="text-lg font-semibold mb-2">Nenhuma meta definida</h2>
          <p class="opacity-60 mb-6 text-sm">
            Importe pelo menos 2 meses de extratos para receber sugestões automáticas
          </p>
          <button phx-click="show_form" class="btn btn-primary btn-sm">
            <.icon name="hero-plus" class="size-4" /> Criar Meta
          </button>
        </div>

        <%!-- New/Edit Modal --%>
        <dialog :if={@show_form} class="modal modal-open" phx-window-keydown="hide_form" phx-key="Escape">
          <div class="modal-box">
            <h3 class="text-lg font-bold mb-4">
              {if @editing_goal, do: "Editar Meta", else: "Nova Meta"}
            </h3>
            <.form for={@form} phx-submit="save_goal" class="space-y-4">
              <div :if={!@editing_goal}>
                <label class="label text-sm font-medium">Tipo</label>
                <select
                  name="goal[type]"
                  class="select select-bordered w-full"
                  phx-change="select_type"
                  value={@form_type}
                >
                  <option :for={t <- FinancialGoal.types()} value={t} selected={@form_type == t}>
                    {FinancialGoal.type_label(t)}
                  </option>
                </select>
              </div>
              <input :if={@editing_goal} type="hidden" name="goal[type]" value={@editing_goal.type} />

              <div :if={@form_type == "category_limit"}>
                <label class="label text-sm font-medium">Categoria</label>
                <select name="goal[category_id]" class="select select-bordered w-full">
                  <option :for={c <- Enum.filter(@categories, &(&1.kind == "expense"))} value={c.id}>
                    {c.name}
                  </option>
                </select>
              </div>

              <div>
                <label class="label text-sm font-medium">Valor alvo (R$)</label>
                <div id={"currency-input-#{if @editing_goal, do: @editing_goal.id, else: "new"}"} phx-hook="CurrencyInput" phx-update="ignore">
                  <input
                    type="hidden"
                    name="goal[target_value]"
                    value={if @editing_goal, do: @editing_goal.target_value, else: ""}
                  />
                  <input
                    type="text"
                    inputmode="numeric"
                    data-currency-display
                    class={"input input-bordered w-full #{if @form.errors[:target_value], do: "input-error"}"}
                    placeholder="Ex: 4.000,00"
                  />
                </div>
                <p :if={@form.errors[:target_value]} class="text-error text-xs mt-1">
                  {translate_error(@form.errors[:target_value])}
                </p>
              </div>

              <div class="modal-action">
                <button type="button" phx-click="hide_form" class="btn btn-ghost">Cancelar</button>
                <button type="submit" class="btn btn-primary">Salvar</button>
              </div>
            </.form>
          </div>
          <form method="dialog" class="modal-backdrop">
            <button phx-click="hide_form">close</button>
          </form>
        </dialog>

        <%!-- Delete Confirmation --%>
        <dialog :if={@delete_target} class="modal modal-open">
          <div class="modal-box">
            <h3 class="text-lg font-bold">Remover meta?</h3>
            <p class="py-4 opacity-70">Esta ação não pode ser desfeita.</p>
            <div class="modal-action">
              <button phx-click="cancel_delete" class="btn btn-ghost">Cancelar</button>
              <button phx-click="delete_goal" class="btn btn-error">Remover</button>
            </div>
          </div>
          <form method="dialog" class="modal-backdrop">
            <button phx-click="cancel_delete">close</button>
          </form>
        </dialog>
      </div>
    </Layouts.app>
    """
  end

  # ── Helpers ──

  defp has_unique_error?(%Ecto.Changeset{} = changeset) do
    Enum.any?(changeset.errors, fn {_field, {_msg, opts}} ->
      opts[:constraint] == :unique
    end)
  end

  defp format_currency(amount) do
    "R$ #{format_br_number(amount)}"
  end

  defp format_br_number(amount) do
    str = amount |> Decimal.round(2) |> Decimal.abs() |> Decimal.to_string(:normal)
    [int_part, dec_part] = String.split(str, ".")
    dec_part = String.pad_trailing(dec_part, 2, "0")

    int_formatted =
      int_part
      |> String.reverse()
      |> String.to_charlist()
      |> Enum.chunk_every(3)
      |> Enum.join(".")
      |> String.reverse()

    sign = if Decimal.compare(amount, 0) == :lt, do: "-", else: ""
    "#{sign}#{int_formatted},#{dec_part}"
  end

  defp month_name(1), do: "Janeiro"
  defp month_name(2), do: "Fevereiro"
  defp month_name(3), do: "Março"
  defp month_name(4), do: "Abril"
  defp month_name(5), do: "Maio"
  defp month_name(6), do: "Junho"
  defp month_name(7), do: "Julho"
  defp month_name(8), do: "Agosto"
  defp month_name(9), do: "Setembro"
  defp month_name(10), do: "Outubro"
  defp month_name(11), do: "Novembro"
  defp month_name(12), do: "Dezembro"

  defp status_color(:on_track), do: "text-success"
  defp status_color(:achieved), do: "text-success"
  defp status_color(:warning), do: "text-warning"
  defp status_color(:exceeded), do: "text-error"
  defp status_color(:behind), do: "text-error"
  defp status_color(_), do: ""

  defp status_bg(:on_track), do: "bg-success"
  defp status_bg(:achieved), do: "bg-success"
  defp status_bg(:warning), do: "bg-warning"
  defp status_bg(:exceeded), do: "bg-error"
  defp status_bg(:behind), do: "bg-error"
  defp status_bg(_), do: "bg-primary"

  defp status_label(:on_track), do: "No caminho certo"
  defp status_label(:achieved), do: "Meta atingida!"
  defp status_label(:warning), do: "Atenção"
  defp status_label(:exceeded), do: "Limite ultrapassado"
  defp status_label(:behind), do: "Abaixo da meta"
  defp status_label(_), do: ""
end
