defmodule Grana.AI do
  @moduledoc """
  Provedores de IA do dono da instância. É possível cadastrar vários (Gemini, OpenAI,
  Claude e qualquer serviço compatível com a API da OpenAI); os de ambiente
  (`GEMINI_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`) aparecem junto, sem
  registro no banco, e têm prioridade de leitura no sentido de que a tela não os edita.

  Os modelos vêm da API de cada provedor (`Grana.AI.Models`), nunca de uma lista no
  código. O par provedor + modelo padrão fica em `users.ai_provider`/`users.ai_model`.
  """

  import Ecto.Query

  alias Grana.AI.{Models, ProviderConfig}
  alias Grana.Accounts.User
  alias Grana.Repo

  @labels %{
    "gemini" => "Google Gemini",
    "openai" => "OpenAI",
    "anthropic" => "Anthropic (Claude)",
    "openai_compatible" => "Compatível com a API da OpenAI"
  }

  @env_kinds ~w(gemini openai anthropic)

  @specialists ~w(search analysis processing chat)

  @doc "Tipos disponíveis para cadastro: `[{kind, rótulo}]`."
  def kinds, do: Enum.map(ProviderConfig.kinds(), &{&1, @labels[&1]})

  def label(kind), do: @labels[kind]

  ## Provedores

  @doc "Provedores do ambiente primeiro, depois os cadastrados."
  def list_providers(%User{id: user_id}) do
    env_providers() ++
      Repo.all(from(p in ProviderConfig, where: p.user_id == ^user_id, order_by: [asc: p.id]))
  end

  def env_providers do
    keys = Application.get_env(:grana, :ai_env_keys, %{})

    for kind <- @env_kinds, key = keys[kind], is_binary(key) and key != "" do
      %ProviderConfig{kind: kind, name: @labels[kind], api_key: key, source: :env}
    end
  end

  def get_provider(%User{} = user, ref) when is_binary(ref) do
    Enum.find(list_providers(user), &(ProviderConfig.ref(&1) == ref))
  end

  def get_provider(_user, _ref), do: nil

  def change_provider(attrs \\ %{}) do
    ProviderConfig.changeset(%ProviderConfig{kind: "gemini"}, attrs)
  end

  @doc """
  Cadastra um provedor depois de conferir a chave listando os modelos na API: uma
  chave ou endereço errado aparece na hora como erro do formulário. Se ainda não há
  padrão, o novo provedor vira o padrão. Devolve `{:ok, provider, models}`.
  """
  def add_provider(%User{} = user, attrs) do
    attrs = default_name(attrs)
    changeset = ProviderConfig.changeset(%ProviderConfig{user_id: user.id}, attrs)

    with {:ok, candidate} <- Ecto.Changeset.apply_action(changeset, :insert),
         {:ok, models} <- Models.list(config_for(candidate)),
         {:ok, provider} <- Repo.insert(changeset) do
      user = maybe_set_default(user, provider, models)
      {:ok, provider, models, user}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}

      {:error, message} when is_binary(message) ->
        field = if attrs["kind"] == "openai_compatible", do: :base_url, else: :api_key

        {:error,
         changeset |> Ecto.Changeset.add_error(field, message) |> Map.put(:action, :insert)}
    end
  end

  # Gemini, OpenAI e Anthropic se chamam pelo próprio rótulo; só os compatíveis (que
  # podem ser vários serviços diferentes) têm nome livre, e em branco cai no rótulo.
  defp default_name(%{"kind" => kind} = attrs) when kind != "openai_compatible" do
    if @labels[kind], do: Map.put(attrs, "name", @labels[kind]), else: attrs
  end

  defp default_name(attrs) do
    if String.trim(attrs["name"] || "") == "",
      do: Map.put(attrs, "name", @labels[attrs["kind"]] || ""),
      else: attrs
  end

  # Só provedores novos viram padrão quando ainda não há um. Valores antigos que não são
  # referências ("gemini", o default da coluna) contam como "sem padrão".
  defp maybe_set_default(user, provider, models) do
    if default_set?(user) do
      user
    else
      {:ok, user} =
        set_default(user, ProviderConfig.ref(provider), Models.suggest(provider.kind, models))

      user
    end
  end

  defp default_set?(%User{ai_provider: "env:" <> _}), do: true
  defp default_set?(%User{ai_provider: "db:" <> _}), do: true
  defp default_set?(_user), do: false

  @doc "Remove o provedor; se era o padrão, o padrão é limpo (o próximo uso escolhe outro)."
  def remove_provider(%User{} = user, id) do
    provider = Repo.get_by!(ProviderConfig, id: id, user_id: user.id)
    ref = ProviderConfig.ref(provider)
    {:ok, _} = Repo.delete(provider)

    specialists =
      Map.reject(user.ai_specialists, fn {_key, choice} -> choice_ref(choice) == ref end)

    {:ok, user} = user |> User.ai_specialists_changeset(specialists) |> Repo.update()

    if user.ai_provider == ref do
      set_default(user, nil, nil)
    else
      {:ok, user}
    end
  end

  @doc "Modelos do provedor, direto da API dele."
  def list_models(%ProviderConfig{} = provider), do: Models.list(config_for(provider))

  @doc "Modelos do provedor já em cache (sem rede): `{:ok, modelos}` ou `:miss`."
  def cached_models(%ProviderConfig{} = provider), do: Models.cached(config_for(provider))

  ## Padrão

  def set_default(%User{} = user, ref, model) do
    user |> User.ai_default_changeset(ref, model) |> Repo.update()
  end

  defp general_config(user, providers) do
    case Enum.find(providers, &(ProviderConfig.ref(&1) == user.ai_provider)) do
      %ProviderConfig{} = provider when is_binary(user.ai_model) ->
        {:ok, Map.put(config_for(provider), :model, user.ai_model)}

      _ ->
        choose_default(user, providers)
    end
  end

  defp choose_default(_user, []), do: {:error, :no_api_key}

  defp choose_default(user, [provider | _]) do
    with {:ok, models} <- Models.list(config_for(provider)),
         model when is_binary(model) <- Models.suggest(provider.kind, models),
         {:ok, _user} <- set_default(user, ProviderConfig.ref(provider), model) do
      {:ok, Map.put(config_for(provider), :model, model)}
    else
      _ -> {:error, :no_api_key}
    end
  end

  @doc "Mapa com o que as chamadas à API precisam (inclui a chave: nunca vai para a tela)."
  def config_for(%ProviderConfig{} = provider) do
    %{
      provider: provider.kind,
      name: provider.name,
      api_key: provider.api_key,
      base_url: provider.base_url,
      ref: ProviderConfig.ref(provider)
    }
  end

  ## Specialists

  @doc "Keys of the AI specialists, each with its own default model."
  def specialists, do: @specialists

  @doc "Encodes a provider + model pair as used by model pickers and stored defaults."
  def choice(ref, model), do: "#{ref}|#{model}"

  @doc "Choice of the general default, or nil when none is saved."
  def general_choice(%User{ai_provider: ref, ai_model: model})
      when is_binary(ref) and is_binary(model),
      do: choice(ref, model)

  def general_choice(_user), do: nil

  @doc "The specialist's own default choice, or nil when it follows the general default."
  def specialist_choice(%User{ai_specialists: specialists}, specialist),
    do: Map.get(specialists || %{}, specialist)

  @doc "Saves the specialist default; a blank choice makes it follow the general default again."
  def set_specialist_default(%User{} = user, specialist, choice)
      when specialist in @specialists do
    specialists =
      if choice in [nil, ""],
        do: Map.delete(user.ai_specialists, specialist),
        else: Map.put(user.ai_specialists, specialist, choice)

    user |> User.ai_specialists_changeset(specialists) |> Repo.update()
  end

  @doc """
  Config for a call made by `specialist`. Precedence: the `choice` picked for this call,
  then the specialist default, then the general default. Choices pointing to a provider
  that no longer exists are skipped.
  """
  def resolve(user, specialist, choice \\ nil)

  def resolve(user_id, specialist, choice) when is_integer(user_id),
    do: resolve(Repo.get!(User, user_id), specialist, choice)

  def resolve(%User{} = user, specialist, choice) do
    providers = list_providers(user)

    with :error <- from_choice(providers, choice),
         :error <- from_choice(providers, specialist && specialist_choice(user, specialist)) do
      general_config(user, providers)
    end
  end

  @doc "Provider and model the call would use, without touching the network: `{name, model}` or nil."
  def describe(%User{} = user, specialist) do
    providers = list_providers(user)

    Enum.find_value(
      [specialist_choice(user, specialist), general_choice(user)],
      fn choice ->
        case from_choice(providers, choice) do
          {:ok, config} -> {config.name, config.model}
          :error -> nil
        end
      end
    )
  end

  @doc "Every provider with its models, for the model pickers."
  def model_choices(%User{} = user) do
    for provider <- list_providers(user) do
      %{ref: ProviderConfig.ref(provider), name: provider.name, models: list_models(provider)}
    end
  end

  defp from_choice(providers, choice) when is_binary(choice) do
    with [ref, model] when model != "" <- String.split(choice, "|", parts: 2),
         %ProviderConfig{} = provider <- Enum.find(providers, &(ProviderConfig.ref(&1) == ref)) do
      {:ok, Map.put(config_for(provider), :model, model)}
    else
      _ -> :error
    end
  end

  defp from_choice(_providers, _choice), do: :error

  defp choice_ref(choice) do
    choice |> String.split("|", parts: 2) |> hd()
  end
end
