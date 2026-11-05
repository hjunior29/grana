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

  import Bitwise

  defp blocked_host?(host) do
    down = String.downcase(host)

    cond do
      down in ["metadata.google.internal", "metadata", "instance-data"] ->
        true

      ip_blocked?(down) ->
        true

      true ->
        resolve_and_check(down)
    end
  end

  defp ip_blocked?(host) do
    clean = host |> String.trim_leading("[") |> String.trim_trailing("]")

    case :inet.parse_address(String.to_charlist(clean)) do
      {:ok, ip} -> blocked_ip?(ip)
      _ -> false
    end
  end

  defp resolve_and_check(host) do
    charlist = String.to_charlist(host)

    ipv4s =
      case :inet.getaddrs(charlist, :inet) do
        {:ok, addrs} -> addrs
        _ -> []
      end

    ipv6s =
      case :inet.getaddrs(charlist, :inet6) do
        {:ok, addrs} -> addrs
        _ -> []
      end

    Enum.any?(ipv4s ++ ipv6s, &blocked_ip?/1)
  end

  # IPv4 tuples: {a, b, c, d}
  defp blocked_ip?({0, _, _, _}), do: true
  defp blocked_ip?({169, 254, _, _}), do: true
  defp blocked_ip?({100, b, _, _}) when b >= 64 and b <= 127, do: true

  # IPv6 tuples: {w1, w2, w3, w4, w5, w6, w7, w8}
  defp blocked_ip?({0, 0, 0, 0, 0, 0, 0, 0}), do: true
  defp blocked_ip?({0xFD00, 0x0EC2, _, _, _, _, _, _}), do: true

  # IPv4-mapped IPv6: ::ffff:a.b.c.d
  defp blocked_ip?({0, 0, 0, 0, 0, 0xFFFF, w7, w8}) do
    blocked_ip?({w7 >>> 8, band(w7, 0xFF), w8 >>> 8, band(w8, 0xFF)})
  end

  # fe80::/10 (IPv6 link-local)
  defp blocked_ip?({w1, _, _, _, _, _, _, _}) when band(w1, 0xFFC0) == 0xFE80, do: true
  defp blocked_ip?(_), do: false

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
