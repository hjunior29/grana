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
    |> cast(attrs, [:name, :icon, :color, :kind, :user_id])
    |> validate_required([:name])
    |> validate_inclusion(:kind, ["expense", "investment", "income"])
    |> validate_format(:color, ~r/^#[0-9A-Fa-f]{3,8}$/, message: "cor inválida")
    |> unique_constraint([:name, :user_id])
  end

  @doc """
  Changeset for system-managed categories. `:is_system` is intentionally not
  castable in the public `changeset/2` to prevent users from forging
  undeletable system categories via mass assignment.
  """
  def system_changeset(category, attrs) do
    attrs = normalize(attrs)

    category
    |> changeset(attrs)
    |> put_change(:is_system, Map.get(attrs, "is_system", false))
  end

  defp normalize(attrs) do
    Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
  end
end
