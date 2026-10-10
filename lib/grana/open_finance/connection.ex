defmodule Grana.OpenFinance.Connection do
  @moduledoc """
  Uma conexão (Item, na nomenclatura da Pluggy) com uma instituição financeira.
  Com o conector MeuPluggy, cada banco autorizado no Meu Pluggy vira uma conexão.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "open_finance_connections" do
    field :item_id, :string
    field :connector_id, :integer
    field :connector_name, :string
    field :connector_image_url, :string
    # Banco no vocabulário dos uploads ("nubank", "bradesco"...), deduzido das contas.
    field :bank, :string
    # "PF" ou "PJ", pelo documento da identidade (CPF/CNPJ) na Pluggy.
    field :holder_type, :string
    field :status, :string
    field :execution_status, :string
    field :error_message, :string
    field :pluggy_updated_at, :utc_datetime
    field :consent_expires_at, :utc_datetime
    field :last_synced_at, :utc_datetime
    field :sync_error, :string

    belongs_to :user, Grana.Accounts.User
    has_many :accounts, Grana.OpenFinance.Account

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset com os metadados vindos do Item da Pluggy (`user_id` e `item_id` são setados no struct)."
  def item_changeset(connection, attrs) do
    connection
    |> cast(attrs, [
      :bank,
      :holder_type,
      :connector_id,
      :connector_name,
      :connector_image_url,
      :status,
      :execution_status,
      :error_message,
      :pluggy_updated_at,
      :consent_expires_at
    ])
    |> validate_required([:status])
    |> unique_constraint(:item_id)
  end

  def sync_changeset(connection, attrs) do
    cast(connection, attrs, [:last_synced_at, :sync_error])
  end
end
