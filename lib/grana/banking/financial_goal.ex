defmodule Grana.Banking.FinancialGoal do
  use Ecto.Schema
  import Ecto.Changeset

  @types ~w(expense_limit income_goal investment_goal category_limit)

  schema "financial_goals" do
    field :type, :string
    field :target_value, :decimal
    field :active, :boolean, default: true

    belongs_to :user, Grana.Accounts.User
    belongs_to :category, Grana.Banking.Category

    timestamps(type: :utc_datetime)
  end

  def changeset(goal, attrs) do
    user_id = goal.user_id || attrs[:user_id] || attrs["user_id"]

    goal
    |> Map.put(:user_id, user_id)
    |> cast(attrs, [:type, :target_value, :active, :category_id])
    |> validate_required([:type, :target_value, :user_id],
      message: "não pode ficar em branco"
    )
    |> validate_inclusion(:type, @types, message: "tipo inválido")
    |> validate_number(:target_value,
      greater_than: 0,
      message: "deve ser maior que zero"
    )
    |> maybe_require_category()
    |> unique_constraint([:user_id, :type],
      name: :financial_goals_user_type_active_idx,
      message: "Já existe uma meta ativa desse tipo"
    )
    |> unique_constraint([:user_id, :type],
      name: :financial_goals_user_id_type_index,
      message: "Já existe uma meta ativa desse tipo"
    )
    |> unique_constraint([:user_id, :type, :category_id],
      name: :financial_goals_user_type_category_active_idx,
      message: "Já existe uma meta ativa para essa categoria"
    )
    |> unique_constraint([:user_id, :type, :category_id],
      name: :financial_goals_user_id_type_category_id_index,
      message: "Já existe uma meta ativa para essa categoria"
    )
  end

  defp maybe_require_category(changeset) do
    if get_field(changeset, :type) == "category_limit" do
      validate_required(changeset, [:category_id])
    else
      put_change(changeset, :category_id, nil)
    end
  end

  def type_label("expense_limit"), do: "Limite de Gastos"
  def type_label("income_goal"), do: "Meta de Receita"
  def type_label("investment_goal"), do: "Meta de Investimento"
  def type_label("category_limit"), do: "Limite por Categoria"
  def type_label(_), do: "Meta"

  def type_icon("expense_limit"), do: "hero-banknotes"
  def type_icon("income_goal"), do: "hero-currency-dollar"
  def type_icon("investment_goal"), do: "hero-chart-bar"
  def type_icon("category_limit"), do: "hero-tag"
  def type_icon(_), do: "hero-flag"

  def types, do: @types
end
