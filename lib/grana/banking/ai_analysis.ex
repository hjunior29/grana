defmodule Grana.Banking.AIAnalysis do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ai_analyses" do
    field :prompt, :string
    field :filters_json, :map
    field :result_json, :map
    field :ai_provider, :string
    field :ai_model, :string

    belongs_to :user, Grana.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(analysis, attrs) do
    analysis
    |> cast(attrs, [:prompt, :filters_json, :result_json, :ai_provider, :ai_model, :user_id])
    |> validate_required([:result_json, :user_id])
  end
end
