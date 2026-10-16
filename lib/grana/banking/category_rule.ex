defmodule Grana.Banking.CategoryRule do
  use Ecto.Schema
  import Ecto.Changeset

  schema "category_rules" do
    field :pattern, :string

    belongs_to :user, Grana.Accounts.User
    belongs_to :category, Grana.Banking.Category

    timestamps(type: :utc_datetime)
  end

  def changeset(rule, attrs) do
    user_id = rule.user_id || attrs[:user_id] || attrs["user_id"]

    rule
    |> Map.put(:user_id, user_id)
    |> cast(attrs, [:pattern, :category_id])
    |> validate_required([:pattern, :user_id, :category_id])
    |> unique_constraint([:pattern, :user_id])
    |> update_change(:pattern, &String.downcase/1)
  end
end
