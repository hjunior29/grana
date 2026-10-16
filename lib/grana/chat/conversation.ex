defmodule Grana.Chat.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "chat_conversations" do
    field :title, :string

    belongs_to :user, Grana.Accounts.User
    has_many :messages, Grana.Chat.Message, preload_order: [asc: :id]

    timestamps(type: :utc_datetime)
  end

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title])
    |> validate_required([:title])
  end
end
