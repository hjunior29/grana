defmodule Custo.Banking.Category do
  use Ecto.Schema
  import Ecto.Changeset

  schema "categories" do
    field :name, :string
    field :icon, :string
    field :color, :string
    field :is_system, :boolean, default: false

    belongs_to :user, Custo.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :icon, :color, :is_system, :user_id])
    |> validate_required([:name])
    |> unique_constraint([:name, :user_id])
  end
end
