defmodule Grana.AI.CatalogTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Grana.AI.Catalog

  @url "https://models.dev/api.json"

  defp ok(body), do: {:ok, %Req.Response{status: 200, body: body}}

  test "load/0 keeps only what the curation needs, per provider" do
    stub(Req, :get, fn @url, _opts ->
      ok(%{
        "google" => %{
          "models" => %{
            "gemini-9-flash" => %{
              "family" => "gemini-flash",
              "release_date" => "2026-09-02",
              "tool_call" => true,
              "modalities" => %{"input" => ["text", "image", "pdf"], "output" => ["text"]},
              "cost" => %{"input" => 1}
            },
            "veo-9" => %{
              "family" => "veo",
              "release_date" => "not a date",
              "modalities" => %{"input" => ["text"], "output" => ["video"]}
            }
          }
        }
      })
    end)

    assert {:ok, catalog} = Catalog.load()

    assert catalog == %{
             "google" => %{
               "gemini-9-flash" => %{
                 family: "gemini-flash",
                 released: ~D[2026-09-02],
                 text?: true,
                 tools?: true,
                 pdf?: true
               },
               "veo-9" => %{
                 family: "veo",
                 released: nil,
                 text?: false,
                 tools?: false,
                 pdf?: false
               }
             }
           }

    assert Catalog.lookup(catalog, "gemini", "gemini-9-flash").family == "gemini-flash"
    assert Catalog.lookup(catalog, "openai", "gemini-9-flash") == nil
    # Compatible services carry anyone's models: the whole catalog is searched.
    assert Catalog.lookup(catalog, "openai_compatible", "gemini-9-flash").tools?
  end

  test "load/0 is unavailable on errors and on answers that are not the catalog" do
    stub(Req, :get, fn @url, _opts -> {:error, %Req.TransportError{reason: :timeout}} end)
    assert Catalog.load() == :unavailable

    stub(Req, :get, fn @url, _opts -> ok("<html>") end)
    assert Catalog.load() == :unavailable

    stub(Req, :get, fn @url, _opts -> {:ok, %Req.Response{status: 503, body: ""}} end)
    assert Catalog.load() == :unavailable
  end
end
