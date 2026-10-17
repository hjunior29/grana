defmodule Grana.Banking.RecurringRule do
  @moduledoc """
  Regra de recorrência por comerciante (espelha `CategoryRule`).

  Quando o usuário marca uma despesa como fixa/variável, gravamos uma regra com
  o `pattern` (nome normalizado do comerciante) e o `mode`. Essas regras valem
  para importações futuras e definem como o comerciante entra na análise.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @modes ~w(fixed variable)

  schema "recurring_rules" do
    field :pattern, :string
    field :mode, :string

    belongs_to :user, Grana.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:pattern, :mode])
    |> validate_required([:pattern, :mode, :user_id])
    |> validate_inclusion(:mode, @modes)
    |> unique_constraint([:user_id, :pattern])
  end

  def modes, do: @modes
end
