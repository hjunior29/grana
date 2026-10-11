defmodule Grana.Banking.SavedSearch do
  use Ecto.Schema
  import Ecto.Changeset

  alias Grana.Banking.Search

  schema "saved_searches" do
    field :name, :string
    field :query, :string

    belongs_to :user, Grana.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(saved_search, attrs) do
    saved_search
    |> cast(attrs, [:name, :query])
    |> update_change(:name, &String.trim/1)
    |> update_change(:query, &String.trim/1)
    |> validate_required([:name, :query])
    |> validate_length(:name, max: 60)
    |> validate_change(:query, &validate_query/2)
    |> unique_constraint(:name,
      name: :saved_searches_user_id_name_index,
      message: "já existe uma busca com esse nome"
    )
  end

  defp validate_query(:query, query) do
    case Search.parse(query) do
      {:ok, _search} -> []
      {:error, message} -> [query: message]
    end
  end
end
