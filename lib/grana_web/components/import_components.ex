defmodule GranaWeb.ImportComponents do
  @moduledoc """
  Andamento da fila de importação (`Grana.Imports.queue/1`): o painel completo da tela
  de importação e o aviso flutuante que as outras telas mostram.
  """
  use GranaWeb, :html

  @doc "Painel da tela de importação: progresso geral e a situação de cada arquivo."
  attr :queue, :map, required: true

  def import_panel(assigns) do
    ~H"""
    <section id="import-queue" class="card bg-base-200 mb-8 p-5 sm:p-6" aria-live="polite">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div class="min-w-0">
          <h2 class="ui-card-title">{title(@queue)}</h2>
          <p class="ui-help mt-1">
            <%= if @queue.active? do %>
              {@queue.finished} de {count_label(@queue.total, "arquivo", "arquivos")}. Roda em segundo plano: pode sair desta tela.
            <% else %>
              {summary(@queue)}
            <% end %>
          </p>
        </div>
        <.button
          :if={!@queue.active?}
          id="import-queue-clear"
          type="button"
          variant="secondary"
          size="sm"
          icon="hero-check"
          phx-click="dismiss_imports"
        >
          Limpar
        </.button>
      </div>

      <div class="mt-4 flex items-center gap-3">
        <.progress_bar queue={@queue} class="flex-1" />
        <span class="ui-help font-mono">{percent(@queue)}%</span>
      </div>

      <ul
        id="import-queue-files"
        class="mt-3 max-h-96 divide-y divide-base-content/10 overflow-y-auto"
      >
        <li
          :for={file <- @queue.files}
          :key={file.id}
          id={"import-file-#{file.id}"}
          class="flex items-center gap-3 py-2.5"
        >
          <.status_icon status={file.status} />
          <div class="min-w-0 flex-1">
            <p class="ui-private-name ui-body truncate">{file.filename}</p>
            <p :if={file.status == :error} class="ui-help text-error">
              {error_message(file.error, file.bank)}
            </p>
          </div>
          <.status_tag file={file} />
        </li>
      </ul>
    </section>
    """
  end

  @doc """
  Aviso flutuante com o andamento, para as telas fora da importação. Some quando a fila
  está vazia; ao terminar, fica até ser fechado.
  """
  attr :queue, :map, default: nil

  def import_toast(assigns) do
    ~H"""
    <div :if={@queue && @queue.total > 0} id="import-toast" role="status" aria-live="polite">
      <div class={["ui-notice ui-toast shadow-lg", toast_tone(@queue)]}>
        <.icon
          name={toast_icon(@queue)}
          class={["size-5 shrink-0 self-start", @queue.active? && "motion-safe:animate-spin"]}
        />
        <div class="min-w-0 flex-1">
          <p class="font-semibold">{title(@queue)}</p>
          <p class="ui-help">
            <%= if @queue.active? do %>
              {@queue.finished} de {count_label(@queue.total, "arquivo", "arquivos")}
            <% else %>
              {summary(@queue)}
            <% end %>
          </p>
          <.progress_bar :if={@queue.active?} queue={@queue} class="mt-2" />
          <.link
            id="import-toast-details"
            navigate={~p"/upload"}
            class="mt-1 inline-block text-sm font-medium underline-offset-2 hover:underline"
          >
            Ver detalhes
          </.link>
        </div>
        <button
          :if={!@queue.active?}
          id="import-toast-close"
          type="button"
          class="group self-start cursor-pointer"
          aria-label="Fechar"
          phx-click="dismiss_imports"
        >
          <.icon name="hero-x-mark" class="ui-text-tertiary size-5 group-hover:text-base-content" />
        </button>
      </div>
    </div>
    """
  end

  attr :queue, :map, required: true
  attr :class, :any, default: nil

  defp progress_bar(assigns) do
    ~H"""
    <div
      class={["h-1.5 overflow-hidden rounded-full bg-base-content/10", @class]}
      role="progressbar"
      aria-valuemin="0"
      aria-valuemax={@queue.total}
      aria-valuenow={@queue.finished}
    >
      <div
        class="h-full rounded-full bg-primary transition-[width] duration-500 ease-out"
        style={"width: #{percent(@queue)}%"}
      />
    </div>
    """
  end

  attr :status, :atom, required: true

  defp status_icon(assigns) do
    ~H"""
    <.icon
      name={status_icon_name(@status)}
      class={[
        "size-5 shrink-0",
        status_icon_class(@status),
        @status == :processing && "motion-safe:animate-spin"
      ]}
    />
    """
  end

  defp status_icon_name(:pending), do: "hero-clock"
  defp status_icon_name(:processing), do: "hero-arrow-path"
  defp status_icon_name(:ok), do: "hero-check-circle"
  defp status_icon_name(:error), do: "hero-x-circle"

  defp status_icon_class(:pending), do: "ui-text-tertiary"
  defp status_icon_class(:processing), do: "text-primary"
  defp status_icon_class(:ok), do: "text-success"
  defp status_icon_class(:error), do: "text-error"

  attr :file, :map, required: true

  defp status_tag(assigns) do
    ~H"""
    <.tag :if={@file.status == :pending} kind="neutro">Na fila</.tag>
    <.tag :if={@file.status == :processing} kind="pendente">Processando…</.tag>
    <.tag :if={@file.status == :ok} kind="ativo">
      {count_label(@file.count, "transação", "transações")}
    </.tag>
    <.tag :if={@file.status == :error} kind="erro">Erro</.tag>
    """
  end

  defp title(%{active?: true}), do: "Importando arquivos"
  defp title(_queue), do: "Importação concluída"

  defp summary(%{failed: 0} = queue) do
    "#{count_label(queue.total, "arquivo importado", "arquivos importados")}, " <>
      count_label(queue.transactions, "transação", "transações") <> "."
  end

  defp summary(%{failed: failed, total: failed}),
    do: "Nenhum arquivo importado: #{count_label(failed, "erro", "erros")}."

  defp summary(queue),
    do: "#{queue.total - queue.failed} de #{queue.total} importados, #{queue.failed} com erro."

  defp percent(%{total: 0}), do: 0
  defp percent(queue), do: round(queue.finished / queue.total * 100)

  defp toast_tone(%{active?: true}), do: "ui-notice-info"
  defp toast_tone(%{failed: 0}), do: "ui-notice-success"
  defp toast_tone(_queue), do: "ui-notice-error"

  defp toast_icon(%{active?: true}), do: "hero-arrow-path"
  defp toast_icon(%{failed: 0}), do: "hero-check-circle"
  defp toast_icon(_queue), do: "hero-exclamation-circle"

  # Os processadores respondem em inglês ou com atoms; aqui vira texto para o usuário,
  # sem nunca expor termos internos crus.
  defp error_message("No transactions found in " <> source, bank) do
    where = if source == "PDF", do: "no PDF", else: "no arquivo"

    hint =
      if bank in [nil, "outro"],
        do: "",
        else: " Verifique se é mesmo do #{String.capitalize(bank)}."

    "Nenhuma transação encontrada #{where}.#{hint}"
  end

  defp error_message("no_api_key", _bank) do
    "Não foi possível extrair o PDF automaticamente (pode ser digitalizado). " <>
      "Cadastre um provedor de IA nas Configurações para processá-lo."
  end

  defp error_message(error, _bank) when is_binary(error) and error != "", do: error
  defp error_message(_error, _bank), do: "Não foi possível processar o arquivo."
end
