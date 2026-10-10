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
    {:ok, _} = Repo.delete(provider)

    if user.ai_provider == ProviderConfig.ref(provider) do
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

  @doc """
  Configuração pronta para `Grana.AI.Provider` (`{:ok, config}`) com o provedor e o
  modelo padrão, ou `{:error, :no_api_key}` se não há provedor utilizável. Sem padrão
  salvo, usa o primeiro provedor e o modelo sugerido pela API, e já grava a escolha.
  """
  def resolve_config(user_id) do
    user = Repo.get!(User, user_id)
    providers = list_providers(user)

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
      base_url: provider.base_url
    }
  end
end
