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
  alias GranaWeb.ModelChoicesHook

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
    |> assign(:ai_general, AI.describe(user, nil))
    |> assign(:ai_specialists, user.ai_specialists)
    |> assign(:ai_saved_ref, user.ai_provider)
    |> assign(:ai_selected_ref, selected)
    |> assign(:ai_default_model, model)
    |> assign(:ai_default_form, default_form(selected, model))
  end

  defp default_form(ref, model),
    do: to_form(%{"provider" => ref, "model" => model}, as: :default)

  # Usa o cache quando há (também na primeira renderização, sem piscar "carregando");
  # senão busca na API em segundo plano.
  defp load_models(socket) do
    ref = socket.assigns.ai_selected_ref

    if ref && not Map.has_key?(socket.assigns.ai_models, ref) do
      provider = AI.get_provider(socket.assigns.current_scope.user, ref)

      case AI.cached_models(provider) do
        {:ok, models} -> put_models(socket, ref, {:ok, models})
        :miss -> fetch_models(socket, ref, provider)
      end
    else
      socket
    end
  end

  defp fetch_models(socket, ref, provider) do
    if connected?(socket) do
      socket
      |> update(:ai_models, &Map.put(&1, ref, :loading))
      |> start_async(:ai_models, fn -> {ref, AI.list_models(provider)} end)
    else
      socket
    end
  end

  defp put_models(socket, ref, result) do
    socket = update(socket, :ai_models, &Map.put(&1, ref, result))
    ensure_default(socket, ref, result)
  end

  defp handle_async(:ai_models, {:ok, {ref, result}}, socket) do
    {:halt, put_models(socket, ref, result)}
  end

  defp handle_async(:ai_models, {:exit, _reason}, socket) do
    ref = socket.assigns.ai_selected_ref
    error = {:error, "Não foi possível carregar os modelos. Tente de novo."}
    {:halt, update(socket, :ai_models, &Map.put(&1, ref, error))}
  end

  defp handle_async(_name, _result, socket), do: {:cont, socket}

  # Sem padrão salvo (ex.: só há provedor do ambiente, ou o padrão apontava para um
  # provedor removido), já grava o modelo sugerido. Trocar o provedor no select não conta:
  # o padrão só muda em "Salvar padrão".
  defp ensure_default(socket, ref, {:ok, models}) do
    user = socket.assigns.current_scope.user

    if is_nil(user.ai_model) or is_nil(AI.get_provider(user, user.ai_provider)) do
      case AI.get_provider(user, ref) do
        %ProviderConfig{kind: kind} ->
          suggested = Grana.AI.Models.suggest(kind, models)
          {:ok, user} = AI.set_default(user, ref, suggested)

          socket
          |> assign(:current_scope, Accounts.Scope.for_user(user))
          |> assign_ai()
          |> ModelChoicesHook.refresh()

        nil ->
          socket
      end
    else
      # Quando o usuário trocou para outro provedor no dropdown e os modelos acabaram de carregar
      if socket.assigns.ai_selected_ref == ref and ref != user.ai_provider and
           is_nil(socket.assigns.ai_default_form[:model].value) do
        provider = AI.get_provider(user, ref)
        suggested = provider && Grana.AI.Models.suggest(provider.kind, models)

        socket
        |> assign(:ai_default_model, suggested)
        |> assign(:ai_default_form, default_form(ref, suggested))
      else
        socket
      end
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

    if Accounts.sudo_mode?(user) do
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
           |> ModelChoicesHook.refresh()
           |> put_flash(:info, "#{provider.name} cadastrado. Modelos carregados da API.")}

        {:error, changeset} ->
          # A chave digitada não volta para a tela.
          scrubbed = %{
            changeset
            | changes: Map.delete(changeset.changes, :api_key),
              params: Map.put(changeset.params || %{}, "api_key", "")
          }

          {:halt,
           assign(socket, :ai_form, to_form(duplicate_error(scrubbed, params), as: :provider))}
      end
    else
      {:halt, GranaWeb.UserAuth.redirect_for_reauth(socket)}
    end
  end

  defp handle_event("ai_remove_provider", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user

    if Accounts.sudo_mode?(user) do
      {:ok, user} = AI.remove_provider(user, String.to_integer(id))

      {:halt,
       socket
       |> assign(:current_scope, Accounts.Scope.for_user(user))
       |> assign_ai()
       |> load_models()
       |> ModelChoicesHook.refresh()
       |> put_flash(:info, "Provedor removido.")}
    else
      {:halt, GranaWeb.UserAuth.redirect_for_reauth(socket)}
    end
  end

  defp handle_event("ai_default_change", %{"default" => params}, socket) do
    ref = params["provider"]

    if ref == socket.assigns.ai_selected_ref do
      {:halt, assign(socket, :ai_default_form, default_form(ref, params["model"]))}
    else
      user = socket.assigns.current_scope.user
      provider = AI.get_provider(user, ref)

      model =
        case socket.assigns.ai_models[ref] do
          {:ok, models} when is_list(models) and models != [] ->
            model_ids = Enum.map(models, & &1.id)

            if ref == user.ai_provider and user.ai_model in model_ids do
              user.ai_model
            else
              provider && Grana.AI.Models.suggest(provider.kind, models)
            end

          _ ->
            if ref == user.ai_provider, do: user.ai_model, else: nil
        end

      {:halt,
       socket
       |> assign(:ai_selected_ref, ref)
       |> assign(:ai_default_model, model)
       |> assign(:ai_default_form, default_form(ref, model))
       |> load_models()}
    end
  end

  defp handle_event(
         "ai_save_default",
         %{"default" => %{"provider" => ref, "model" => model}},
         socket
       ) do
    user = socket.assigns.current_scope.user

    if Accounts.sudo_mode?(user) do
      if AI.get_provider(user, ref) && model not in [nil, ""] do
        {:ok, user} = AI.set_default(user, ref, model)

        {:halt,
         socket
         |> assign(:current_scope, Accounts.Scope.for_user(user))
         |> assign_ai()
         |> ModelChoicesHook.refresh()
         |> put_flash(:info, "Padrão salvo: #{model}.")}
      else
        form =
          to_form(%{"provider" => ref, "model" => model},
            as: :default,
            errors: [model: {"Escolha o provedor e o modelo.", []}]
          )

        {:halt, assign(socket, :ai_default_form, form)}
      end
    else
      {:halt, GranaWeb.UserAuth.redirect_for_reauth(socket)}
    end
  end

  defp handle_event("ai_save_specialists", %{"specialists" => params}, socket) do
    user = socket.assigns.current_scope.user

    if Accounts.sudo_mode?(user) do
      user =
        Enum.reduce(AI.specialists(), user, fn key, user ->
          {:ok, user} = AI.set_specialist_default(user, key, params[key])
          user
        end)

      {:halt,
       socket
       |> assign(:current_scope, Accounts.Scope.for_user(user))
       |> assign_ai()
       |> ModelChoicesHook.refresh()
       |> put_flash(:info, "Modelos dos especialistas salvos.")}
    else
      {:halt, GranaWeb.UserAuth.redirect_for_reauth(socket)}
    end
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  # O nome não é editável nos tipos fixos, então o erro de nome repetido aparece no campo Tipo.
  defp duplicate_error(changeset, %{"kind" => kind}) when kind != "openai_compatible" do
    if Keyword.has_key?(changeset.errors, :name) and
         not Keyword.has_key?(changeset.errors, :api_key) do
      Ecto.Changeset.add_error(
        changeset,
        :kind,
        "#{AI.label(kind)} já está cadastrado. Remova o existente para trocar a chave."
      )
    else
      changeset
    end
  end

  defp duplicate_error(changeset, _params), do: changeset
end
