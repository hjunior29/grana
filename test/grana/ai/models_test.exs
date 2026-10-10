defmodule Grana.AI.ModelsTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Grana.AI.Models

  defp ok(body), do: {:ok, %Req.Response{status: 200, body: body}}

  describe "Gemini" do
    test "lista só modelos que geram conteúdo de texto, Gemini primeiro e mais novos antes" do
      expect(Req, :get, fn url, opts ->
        assert url == "https://generativelanguage.googleapis.com/v1beta/models"
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
      assert hd(models).name == "Gemini 3 Pro" or hd(models).name == "gemini-3-pro"
    end
  end

  describe "OpenAI e compatíveis" do
    test "descarta embeddings, áudio e imagem e ordena pelo mais novo" do
      expect(Req, :get, fn url, opts ->
        assert url == "https://api.openai.com/v1/models"
        assert {"authorization", "Bearer sk"} in opts[:headers]

        ok(%{
          "data" => [
            %{"id" => "gpt-4.1", "created" => 100},
            %{"id" => "gpt-5-mini", "created" => 300},
            %{"id" => "text-embedding-3-large", "created" => 400},
            %{"id" => "whisper-1", "created" => 50},
            %{"id" => "gpt-image-1", "created" => 500},
            %{"id" => "gpt-5", "created" => 200}
          ]
        })
      end)

      assert {:ok, models} = Models.list(%{provider: "openai", api_key: "sk"})
      assert Enum.map(models, & &1.id) == ["gpt-5-mini", "gpt-5", "gpt-4.1"]
    end

    test "serviço compatível usa o base_url e dispensa chave" do
      expect(Req, :get, fn url, opts ->
        assert url == "http://localhost:11434/v1/models"
        assert opts[:headers] == []
        ok(%{"data" => [%{"id" => "llama3.3"}, %{"id" => "qwen3"}]})
      end)

      config = %{
        provider: "openai_compatible",
        api_key: nil,
        base_url: "http://localhost:11434/v1"
      }

      assert {:ok, [%{id: "qwen3"}, %{id: "llama3.3"}]} = Models.list(config)
    end
  end

  describe "Anthropic" do
    test "mantém a ordem da API (mais novo primeiro) e usa o nome de exibição" do
      expect(Req, :get, fn url, opts ->
        assert url == "https://api.anthropic.com/v1/models"
        assert {"x-api-key", "k"} in opts[:headers]

        ok(%{
          "data" => [
            %{"id" => "claude-opus-x", "display_name" => "Claude Opus X"},
            %{"id" => "claude-sonnet-x", "display_name" => "Claude Sonnet X"}
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
    end

    @config %{provider: "openai", api_key: "sk-cache"}
    @body %{"data" => [%{"id" => "gpt-5", "created" => 1}]}

    test "a segunda consulta não chama a API" do
      expect(Req, :get, 1, fn _url, _opts -> ok(@body) end)

      assert {:ok, [%{id: "gpt-5"}]} = Models.list(@config)
      assert {:ok, [%{id: "gpt-5"}]} = Models.list(@config)
    end

    test "erros não são guardados: a próxima consulta tenta de novo" do
      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 401, body: %{"error" => %{"message" => "x"}}}}
      end)

      expect(Req, :get, fn _url, _opts -> ok(@body) end)

      assert {:error, _} = Models.list(@config)
      assert {:ok, _} = Models.list(@config)
      assert {:ok, _} = Models.list(@config)
    end

    test "chave ou endereço diferentes têm cache próprio" do
      expect(Req, :get, 3, fn _url, _opts -> ok(@body) end)

      Models.list(@config)
      Models.list(%{@config | api_key: "sk-outra"})
      Models.list(%{provider: "openai_compatible", api_key: "sk-cache", base_url: "http://x/v1"})
      Models.list(@config)
    end

    test "não é apagado quando os dados do usuário mudam (invalidate_user)" do
      expect(Req, :get, 1, fn _url, _opts -> ok(@body) end)

      Models.list(@config)
      Grana.Cache.invalidate_user(1)
      Models.list(@config)
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
