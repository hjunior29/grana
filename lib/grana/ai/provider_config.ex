defmodule Grana.AI.ProviderConfig do
  @moduledoc """
  Um provedor de IA cadastrado: o tipo (Gemini, OpenAI, Claude ou compatível com a API
  da OpenAI), um nome, o endereço (só para os compatíveis) e a chave, cifrada e só de
  escrita. Os provedores vindos do ambiente (`GEMINI_API_KEY` etc.) usam esta mesma
  struct, com `source: :env` e sem registro no banco.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(gemini openai anthropic openai_compatible)

  @derive {Inspect, except: [:api_key]}
  schema "ai_providers" do
    field :kind, :string
    field :name, :string
    field :base_url, :string
    field :api_key, Grana.Encrypted.Binary, redact: true
    field :source, Ecto.Enum, values: [:database, :env], virtual: true, default: :database

    belongs_to :user, Grana.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [:kind, :name, :base_url, :api_key])
    |> update_change(:name, &trim/1)
    |> update_change(:base_url, &trim/1)
    |> update_change(:api_key, &trim/1)
    |> validate_required([:kind, :name])
    |> validate_inclusion(:kind, @kinds)
    |> validate_length(:name, max: 60)
    |> validate_base_url()
    |> validate_api_key()
    |> unique_constraint(:name,
      name: :ai_providers_user_id_name_index,
      message: "já existe um provedor com esse nome"
    )
  end

  defp validate_base_url(changeset) do
    changeset =
      if get_field(changeset, :kind) == "openai_compatible",
        do: validate_required(changeset, [:base_url], message: "informe o endereço da API"),
        else: changeset

    changeset
    |> validate_format(:base_url, ~r{^https?://[^\s]+$},
      message: "deve começar com http:// ou https://"
    )
    |> validate_safe_host()
  end

  defp validate_safe_host(changeset) do
    validate_change(changeset, :base_url, fn :base_url, url ->
      uri = URI.parse(url)

      cond do
        is_nil(uri.host) or uri.host == "" ->
          [base_url: "endereço inválido"]

        blocked_host?(uri.host) ->
          [base_url: "endereço não permitido"]

        true ->
          []
      end
    end)
  end

  defp blocked_host?(host) do
    down = String.downcase(host)

    cond do
      down in ["metadata.google.internal", "metadata", "instance-data"] ->
        true

      match?({:ok, {169, 254, _, _}}, :inet.parse_address(String.to_charlist(host))) ->
        true

      match?({:ok, {0, _, _, _}}, :inet.parse_address(String.to_charlist(host))) ->
        true

      true ->
        false
    end
  end

  # Serviços locais (Ollama, LM Studio) não pedem chave.
  defp validate_api_key(changeset) do
    if get_field(changeset, :kind) == "openai_compatible",
      do: changeset,
      else: validate_required(changeset, [:api_key], message: "informe a chave da API")
  end

  defp trim(nil), do: nil
  defp trim(value), do: String.trim(value)

  @doc "Referência estável usada em `users.ai_provider`."
  def ref(%__MODULE__{source: :env, kind: kind}), do: "env:#{kind}"
  def ref(%__MODULE__{id: id}), do: "db:#{id}"
end
