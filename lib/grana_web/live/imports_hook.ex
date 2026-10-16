defmodule GranaWeb.ImportsHook do
  @moduledoc """
  Leva o andamento da importação (`Grana.Imports`) a toda tela logada: mantém
  `@import_queue` em dia, que o `Layouts.app` mostra como aviso flutuante, e trata o
  `dismiss_imports` (fechar o aviso ou limpar o resumo).
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias Grana.Imports

  def on_mount(:default, _params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id
    if connected?(socket), do: Imports.subscribe(user_id)

    {:cont,
     socket
     |> assign(:import_queue, Imports.queue(user_id))
     |> attach_hook(:imports, :handle_info, &handle_info/2)
     |> attach_hook(:imports_dismiss, :handle_event, &handle_event/3)}
  end

  defp handle_info(:imports_changed, socket), do: {:halt, reload(socket)}
  defp handle_info(_message, socket), do: {:cont, socket}

  defp handle_event("dismiss_imports", _params, socket) do
    Imports.clear(socket.assigns.current_scope.user.id)
    {:halt, reload(socket)}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp reload(socket),
    do: assign(socket, :import_queue, Imports.queue(socket.assigns.current_scope.user.id))
end
