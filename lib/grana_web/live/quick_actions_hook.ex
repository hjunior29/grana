defmodule GranaWeb.QuickActionsHook do
  use GranaWeb, :verified_routes

  import Phoenix.LiveView, only: [attach_hook: 4]

  alias Grana.Banking

  def on_mount(:default, _params, _session, socket) do
    {:cont, attach_hook(socket, :quick_actions, :handle_event, &handle_event/3)}
  end

  defp handle_event("quick_actions:load", _params, socket) do
    searches =
      socket.assigns.current_scope.user.id
      |> Banking.list_saved_searches()
      |> Enum.map(fn saved ->
        %{
          id: saved.id,
          name: saved.name,
          path: ~p"/transactions?#{[mode: "advanced", q: saved.query, saved: saved.id]}"
        }
      end)

    {:halt, %{searches: searches}, socket}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}
end
