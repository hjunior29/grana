defmodule Grana.Chat.Message do
  @moduledoc """
  A chat message. Assistant messages keep the tools they called (`tool_calls`: name,
  arguments, result and details for the screen) and the provider and model that answered.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "chat_messages" do
    field :role, :string
    field :content, :string
    field :tool_calls, {:array, :map}, default: []
    field :ai_provider, :string
    field :ai_model, :string

    belongs_to :conversation, Grana.Chat.Conversation

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:role, :content, :tool_calls, :ai_provider, :ai_model])
    |> validate_required([:role, :content])
    |> validate_inclusion(:role, ["user", "assistant"])
  end
end
