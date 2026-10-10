defmodule GranaWeb.AiSettingsHooks do
  @moduledoc """
  Estado e eventos do painel de provedores de IA (`AiComponents.providers_panel/1`),
  compartilhados por Configurações e Onboarding.

  Os modelos de cada provedor são lidos da API dele (`Grana.AI.Models`) em segundo
  plano, uma vez por provedor por visita à tela.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  alias Grana.Accounts
  alias Grana.AI
  alias Grana.AI.ProviderConfig

  def on_mount(:default, _params, _session, socket) do
    socket =
      socket
      |> assign(:ai_form, provider_form(%{}))
      |> assign(:ai_show_form, false)
      |> assign(:ai_models, %{})
      |> assign_ai()
      |> attach_hook(:ai_events, :handle_event, &handle_event/3)
      |> attach_hook(:ai_async, :handle_async, &handle_async/3)

    {:cont, load_models(socket)}
  end

  defp provider_form(params), do: to_form(AI.change_provider(params), as: :provider)

  # Lista (sem as chaves: elas ficam só no servidor), padrão e formulário do padrão.
  defp assign_ai(socket) do
    user = socket.assigns.current_scope.user
    providers = AI.list_providers(user)
    refs = Enum.map(providers, &ProviderConfig.ref/1)
    selected = if user.ai_provider in refs, do: user.ai_provider, else: List.first(refs)
    model = if selected == user.ai_provider, do: user.ai_model

    socket
    |> assign(:ai_providers, Enum.map(providers, &%{&1 | api_key: nil}))
    |> assign(:ai_selected_ref, selected)
    |> assign(:ai_default_model, model)
    |> assign(:ai_default_form, default_form(selected, model))
  end

  defp default_form(ref, model),
    do: to_form(%{"provider" => ref, "model" => model}, as: :default)

  defp load_models(socket) do
    ref = socket.assigns.ai_selected_ref

    if (connected?(socket) and ref) && not Map.has_key?(socket.assigns.ai_models, ref) do
      user = socket.assigns.current_scope.user
      provider = AI.get_provider(user, ref)

      socket
      |> update(:ai_models, &Map.put(&1, ref, :loading))
      |> start_async(:ai_models, fn -> {ref, AI.list_models(provider)} end)
    else
      socket
    end
  end

  defp handle_async(:ai_models, {:ok, {ref, result}}, socket) do
    socket = update(socket, :ai_models, &Map.put(&1, ref, result))
    {:halt, ensure_default(socket, ref, result)}
  end

  defp handle_async(:ai_models, {:exit, _reason}, socket) do
    ref = socket.assigns.ai_selected_ref
    error = {:error, "Não foi possível carregar os modelos. Tente de novo."}
    {:halt, update(socket, :ai_models, &Map.put(&1, ref, error))}
  end

  defp handle_async(_name, _result, socket), do: {:cont, socket}

  # Sem padrão salvo (ex.: só há provedor do ambiente), já grava o modelo sugerido.
  defp ensure_default(socket, ref, {:ok, models}) do
    user = socket.assigns.current_scope.user

    if is_nil(user.ai_model) or user.ai_provider != ref do
      case AI.get_provider(user, ref) do
        %ProviderConfig{kind: kind} ->
          {:ok, user} = AI.set_default(user, ref, Grana.AI.Models.suggest(kind, models))
          socket |> assign(:current_scope, Accounts.Scope.for_user(user)) |> assign_ai()

        nil ->
          socket
      end
    else
      socket
    end
  end

  defp ensure_default(socket, _ref, _error), do: socket

  defp handle_event("ai_toggle_form", _params, socket) do
    {:halt, assign(socket, :ai_show_form, !socket.assigns.ai_show_form)}
  end

  defp handle_event("ai_validate_provider", %{"provider" => params}, socket) do
    {:halt, assign(socket, :ai_form, provider_form(params))}
  end

  defp handle_event("ai_add_provider", %{"provider" => params}, socket) do
    user = socket.assigns.current_scope.user

    case AI.add_provider(user, params) do
      {:ok, provider, models, user} ->
        ref = ProviderConfig.ref(provider)

        {:halt,
         socket
         |> assign(:current_scope, Accounts.Scope.for_user(user))
         |> update(:ai_models, &Map.put(&1, ref, {:ok, models}))
         |> assign(:ai_form, provider_form(%{}))
         |> assign(:ai_show_form, false)
         |> assign_ai()
         |> put_flash(:info, "#{provider.name} cadastrado. Os modelos vieram direto da API.")}

      {:error, changeset} ->
        # A chave digitada não volta para a tela.
        scrubbed = %{
          changeset
          | changes: Map.delete(changeset.changes, :api_key),
            params: Map.put(changeset.params || %{}, "api_key", "")
        }

        {:halt, assign(socket, :ai_form, to_form(scrubbed, as: :provider))}
    end
  end

  defp handle_event("ai_remove_provider", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    {:ok, user} = AI.remove_provider(user, String.to_integer(id))

    {:halt,
     socket
     |> assign(:current_scope, Accounts.Scope.for_user(user))
     |> assign_ai()
     |> load_models()
     |> put_flash(:info, "Provedor removido.")}
  end

  defp handle_event("ai_default_change", %{"default" => params}, socket) do
    ref = params["provider"]

    if ref == socket.assigns.ai_selected_ref do
      {:halt, assign(socket, :ai_default_form, default_form(ref, params["model"]))}
    else
      {:halt,
       socket
       |> assign(:ai_selected_ref, ref)
       |> assign(:ai_default_form, default_form(ref, nil))
       |> load_models()}
    end
  end

  defp handle_event(
         "ai_save_default",
         %{"default" => %{"provider" => ref, "model" => model}},
         socket
       ) do
    user = socket.assigns.current_scope.user

    if AI.get_provider(user, ref) && model not in [nil, ""] do
      {:ok, user} = AI.set_default(user, ref, model)

      {:halt,
       socket
       |> assign(:current_scope, Accounts.Scope.for_user(user))
       |> assign_ai()
       |> put_flash(:info, "Padrão salvo: #{model}.")}
    else
      {:halt, put_flash(socket, :error, "Escolha o provedor e o modelo.")}
    end
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}
end
