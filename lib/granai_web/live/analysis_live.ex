defmodule GranaiWeb.AnalysisLive do
  use GranaiWeb, :live_view

  alias Granai.Banking
  alias Granai.Banking.AIAnalyzer

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id
    categories = Banking.ensure_default_categories(user_id)
    banks = Banking.available_banks(user_id)
    years = Banking.available_years(user_id)
    months = Banking.available_months(user_id)
    analyses = Banking.list_ai_analyses(user_id)

    current_year =
      case years do
        [y | _] -> y
        [] -> Date.utc_today().year
      end

    socket =
      socket
      |> assign(:page_title, "Análise")
      |> assign(:categories, categories)
      |> assign(:banks, banks)
      |> assign(:available_years, years)
      |> assign(:available_months, months)
      |> assign(:analyses, analyses)
      |> assign(:loading, false)
      |> assign(:show_api_key_alert, false)
      |> assign(:filters, %{
        year: current_year,
        month: 0,
        bank: "all",
        type: "all"
      })
      |> assign(:granaim_prompt, "")
      |> assign(:delete_target, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("update_filters", params, socket) do
    filters = %{
      year: parse_int(params["year"], socket.assigns.filters.year),
      month: parse_int(params["month"], 0),
      bank: params["bank"] || "all",
      type: params["type"] || "all"
    }

    {:noreply, assign(socket, :filters, filters)}
  end

  def handle_event("update_prompt", %{"prompt" => prompt}, socket) do
    {:noreply, assign(socket, :granaim_prompt, prompt)}
  end

  def handle_event("analyze", _params, socket) do
    %{current_scope: scope, filters: filters, granaim_prompt: prompt} = socket.assigns

    case Granai.Accounts.get_user_ai_config(scope.user.id) do
      {:error, :no_api_key} ->
        {:noreply, assign(socket, :show_api_key_alert, true)}

      {:ok, _config} ->
        socket = assign(socket, :loading, true)

        Task.async(fn ->
          granaim = case prompt do
            "" -> nil
            p -> p
          end

          AIAnalyzer.analyze_with_filters(scope.user.id, filters, granaim)
        end)

        {:noreply, socket}
    end
  end

  def handle_event("dismiss_api_alert", _params, socket) do
    {:noreply, assign(socket, :show_api_key_alert, false)}
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :delete_target, String.to_integer(id))}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :delete_target, nil)}
  end

  def handle_event("delete_analysis", _params, socket) do
    case socket.assigns.delete_target do
      nil ->
        {:noreply, socket}

      id ->
        analysis = Banking.get_ai_analysis!(id)
        {:ok, _} = Banking.delete_ai_analysis(analysis)
        analyses = Banking.list_ai_analyses(socket.assigns.current_scope.user.id)

        socket =
          socket
          |> assign(:analyses, analyses)
          |> assign(:delete_target, nil)
          |> put_flash(:info, "Análise removida")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({ref, result}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    socket =
      case result do
        {:ok, analysis_result} ->
          user_id = socket.assigns.current_scope.user.id

          Banking.create_ai_analysis(%{
            user_id: user_id,
            prompt: socket.assigns.granaim_prompt,
            filters_json: socket.assigns.filters,
            result_json: analysis_result
          })

          analyses = Banking.list_ai_analyses(user_id)

          socket
          |> assign(:analyses, analyses)
          |> assign(:loading, false)
          |> put_flash(:info, "Análise concluída!")

        {:error, msg} ->
          socket
          |> assign(:loading, false)
          |> put_flash(:error, "Erro na análise: #{msg}")
      end

    {:noreply, socket}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, assign(socket, :loading, false)}
  end

  defp parse_int(nil, default), do: default
  defp parse_int(val, _default) when is_integer(val), do: val

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      _ -> default
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-6xl mx-auto">
        <div class="mb-8">
          <h1 class="text-3xl font-bold tracking-tight">Análise</h1>
          <p class="text-sm opacity-60 mt-1">Obtenha insights inteligentes sobre suas finanças</p>
        </div>

        <div class="card bg-base-200 p-6 mb-8">
          <h3 class="font-semibold mb-4">Configurar Análise</h3>
          <form phx-change="update_filters" phx-submit="analyze">
            <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-4">
              <div>
                <label class="text-xs opacity-50 mb-1 block">Ano</label>
                <select name="year" class="select select-bordered select-sm w-full">
                  <option
                    :for={y <- @available_years}
                    value={y}
                    selected={@filters.year == y}
                  >
                    {y}
                  </option>
                </select>
              </div>
              <div>
                <label class="text-xs opacity-50 mb-1 block">Mês</label>
                <select name="month" class="select select-bordered select-sm w-full">
                  <option value="0" selected={@filters.month == 0}>Ano todo</option>
                  <option
                    :for={m <- 1..12}
                    value={m}
                    selected={@filters.month == m}
                  >
                    {Banking.month_name(m)}
                  </option>
                </select>
              </div>
              <div>
                <label class="text-xs opacity-50 mb-1 block">Banco</label>
                <select name="bank" class="select select-bordered select-sm w-full">
                  <option value="all" selected={@filters.bank == "all"}>Todos</option>
                  <option :for={b <- @banks} value={b} selected={@filters.bank == b}>
                    {String.capitalize(b)}
                  </option>
                </select>
              </div>
              <div>
                <label class="text-xs opacity-50 mb-1 block">Tipo</label>
                <select name="type" class="select select-bordered select-sm w-full">
                  <option value="all" selected={@filters.type == "all"}>Todos</option>
                  <option value="debit" selected={@filters.type == "debit"}>Despesas</option>
                  <option value="credit" selected={@filters.type == "credit"}>Receitas</option>
                </select>
              </div>
            </div>

            <div class="mb-4">
              <label class="text-xs opacity-50 mb-1 block">Prompt personalizado (opcional)</label>
              <textarea
                name="prompt"
                phx-change="update_prompt"
                phx-debounce="300"
                value={@granaim_prompt}
                placeholder="Ex: Foque em oportunidades de economia, analise padrões de gastos com alimentação..."
                class="textarea textarea-bordered w-full"
                rows="2"
              />
            </div>

            <button
              type="submit"
              class="btn btn-primary gap-2"
              disabled={@loading}
            >
              <.icon :if={!@loading} name="hero-sparkles" class="size-4" />
              {if @loading, do: "Analisando...", else: "Analisar"}
            </button>
          </form>
        </div>

        <div class="mb-4">
          <h3 class="font-semibold text-lg">Histórico de Análises</h3>
          <p class="text-sm opacity-50">Suas análises anteriores ficam salvas aqui</p>
        </div>

        <div :if={@loading} class="card bg-base-200 p-6 mb-8">
          <div class="flex items-center gap-3">
            <span class="loading loading-spinner loading-sm text-primary" />
            <span class="text-sm opacity-60">Analisando seus dados com IA...</span>
          </div>
        </div>

        <div :if={@analyses == []} class="text-center py-16">
          <.icon name="hero-sparkles" class="size-16 mx-auto mb-4 opacity-20" />
          <h2 class="text-xl font-semibold mb-2">Nenhuma análise encontrada</h2>
          <p class="opacity-60 mb-6">Filtre os dados e faça uma análise</p>
        </div>

        <div class="space-y-4">
          <div :for={analysis <- @analyses} class="card bg-gradient-to-br from-primary/5 to-secondary/5 border border-primary/10 p-6">
            <div class="flex items-start justify-between mb-4">
              <div>
                <div class="flex items-center gap-2 mb-1">
                  <.icon name="hero-sparkles" class="size-4 text-primary" />
                  <span class="font-semibold text-sm">
                    {format_datetime_br(analysis.inserted_at)}
                  </span>
                </div>
                <div class="flex flex-wrap gap-1">
                  <span :if={analysis.filters_json["year"]} class="badge badge-xs badge-ghost">
                    {analysis.filters_json["year"]}
                  </span>
                  <span :if={analysis.filters_json["month"] && analysis.filters_json["month"] != 0} class="badge badge-xs badge-ghost">
                    {Banking.month_name(analysis.filters_json["month"])}
                  </span>
                  <span :if={analysis.filters_json["month"] == 0} class="badge badge-xs badge-ghost">
                    Ano todo
                  </span>
                  <span :if={analysis.filters_json["bank"] && analysis.filters_json["bank"] != "all"} class="badge badge-xs badge-ghost">
                    {String.capitalize(analysis.filters_json["bank"])}
                  </span>
                  <span :if={analysis.filters_json["type"] && analysis.filters_json["type"] != "all"} class="badge badge-xs badge-ghost">
                    {type_label(analysis.filters_json["type"])}
                  </span>
                </div>
                <p :if={analysis.prompt && analysis.prompt != ""} class="text-xs opacity-40 mt-1 italic">
                  "{analysis.prompt}"
                </p>
              </div>
              <button
                phx-click="confirm_delete"
                phx-value-id={analysis.id}
                class="btn btn-ghost btn-xs text-error"
              >
                <.icon name="hero-trash" class="size-4" />
              </button>
            </div>

            <p class="text-sm mb-4 font-medium">{analysis.result_json["resumo"]}</p>

            <div class="space-y-2 mb-4">
              <div
                :for={insight <- analysis.result_json["insights"] || []}
                class="flex items-start gap-2 text-sm"
              >
                <.icon name="hero-light-bulb" class="size-4 text-warning shrink-0 mt-0.5" />
                <span class="opacity-80">{insight}</span>
              </div>
            </div>

            <div
              :if={analysis.result_json["alerta"]}
              class="alert alert-warning text-sm py-2 mb-3"
            >
              <.icon name="hero-exclamation-triangle" class="size-4" />
              <span>{analysis.result_json["alerta"]}</span>
            </div>

            <div
              :if={analysis.result_json["dica"]}
              class="flex items-start gap-2 text-sm bg-success/10 rounded-lg p-3"
            >
              <.icon name="hero-check-circle" class="size-4 text-success shrink-0 mt-0.5" />
              <span class="opacity-80">{analysis.result_json["dica"]}</span>
            </div>
          </div>
        </div>

        <dialog
          :if={@show_api_key_alert}
          class="modal modal-open"
          phx-window-keydown="dismiss_api_alert"
          phx-key="Escape"
        >
          <div class="modal-box">
            <h3 class="text-lg font-bold">API Key não configurada</h3>
            <p class="py-4 opacity-70">
              Para usar funcionalidades de IA (análise, categorização automática e extração de PDFs),
              você precisa configurar uma API Key do Google Gemini.
            </p>
            <ol class="list-decimal list-inside text-sm opacity-70 space-y-1 mb-4">
              <li>Acesse <a href="https://aistudio.google.com/apikey" target="_blank" class="link link-primary">Google AI Studio</a></li>
              <li>Crie uma API Key gratuita</li>
              <li>Cole a chave nas Configurações</li>
            </ol>
            <div class="modal-action">
              <button phx-click="dismiss_api_alert" class="btn btn-ghost">Fechar</button>
              <.link navigate={~p"/users/settings"} class="btn btn-primary">Ir para Configurações</.link>
            </div>
          </div>
          <form method="dialog" class="modal-backdrop">
            <button phx-click="dismiss_api_alert">close</button>
          </form>
        </dialog>

        <dialog
          :if={@delete_target}
          id="delete_analysis_modal"
          class="modal modal-open"
          phx-window-keydown="cancel_delete"
          phx-key="Escape"
        >
          <div class="modal-box">
            <h3 class="text-lg font-bold">Remover análise</h3>
            <p class="py-4 opacity-70">
              Tem certeza que deseja remover esta análise? Esta ação é permanente.
            </p>
            <div class="modal-action">
              <button phx-click="cancel_delete" class="btn btn-ghost">Cancelar</button>
              <button phx-click="delete_analysis" class="btn btn-error">Remover</button>
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

  defp type_label("debit"), do: "Despesas"
  defp type_label("credit"), do: "Receitas"
  defp type_label(_), do: "Todos"

  defp format_datetime_br(dt) do
    dt
    |> DateTime.add(-3, :hour)
    |> Calendar.strftime("%d/%m/%Y às %H:%M")
  end
end
