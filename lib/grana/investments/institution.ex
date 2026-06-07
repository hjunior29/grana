defmodule Grana.Investments.Institution do
  use Ecto.Schema
  import Ecto.Changeset

  schema "investment_institutions" do
    field :name, :string
    field :slug, :string
    field :logo_path, :string
    field :is_system, :boolean, default: false

    belongs_to :user, Grana.Accounts.User

    has_many :statements, Grana.Investments.Statement, foreign_key: :institution_id
    has_many :transactions, Grana.Investments.Transaction, foreign_key: :institution_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Derives logo path from institution slug, checking for a static file.
  Falls back to the logo_path stored in the database.

  Instituições vindas de extrato bancário usam slug `ext-<banco>` (ex.: `ext-nubank`):
  nesse caso o logo é o do próprio banco (`/images/<banco>-logo.png`).
  """
  def logo_url(%__MODULE__{slug: "ext-" <> bank, logo_path: db_path}) do
    static_file("/images/#{bank}-logo.png") || db_path
  end

  def logo_url(%__MODULE__{slug: slug, logo_path: db_path}) do
    static_file("/images/#{slug}-logo.png") || db_path
  end

  def logo_url(_), do: nil

  defp static_file(path) do
    if File.exists?(Path.join(:code.priv_dir(:grana), "static#{path}")), do: path
  end

  def changeset(institution, attrs) do
    institution
    |> cast(attrs, [:name, :slug, :logo_path, :is_system, :user_id])
    |> maybe_generate_slug()
    |> validate_required([:name, :slug, :user_id])
    |> unique_constraint([:slug, :user_id])
  end

  defp maybe_generate_slug(changeset) do
    case get_change(changeset, :slug) do
      nil ->
        case get_change(changeset, :name) do
          nil -> changeset
          name -> put_change(changeset, :slug, __MODULE__.Slug.slugify(name))
        end

      _ ->
        changeset
    end
  end

  defmodule Slug do
    def slugify(name) do
      name
      |> String.downcase()
      |> String.replace(~r/[^\w\s-]/, "")
      |> String.replace(~r/[\s_]+/, "-")
      |> String.trim("-")
    end
  end
end
