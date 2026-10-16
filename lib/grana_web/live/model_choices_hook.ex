defmodule GranaWeb.ModelChoicesHook do
  @moduledoc """
  Feeds the AI model pickers: `@model_defaults` (provider and model each specialist uses
  by default, no network) and `@model_choices` (every provider's models, loaded in the
  background; `:loading` until then).
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, start_async: 3]

  alias Grana.AI

  def on_mount(:default, _params, _session, socket) do
    socket =
      socket
      |> assign(:model_choices, :loading)
      |> refresh()
      |> attach_hook(:model_choices, :handle_async, &handle_async/3)

    {:cont, socket}
  end

  @doc "Reloads defaults and models after the providers or defaults change."
  def refresh(%{assigns: %{model_choices: _}} = socket) do
    user = socket.assigns.current_scope.user

    socket =
      assign(socket, :model_defaults, Map.new(AI.specialists(), &{&1, AI.describe(user, &1)}))

    if connected?(socket),
      do: start_async(socket, :model_choices, fn -> AI.model_choices(user) end),
      else: socket
  end

  def refresh(socket), do: socket

  defp handle_async(:model_choices, {:ok, choices}, socket),
    do: {:halt, assign(socket, :model_choices, choices)}

  defp handle_async(:model_choices, {:exit, _reason}, socket),
    do: {:halt, assign(socket, :model_choices, [])}

  defp handle_async(_name, _result, socket), do: {:cont, socket}
end
