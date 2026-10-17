defmodule Grana.Banking.InternalTransferRule do
  @moduledoc """
  Regra aprendida por contraparte quando o usuário marca/desmarca uma
  transferência como interna (espelha `RecurringRule`).

  - `pattern`: contraparte normalizada — `"cpf:<6 dígitos do meio>"` quando o CPF
    mascarado está disponível, senão `"name:<nome normalizado>"`.
  - `kind`: `"internal"` força a transação a contar como transferência interna;
    `"external"` força como externa (sobrepõe a heurística automática).

  Valem para importações futuras e para o re-cálculo de `detect_internal_transfers`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(internal external)

  schema "internal_transfer_rules" do
    field :pattern, :string
    field :kind, :string

    belongs_to :user, Grana.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:pattern, :kind])
    |> validate_required([:pattern, :kind, :user_id])
    |> validate_inclusion(:kind, @kinds)
    |> unique_constraint([:user_id, :pattern])
  end

  def kinds, do: @kinds
end
