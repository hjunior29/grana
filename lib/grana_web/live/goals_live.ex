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
    goal = Banking.get_financial_goal!(GranaWeb.Params.to_int(id, -1), user_id)
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
          |> put_flash(:info, "Meta salva.")

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
         |> put_flash(:info, "Meta criada.")}

      {:error, _changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Erro ao criar meta. Verifique se já não existe uma meta desse tipo."
         )}
    end
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :delete_target, GranaWeb.Params.to_int(id, -1))}
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
     |> put_flash(:info, "Meta removida.")}
  end

  # ── Render ──

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      import_queue={@import_queue}
      chat_notice={@chat_notice}
    >
      <div class="max-w-6xl mx-auto">
        <.page_header title="Metas" subtitle="Acompanhe seus objetivos financeiros">
          <:actions>
            <.button
              id="new-goal"
              type="button"
              variant="primary"
              size="sm"
              icon="hero-plus"
              phx-click="show_form"
            >
              Nova meta
            </.button>
          </:actions>
        </.page_header>

        <div :if={@goals_progress != []} class="flex items-center justify-center mb-6">
          <.tag kind="neutro">Referência: {month_name(@month)} {@year}</.tag>
        </div>

        <%!-- Suggestions --%>
        <% suggestions =
          Enum.reject(
            @suggestions,
            &(&1.type in Enum.map(@goals_progress, fn gp -> gp.goal.type end))
          ) %>
        <div :if={suggestions != []} class="mb-6 space-y-3">
          <h2 class="ui-section-title">Sugestões baseadas no seu histórico</h2>
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            <div :for={s <- suggestions} class="card bg-base-200 p-4">
              <div class="flex items-center gap-2 mb-2">
                <.icon name={FinancialGoal.type_icon(s.type)} class="size-5 text-primary" />
                <span class="ui-body font-medium">{FinancialGoal.type_label(s.type)}</span>
              </div>
              <p class="ui-help mb-3">
                Média dos últimos 3 meses: <span class="ui-private">{format_currency(s.avg)}</span>
              </p>
              <% v90 = Decimal.round(Decimal.mult(s.avg, Decimal.from_float(0.9)), 0) %>
              <% v80 = Decimal.round(Decimal.mult(s.avg, Decimal.from_float(0.8)), 0) %>
              <div class="flex flex-wrap gap-2">
                <.button
                  type="button"
                  variant="primary"
                  size="sm"
                  phx-click="accept_suggestion"
                  phx-value-type={s.type}
                  phx-value-amount={Decimal.to_string(s.avg, :normal)}
                >
                  <span class="ui-private">{format_currency(s.avg)}</span>
                </.button>
                <.button
                  type="button"
                  variant="ghost"
                  size="sm"
                  phx-click="accept_suggestion"
                  phx-value-type={s.type}
                  phx-value-amount={Decimal.to_string(v90, :normal)}
                >
                  <span class="ui-private">{format_currency(v90)}</span>
                </.button>
                <.button
                  type="button"
                  variant="ghost"
                  size="sm"
                  phx-click="accept_suggestion"
                  phx-value-type={s.type}
                  phx-value-amount={Decimal.to_string(v80, :normal)}
                >
                  <span class="ui-private">{format_currency(v80)}</span>
                </.button>
              </div>
            </div>
          </div>
        </div>

        <%!-- Active Goals --%>
        <div :if={@goals_progress != []} class="space-y-4">
          <div
            :for={gp <- @goals_progress}
            id={"goal-#{gp.goal.id}"}
            class="card bg-base-200 p-4 sm:p-6"
          >
            <div class="flex items-center justify-between mb-3">
              <div class="flex items-center gap-2">
                <.icon
                  name={FinancialGoal.type_icon(gp.goal.type)}
                  class={"size-5 #{status_color(gp.status)}"}
                />
                <div>
                  <span class="ui-body font-semibold">
                    {FinancialGoal.type_label(gp.goal.type)}
                  </span>
                  <.category_icon
                    :if={gp.goal.category}
                    category={gp.goal.category}
                    class="size-5 ml-2"
                  />
                </div>
              </div>
              <div class="flex items-center gap-1">
                <.button
                  type="button"
                  variant="ghost"
                  size="sm"
                  icon="hero-pencil"
                  class="btn-square"
                  aria-label="Editar meta"
                  phx-click="edit_goal"
                  phx-value-id={gp.goal.id}
                >
                  <span class="sr-only">Editar meta</span>
                </.button>
                <.button
                  type="button"
                  variant="ghost"
                  size="sm"
                  icon="hero-trash"
                  class="btn-square text-error"
                  aria-label="Remover meta"
                  phx-click="confirm_delete"
                  phx-value-id={gp.goal.id}
                >
                  <span class="sr-only">Remover meta</span>
                </.button>
              </div>
            </div>

            <div class="flex items-end justify-between mb-2">
              <span class={"ui-private text-lg sm:text-xl font-bold #{status_color(gp.status)}"}>
                {format_currency(gp.current)}
              </span>
              <span class="ui-body ui-text-secondary">
                / <span class="ui-private">{format_currency(gp.target)}</span>
              </span>
            </div>

            <div class="w-full bg-base-300 rounded-full h-3 mb-1">
              <div
                class={"h-3 rounded-full transition-all #{status_bg(gp.status)}"}
                style={"width: #{min(gp.pct, 100)}%"}
              />
            </div>

            <div class="ui-help flex justify-between">
              <span>{status_label(gp.status)}</span>
              <span class={"font-medium #{status_color(gp.status)}"}>{format_pct(gp.pct)}</span>
            </div>
          </div>
        </div>

        <%!-- Empty State --%>
        <.empty_state
          :if={@goals_progress == [] and @suggestions == []}
          id="goals-empty"
          icon="hero-flag"
          title="Nenhuma meta definida"
          text="Importe pelo menos 2 meses de extratos para receber sugestões automáticas."
        >
          <:action>
            <.button
              type="button"
              variant="primary"
              size="sm"
              icon="hero-plus"
              phx-click="show_form"
            >
              Criar meta
            </.button>
          </:action>
        </.empty_state>

        <.form_modal
          :if={@show_form}
          id="goal_modal"
          title={if @editing_goal, do: "Editar meta", else: "Nova meta"}
          form={@form}
          form_id="goal-form"
          on_submit="save_goal"
          on_cancel={JS.push("hide_form")}
        >
          <div class="flex flex-col gap-4">
            <.input
              :if={!@editing_goal}
              id="goal_type"
              type="select"
              name="goal[type]"
              label="Tipo"
              value={@form_type}
              options={Enum.map(FinancialGoal.types(), &{FinancialGoal.type_label(&1), &1})}
              phx-change="select_type"
            />
            <input :if={@editing_goal} type="hidden" name="goal[type]" value={@editing_goal.type} />

            <.input
              :if={@form_type == "category_limit"}
              id="goal_category_id"
              type="select"
              name="goal[category_id]"
              label="Categoria"
              value={nil}
              options={for c <- Enum.filter(@categories, &(&1.kind == "expense")), do: {c.name, c.id}}
            />

            <div>
              <label for="goal-target-display" class="ui-label">Valor alvo (R$)</label>
              <div
                id={"currency-input-#{if @editing_goal, do: @editing_goal.id, else: "new"}"}
                phx-hook="CurrencyInput"
                phx-update="ignore"
              >
                <input
                  type="hidden"
                  name="goal[target_value]"
                  value={if @editing_goal, do: @editing_goal.target_value, else: ""}
                />
                <input
                  id="goal-target-display"
                  type="text"
                  inputmode="decimal"
                  autocomplete="off"
                  data-currency-display
                  class={[
                    "ui-private-input input w-full",
                    @form.errors[:target_value] && "input-error"
                  ]}
                  placeholder="Ex: 4000 ou 4.000,50"
                />
              </div>
              <p :if={@form.errors[:target_value]} class="ui-body mt-1 text-error">
                {translate_error(@form.errors[:target_value])}
              </p>
            </div>
          </div>
        </.form_modal>

        <.confirm_modal
          :if={@delete_target}
          id="delete-goal-modal"
          open
          title="Remover meta?"
          confirm="Remover"
          loading="Removendo…"
          on_confirm={JS.push("delete_goal")}
          on_cancel={JS.push("cancel_delete")}
        >
          Remover {delete_goal_label(@goals_progress, @delete_target)}? Esta ação não pode ser desfeita.
        </.confirm_modal>
      </div>
    </Layouts.app>
    """
  end

  # ── Helpers ──

  defp delete_goal_label(goals_progress, id) do
    case Enum.find(goals_progress, &(&1.goal.id == id)) do
      nil -> "esta meta"
      gp -> "“" <> FinancialGoal.type_label(gp.goal.type) <> "”"
    end
  end

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

  defp status_color(:on_track), do: "ui-money-receita"
  defp status_color(:achieved), do: "ui-money-receita"
  defp status_color(:warning), do: "text-warning"
  defp status_color(:exceeded), do: "ui-money-despesa"
  defp status_color(:behind), do: "ui-money-despesa"
  defp status_color(_), do: ""

  defp status_bg(:on_track), do: "bg-(--ui-receita)"
  defp status_bg(:achieved), do: "bg-(--ui-receita)"
  defp status_bg(:warning), do: "bg-warning"
  defp status_bg(:exceeded), do: "bg-(--ui-despesa)"
  defp status_bg(:behind), do: "bg-(--ui-despesa)"
  defp status_bg(_), do: "bg-primary"

  defp status_label(:on_track), do: "No caminho certo"
  defp status_label(:achieved), do: "Meta atingida"
  defp status_label(:warning), do: "Atenção"
  defp status_label(:exceeded), do: "Limite ultrapassado"
  defp status_label(:behind), do: "Abaixo da meta"
  defp status_label(_), do: ""
end
