defmodule Grana.Banking.Category do
  use Ecto.Schema
  import Ecto.Changeset

  schema "categories" do
    field :name, :string
    field :icon, :string
    field :color, :string
    field :kind, :string, default: "expense"
    field :is_system, :boolean, default: false

    belongs_to :user, Grana.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :icon, :color, :kind, :is_system, :user_id])
    |> validate_required([:name])
    |> validate_inclusion(:kind, ["expense", "investment", "income"])
    |> unique_constraint([:name, :user_id])
  end
end
