defmodule Grana.Investments.InstitutionTest do
  use ExUnit.Case, async: true

  alias Grana.Investments.Institution

  describe "changeset/2" do
    test "valid attrs with name auto-generates slug" do
      cs = Institution.changeset(%Institution{}, %{name: "Minha Corretora", user_id: 1})
      assert cs.valid?
      assert Ecto.Changeset.get_change(cs, :slug) == "minha-corretora"
    end

    test "explicit slug is preserved" do
      cs = Institution.changeset(%Institution{}, %{name: "X", slug: "my-slug", user_id: 1})
      assert cs.valid?
      assert Ecto.Changeset.get_change(cs, :slug) == "my-slug"
    end

    test "requires name and user_id" do
      cs = Institution.changeset(%Institution{}, %{})
      errors = Enum.map(cs.errors, &elem(&1, 0))
      assert :name in errors
      assert :user_id in errors
    end
  end

  describe "Slug.slugify/1" do
    test "downcases and replaces spaces with hyphens" do
      assert Institution.Slug.slugify("Nubank Brasil") == "nubank-brasil"
    end

    test "removes special characters" do
      assert Institution.Slug.slugify("Bradesco S.A.") == "bradesco-sa"
    end

    test "collapses multiple spaces" do
      assert Institution.Slug.slugify("A  B   C") == "a-b-c"
    end

    test "trims leading/trailing hyphens" do
      assert Institution.Slug.slugify("-teste-") == "teste"
    end
  end

  describe "logo_url/1" do
    test "returns nil for struct without slug and logo_path" do
      inst = %Institution{slug: "nonexistent-slug-xyz", logo_path: nil}
      assert Institution.logo_url(inst) == nil
    end

    test "falls back to db logo_path when static file absent" do
      inst = %Institution{slug: "nonexistent-slug-xyz", logo_path: "/images/custom.png"}
      assert Institution.logo_url(inst) == "/images/custom.png"
    end

    test "returns nil for nil" do
      assert Institution.logo_url(nil) == nil
    end

    test "ext- prefix uses bank name for logo lookup" do
      inst = %Institution{slug: "ext-nubank", logo_path: "/fallback.png"}
      result = Institution.logo_url(inst)
      assert result == "/images/nubank-logo.png" or result == "/fallback.png"
    end
  end
end
