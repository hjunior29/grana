defmodule GranaWeb.DataHook do
  @moduledoc """
  `@has_data` on every logged-in screen: false until the first transaction exists,
  imported or from Open Finance. Screens that read the data show only
  `UiComponents.no_data/1` meanwhile, with no filters or tools around it.

  Those screens also declare `on_mount {GranaWeb.DataHook, :reload_on_data}`: while
  there is no data, an import or Open Finance read that brings the first transactions
  reloads them, so they show what arrived.
  """

  import Phoenix.Component, only: [assign: 3]

  import Phoenix.LiveView,
    only: [attach_hook: 4, detach_hook: 3, push_navigate: 2, put_private: 3]

  alias Grana.Banking

  # Attached by the live_session before `GranaWeb.ImportsHook`, which consumes
  # `:imports_changed`: a screen's own on_mount would attach too late to see it.
  def on_mount(:default, _params, _session, socket) do
    has_data = Banking.has_transactions?(socket.assigns.current_scope.user.id)
    socket = assign(socket, :has_data, has_data)

    if has_data do
      {:cont, socket}
    else
      {:cont,
       socket
       |> attach_hook(:data_path, :handle_params, &keep_path/3)
       |> attach_hook(:data_arrival, :handle_info, &handle_info/2)}
    end
  end

  def on_mount(:reload_on_data, _params, _session, socket),
    do: {:cont, put_private(socket, :reload_on_data, true)}

  defp keep_path(_params, uri, socket) do
    %URI{path: path, query: query} = URI.parse(uri)
    {:cont, put_private(socket, :data_path, if(query, do: "#{path}?#{query}", else: path))}
  end

  # Without data yet, the messages go on to the queue notice and the screen's own
  # handlers; with it, the screen is replaced and nobody else needs them.
  defp handle_info(:imports_changed, socket), do: reload_on_data(socket)
  defp handle_info({:open_finance_synced, _connection_id}, socket), do: reload_on_data(socket)
  defp handle_info(_message, socket), do: {:cont, socket}

  defp reload_on_data(%{private: %{reload_on_data: true}} = socket) do
    if Banking.has_transactions?(socket.assigns.current_scope.user.id) do
      {:halt,
       socket
       |> detach_hook(:data_arrival, :handle_info)
       |> push_navigate(to: socket.private.data_path)}
    else
      {:cont, socket}
    end
  end

  defp reload_on_data(socket), do: {:cont, socket}
end
