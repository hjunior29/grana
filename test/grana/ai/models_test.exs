defmodule Grana.AI.ModelsTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Grana.AI.Models

  @catalog_url "https://models.dev/api.json"

  defp ok(body), do: {:ok, %Req.Response{status: 200, body: body}}

  # The catalog answer (`:unavailable` for a network failure) plus the provider's own API.
  defp apis(catalog, provider_fun) do
    stub(Req, :get, fn
      @catalog_url, _opts ->
        if catalog == :unavailable,
          do: {:error, %Req.TransportError{reason: :timeout}},
          else: ok(catalog)

      url, opts ->
        provider_fun.(url, opts)
    end)
  end

  defp entry(family, date, extra \\ %{}) do
    Map.merge(
      %{
        "family" => family,
        "release_date" => date,
        "tool_call" => true,
        "modalities" => %{"input" => ["text", "image"], "output" => ["text"]}
      },
      extra
    )
  end

  describe "curation with the catalog" do
    defp google_catalog do
      %{
        "google" => %{
          "models" => %{
            "gemini-4-argon" => entry("gemini", "2026-10-13"),
            "gemini-3.8-flash" => entry("gemini-flash", "2026-09-02"),
            "gemini-3.7-flash" => entry("gemini-flash", "2026-08-13"),
            "gemini-flash-latest" => entry("gemini-flash", "2026-08-13"),
            "gemini-2.5-pro" => entry("gemini-pro", "2025-06-17"),
            "gemini-3.1-flash-image" =>
              entry("gemini-flash", "2026-05-28", %{
                "modalities" => %{"input" => ["text"], "output" => ["text", "image"]}
              }),
            "gemini-omni" => entry("gemini", "2026-06-30", %{"tool_call" => false}),
            "gemma-4-31b-it" => entry("gemma", "2026-04-02")
          }
        }
      }
    end

    test "text models with tools, the newest of each family, within a year of the newest" do
      apis(google_catalog(), fn url, _opts ->
        assert url == "https://generativelanguage.googleapis.com/v1beta/models"

        ok(%{
          "models" =>
            for id <-
                  ~w(gemini-4-argon gemini-3.8-flash gemini-3.7-flash gemini-flash-latest gemini-2.5-pro
                         gemini-3.1-flash-image gemini-omni gemma-4-31b-it gemini-5-unknown text-embedding-9) do
              %{
                "name" => "models/#{id}",
                "displayName" => String.upcase(id),
                "supportedGenerationMethods" => ["generateContent"]
              }
            end
        })
      end)

      assert {:ok, models} = Models.list(%{provider: "gemini", api_key: "k"})

      # gemini-2.5-pro: more than a year before gemini-4-argon. gemini-3.7-flash and
      # gemini-flash-latest: older than gemini-3.8-flash in the same family. Image and
      # no-tools models out. Unknown models leave too: Gemini's API has no dates to tell
      # a brand-new model from an image or audio one the catalog does not list.
      assert Enum.map(models, & &1.id) == ~w(gemini-4-argon gemini-3.8-flash gemma-4-31b-it)
      assert Enum.map(models, & &1.pdf) == [false, false, false]

      assert hd(models).name == "GEMINI-4-ARGON"
    end

    test "for_pdf/1 keeps the models that read PDF files and the unknown ones" do
      models = [%{id: "a", pdf: true}, %{id: "b", pdf: false}, %{id: "c", pdf: nil}]
      assert Enum.map(Models.for_pdf(models), & &1.id) == ["a", "c"]
    end

    test "on the same date the plain id beats the dated snapshot" do
      catalog = %{
        "anthropic" => %{
          "models" => %{
            "claude-haiku-4-5" => entry("claude-haiku", "2025-10-15"),
            "claude-haiku-4-5-20251001" => entry("claude-haiku", "2025-10-15")
          }
        }
      }

      apis(catalog, fn _url, _opts ->
        ok(%{"data" => [%{"id" => "claude-haiku-4-5-20251001"}, %{"id" => "claude-haiku-4-5"}]})
      end)

      assert {:ok, [%{id: "claude-haiku-4-5"}]} =
               Models.list(%{provider: "anthropic", api_key: "k"})
    end

    test "unknown models only stay when newer than the catalog's newest for the provider" do
      apis(%{"openai" => %{"models" => %{"gpt-6" => entry("gpt", "2026-09-01")}}}, fn _url,
                                                                                      _opts ->
        ok(%{
          "data" => [
            %{"id" => "gpt-6", "created" => 1_700_000_000},
            %{"id" => "gpt-4o-2024-11-20", "created" => 1_732_000_000},
            %{"id" => "gpt-7-preview", "created" => 1_790_000_000},
            %{"id" => "gpt-5.2-codex", "created" => 1_770_000_000},
            %{"id" => "chat-latest", "created" => 1_760_000_000},
            %{"id" => "gpt-4o-audio-preview", "created" => 1_790_000_000},
            %{"id" => "sora-3", "created" => 1_790_000_000}
          ]
        })
      end)

      assert {:ok, models} = Models.list(%{provider: "openai", api_key: "sk"})
      # gpt-7-preview (2026-09-21) is newer than gpt-6 (2026-09-01) and reads as text; the
      # codex and chat-latest ids are older than the catalog, audio and video never pass.
      assert Enum.map(models, & &1.id) == ["gpt-7-preview", "gpt-6"]
    end

    test "a compatible service finds its models anywhere in the catalog" do
      catalog = %{
        "openrouter" => %{"models" => %{"openai/gpt-6" => entry("gpt", "2026-09-01")}},
        "ollama-cloud" => %{
          "models" => %{"llama-9" => entry("llama", "2026-01-01", %{"tool_call" => false})}
        }
      }

      apis(catalog, fn url, opts ->
        assert url == "http://localhost:11434/v1/models"
        assert opts[:headers] == []
        ok(%{"data" => [%{"id" => "openai/gpt-6"}, %{"id" => "llama-9"}, %{"id" => "qwen3"}]})
      end)

      config = %{
        provider: "openai_compatible",
        api_key: nil,
        base_url: "http://localhost:11434/v1"
      }

      assert {:ok, [%{id: "openai/gpt-6"}, %{id: "qwen3"}]} = Models.list(config)
    end
  end

  describe "without the catalog (heuristics only)" do
    test "Gemini: text models, Gemini first, newest versions first" do
      apis(:unavailable, fn _url, opts ->
        assert {"x-goog-api-key", "k"} in opts[:headers]

        ok(%{
          "models" => [
            %{
              "name" => "models/gemini-2.0-flash",
              "displayName" => "Gemini 2.0 Flash",
              "supportedGenerationMethods" => ["generateContent"]
            },
            %{
              "name" => "models/gemini-3-pro",
              "displayName" => "Gemini 3 Pro",
              "supportedGenerationMethods" => ["generateContent"]
            },
            %{
              "name" => "models/text-embedding-004",
              "supportedGenerationMethods" => ["embedContent"]
            },
            %{
              "name" => "models/gemini-3-flash-image",
              "supportedGenerationMethods" => ["generateContent"]
            },
            %{"name" => "models/gemma-3", "supportedGenerationMethods" => ["generateContent"]}
          ]
        })
      end)

      assert {:ok, models} = Models.list(%{provider: "gemini", api_key: "k"})
      assert Enum.map(models, & &1.id) == ["gemini-3-pro", "gemini-2.0-flash", "gemma-3"]
      assert hd(models).name == "Gemini 3 Pro"
    end

    test "OpenAI: drops embeddings, audio and image and sorts by the API date" do
      apis(:unavailable, fn url, opts ->
        assert url == "https://api.openai.com/v1/models"
        assert {"authorization", "Bearer sk"} in opts[:headers]

        ok(%{
          "data" => [
            %{"id" => "gpt-4.1", "created" => 1_700_000_000},
            %{"id" => "gpt-5-mini", "created" => 1_760_000_000},
            %{"id" => "text-embedding-3-large", "created" => 1_790_000_000},
            %{"id" => "whisper-1", "created" => 50},
            %{"id" => "gpt-image-1", "created" => 1_790_000_000},
            %{"id" => "gpt-5", "created" => 1_750_000_000}
          ]
        })
      end)

      assert {:ok, models} = Models.list(%{provider: "openai", api_key: "sk"})
      assert Enum.map(models, & &1.id) == ["gpt-5-mini", "gpt-5", "gpt-4.1"]
    end

    test "Anthropic: newest first by created_at, with the display name" do
      apis(:unavailable, fn url, opts ->
        assert url == "https://api.anthropic.com/v1/models"
        assert {"x-api-key", "k"} in opts[:headers]

        ok(%{
          "data" => [
            %{
              "id" => "claude-opus-x",
              "display_name" => "Claude Opus X",
              "created_at" => "2026-02-01T00:00:00Z"
            },
            %{
              "id" => "claude-sonnet-x",
              "display_name" => "Claude Sonnet X",
              "created_at" => "2025-09-29T00:00:00Z"
            }
          ]
        })
      end)

      assert {:ok, [%{id: "claude-opus-x", name: "Claude Opus X"}, %{id: "claude-sonnet-x"}]} =
               Models.list(%{provider: "anthropic", api_key: "k"})
    end
  end

  describe "erros" do
    test "chave inválida vira mensagem com o nome do provedor" do
      stub(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 401, body: %{"error" => %{"message" => "bad"}}}}
      end)

      assert {:error, msg} = Models.list(%{provider: "openai", api_key: "x", name: "OpenAI"})
      assert msg =~ "Chave de API inválida para OpenAI"
    end

    test "resposta que não é JSON de modelos" do
      stub(Req, :get, fn _url, _opts -> ok("<html>não é a API</html>") end)

      assert {:error, msg} =
               Models.list(%{provider: "openai_compatible", base_url: "http://x/v1"})

      assert msg =~ "não parece uma lista de modelos"
    end

    test "falha de rede" do
      stub(Req, :get, fn _url, _opts -> {:error, %Req.TransportError{reason: :econnrefused}} end)

      assert {:error, "Não foi possível conectar" <> _} =
               Models.list(%{provider: "anthropic", api_key: "k"})
    end
  end

  describe "cache" do
    setup do
      start_supervised!({Cachex, name: Grana.Cache.cache_name()})
      Application.put_env(:grana, Grana.Cache, enabled: true, ttl_seconds: 300)
      on_exit(fn -> Application.put_env(:grana, Grana.Cache, enabled: false) end)
      %{calls: start_supervised!({Agent, fn -> 0 end})}
    end

    @config %{provider: "openai", api_key: "sk-cache"}
    @body %{"data" => [%{"id" => "gpt-5", "created" => 1}]}

    # Answers the provider's API (counting the calls) and the catalog.
    defp provider_api(calls, reply \\ fn -> ok(@body) end) do
      stub(Req, :get, fn
        @catalog_url, _opts ->
          ok(%{})

        _url, _opts ->
          Agent.update(calls, &(&1 + 1))
          reply.()
      end)
    end

    test "a segunda consulta não chama a API", %{calls: calls} do
      provider_api(calls)

      assert {:ok, [%{id: "gpt-5"}]} = Models.list(@config)
      assert {:ok, [%{id: "gpt-5"}]} = Models.list(@config)
      assert Agent.get(calls, & &1) == 1
    end

    test "cached/1 só consulta o cache, sem rede", %{calls: calls} do
      assert Models.cached(@config) == :miss

      provider_api(calls)
      Models.list(@config)

      assert {:ok, [%{id: "gpt-5"}]} = Models.cached(@config)
      assert Models.cached(%{@config | api_key: "outra"}) == :miss
      assert Agent.get(calls, & &1) == 1
    end

    test "erros não são guardados: a próxima consulta tenta de novo", %{calls: calls} do
      provider_api(calls, fn ->
        if Agent.get(calls, & &1) == 1,
          do: {:ok, %Req.Response{status: 401, body: %{"error" => %{"message" => "x"}}}},
          else: ok(@body)
      end)

      assert {:error, _} = Models.list(@config)
      assert {:ok, _} = Models.list(@config)
      assert {:ok, _} = Models.list(@config)
      assert Agent.get(calls, & &1) == 2
    end

    test "chave ou endereço diferentes têm cache próprio", %{calls: calls} do
      provider_api(calls)

      Models.list(@config)
      Models.list(%{@config | api_key: "sk-outra"})
      Models.list(%{provider: "openai_compatible", api_key: "sk-cache", base_url: "http://x/v1"})
      Models.list(@config)

      assert Agent.get(calls, & &1) == 3
    end

    test "o catálogo também fica em cache, e nada é apagado com os dados do usuário", %{
      calls: calls
    } do
      provider_api(calls)

      Models.list(@config)
      Grana.Cache.invalidate_user(1)
      Models.list(@config)

      assert Agent.get(calls, & &1) == 1
      assert {:ok, %{}} = Grana.AI.Catalog.load()
      stub(Req, :get, fn _url, _opts -> flunk("the catalog must come from the cache") end)
      assert {:ok, %{}} = Grana.AI.Catalog.load()
    end
  end

  describe "suggest/2" do
    test "prefere a família rápida de cada provedor, senão o primeiro" do
      gemini = [%{id: "gemini-3-pro"}, %{id: "gemini-3-flash-lite"}, %{id: "gemini-3-flash"}]
      assert Models.suggest("gemini", gemini) == "gemini-3-flash"

      anthropic = [%{id: "claude-opus-x"}, %{id: "claude-sonnet-x"}]
      assert Models.suggest("anthropic", anthropic) == "claude-sonnet-x"

      openai = [%{id: "gpt-5"}, %{id: "gpt-5-mini"}]
      assert Models.suggest("openai", openai) == "gpt-5-mini"

      assert Models.suggest("openai_compatible", [%{id: "llama"}, %{id: "qwen"}]) == "llama"
      assert Models.suggest("openai", [%{id: "o3"}]) == "o3"
      assert Models.suggest("openai", []) == nil
    end
  end
end
