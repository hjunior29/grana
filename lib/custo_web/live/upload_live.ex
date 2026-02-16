defmodule CustoWeb.UploadLive do
  use CustoWeb, :live_view

  alias Custo.Banking.StatementProcessor

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Upload Extrato")
      |> assign(:bank, nil)
      |> assign(:processing, false)
      |> assign(:results, [])
      |> allow_upload(:statements,
        accept: ~w(.csv .pdf),
        max_entries: 20,
        max_file_size: 10_000_000
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("select-bank", %{"bank" => bank}, socket) do
    {:noreply, assign(socket, :bank, bank)}
  end

  def handle_event("upload", _params, socket) do
    %{current_scope: scope} = socket.assigns
    bank = socket.assigns.bank

    case bank do
      nil ->
        {:noreply, put_flash(socket, :error, "Selecione um banco antes de fazer upload")}

      _ ->
        socket = assign(socket, :processing, true)
        send(self(), {:process_uploads, bank, scope.user.id})
        {:noreply, socket}
    end
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :statements, ref)}
  end

  @impl true
  def handle_info({:process_uploads, bank, user_id}, socket) do
    file_data =
      consume_uploaded_entries(socket, :statements, fn %{path: path}, entry ->
        {:ok, {entry.client_name, File.read!(path)}}
      end)

    Task.async(fn ->
      Enum.map(file_data, fn {filename, content} ->
        case StatementProcessor.process(content, bank, user_id, filename) do
          {:ok, result} -> {:ok, filename, result.transaction_count}
          {:error, reason} -> {:error, filename, reason}
        end
      end)
    end)

    {:noreply, assign(socket, :upload_bank, bank)}
  end

  def handle_info({ref, results}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    bank = socket.assigns[:upload_bank] || ""

    {successes, errors} =
      Enum.split_with(results, fn
        {:ok, _, _} -> true
        _ -> false
      end)

    socket =
      socket
      |> assign(:processing, false)
      |> assign(:results, successes)

    socket =
      case {successes, errors} do
        {[], errors} ->
          error_messages =
            Enum.map(errors, fn {:error, name, reason} ->
              "#{name}: #{format_error(reason, bank)}"
            end)

          put_flash(socket, :error, Enum.join(error_messages, " | "))

        {_, []} ->
          put_flash(socket, :info, "#{length(successes)} arquivo(s) processado(s) com sucesso!")

        {_, errors} ->
          error_msgs =
            Enum.map(errors, fn {:error, name, reason} ->
              "#{name}: #{format_error(reason, bank)}"
            end)

          socket
          |> put_flash(:info, "#{length(successes)} processado(s) com sucesso")
          |> put_flash(:error, Enum.join(error_msgs, " | "))
      end

    {:noreply, socket}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    socket =
      socket
      |> assign(:processing, false)
      |> put_flash(:error, "Erro inesperado no processamento")

    {:noreply, socket}
  end

  defp format_error("No transactions found in file", bank) do
    "Nenhuma transação encontrada. Verifique se o arquivo é realmente do #{String.capitalize(bank)}."
  end

  defp format_error("No transactions found in PDF", bank) do
    "Nenhuma transação encontrada no PDF. Verifique se o arquivo é realmente do #{String.capitalize(bank)}."
  end

  defp format_error(reason, _bank), do: reason

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-6xl mx-auto">
        <div class="mb-8">
          <h1 class="text-3xl font-bold tracking-tight">Upload</h1>
          <p class="text-sm opacity-60 mt-1">Importe extratos e faturas em formato CSV ou PDF</p>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-8">
          <button
            phx-click="select-bank"
            phx-value-bank="nubank"
            class={[
              "card bg-base-200 p-6 cursor-pointer transition-all hover:shadow-lg border-2",
              (@bank == "nubank" && "border-primary") || "border-transparent"
            ]}
          >
            <div class="flex items-center gap-4">
              <img src={~p"/images/nubank-logo.png"} alt="Nubank" class="w-12 h-12 rounded-full" />
              <div class="text-left">
                <h3 class="font-semibold text-lg">Nubank</h3>
                <p class="text-sm opacity-70">Extrato ou fatura CSV/PDF</p>
              </div>
            </div>
          </button>

          <button
            phx-click="select-bank"
            phx-value-bank="bradesco"
            class={[
              "card bg-base-200 p-6 cursor-pointer transition-all hover:shadow-lg border-2",
              (@bank == "bradesco" && "border-primary") || "border-transparent"
            ]}
          >
            <div class="flex items-center gap-4">
              <img src={~p"/images/bradesco-logo.png"} alt="Bradesco" class="w-12 h-12 rounded-full" />
              <div class="text-left">
                <h3 class="font-semibold text-lg">Bradesco</h3>
                <p class="text-sm opacity-70">Extrato ou fatura CSV/PDF</p>
              </div>
            </div>
          </button>
        </div>

        <div :if={@bank} class="card bg-base-200 p-8 mb-8">
          <form id="upload-form" phx-submit="upload" phx-change="validate">
            <div class="flex flex-col items-center gap-4">
              <div
                id="drop-zone"
                class="w-full border-2 border-dashed border-base-content/20 rounded-xl hover:border-primary/50 transition-all duration-200"
                phx-drop-target={@uploads.statements.ref}
                phx-hook="DropZone"
              >
                <.live_file_input upload={@uploads.statements} class="hidden" />
                <label for={@uploads.statements.ref} class="cursor-pointer block p-8 text-center">
                  <.icon name="hero-cloud-arrow-up" class="size-12 mx-auto mb-4 opacity-40" />
                  <p class="font-medium">Arraste arquivos CSV ou PDF, ou clique para selecionar</p>
                  <p class="text-sm opacity-60 mt-1">Até 20 arquivos, máximo 10MB cada</p>
                </label>
              </div>

              <div :if={@uploads.statements.entries != []} class="w-full space-y-3">
                <div
                  :for={entry <- @uploads.statements.entries}
                  class="flex items-center justify-between bg-base-100 rounded-lg p-3"
                >
                  <div class="flex items-center gap-3">
                    <.icon name="hero-document-text" class="size-5 opacity-60" />
                    <span class="text-sm font-medium">{entry.client_name}</span>
                    <span class="badge badge-sm">{format_bytes(entry.client_size)}</span>
                  </div>
                  <button
                    type="button"
                    phx-click="cancel-upload"
                    phx-value-ref={entry.ref}
                    class="btn btn-ghost btn-xs btn-circle"
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </div>
              </div>

              <div :for={err <- upload_errors(@uploads.statements)} class="text-error text-sm">
                {upload_error_to_string(err)}
              </div>

              <button
                type="submit"
                class="btn btn-primary btn-wide"
                disabled={@processing || @uploads.statements.entries == []}
              >
                <span :if={@processing} class="loading loading-spinner loading-sm" />
                {if @processing, do: "Processando...", else: "Processar Extratos"}
              </button>
            </div>
          </form>
        </div>

        <div :if={@results != []} class="card bg-success/10 p-6 mb-4">
          <h3 class="font-semibold text-success mb-3">Processados com sucesso</h3>
          <div
            :for={{:ok, name, count} <- @results}
            class="flex justify-between py-2 border-b border-base-content/10 last:border-0"
          >
            <span>{name}</span>
            <span class="badge badge-success">{count} transações</span>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024, 1)} KB"

  defp upload_error_to_string(:too_large), do: "Arquivo muito grande (máximo 10MB)"
  defp upload_error_to_string(:not_accepted), do: "Tipo de arquivo não aceito (use CSV ou PDF)"
  defp upload_error_to_string(:too_many_files), do: "Muitos arquivos (máximo 20)"
  defp upload_error_to_string(err), do: "Erro: #{inspect(err)}"
end
