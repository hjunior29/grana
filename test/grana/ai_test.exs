defmodule Grana.AITest do
  use Grana.DataCase, async: false
  use Mimic

  import Grana.AccountsFixtures

  alias Grana.{Accounts, AI}
  alias Grana.AI.ProviderConfig

  @models [%{id: "gpt-5", name: "gpt-5"}, %{id: "gpt-5-mini", name: "gpt-5-mini"}]

  setup do
    %{user: user_fixture()}
  end

  defp put_env_keys(keys) do
    Application.put_env(:grana, :ai_env_keys, keys)
    on_exit(fn -> Application.delete_env(:grana, :ai_env_keys) end)
  end

  describe "ProviderConfig.changeset/2" do
    test "exige tipo e nome; chave exceto em compatíveis; endereço só nos compatíveis" do
      assert %{api_key: ["informe a chave da API"]} =
               errors_on(
                 ProviderConfig.changeset(%ProviderConfig{}, %{kind: "openai", name: "X"})
               )

      assert %{base_url: ["informe o endereço da API"]} =
               errors_on(
                 ProviderConfig.changeset(%ProviderConfig{}, %{
                   kind: "openai_compatible",
                   name: "Local"
                 })
               )

      assert ProviderConfig.changeset(%ProviderConfig{}, %{
               kind: "openai_compatible",
               name: "Local",
               base_url: "http://localhost:11434/v1"
             }).valid?
    end

    test "tipo desconhecido, endereço inválido e nome longo" do
      errors =
        errors_on(
          ProviderConfig.changeset(%ProviderConfig{}, %{
            kind: "skynet",
            name: String.duplicate("a", 61),
            base_url: "ftp://x",
            api_key: "k"
          })
        )

      assert %{kind: _, name: _, base_url: _} = errors
    end

    test "apara espaços" do
      cs =
        ProviderConfig.changeset(%ProviderConfig{}, %{kind: "gemini", name: " G ", api_key: " k "})

      assert Ecto.Changeset.get_field(cs, :name) == "G"
      assert Ecto.Changeset.get_field(cs, :api_key) == "k"
    end
  end

  describe "add_provider/2" do
    test "confere a chave pela API, cifra no banco e define o padrão sugerido", %{user: user} do
      expect(AI.Models, :list, fn %{provider: "openai", api_key: "sk-segredo-longo-123"} ->
        {:ok, @models}
      end)

      assert {:ok, provider, @models, user} =
               AI.add_provider(user, %{
                 "kind" => "openai",
                 "name" => "",
                 "api_key" => "sk-segredo-longo-123"
               })

      assert provider.name == "OpenAI"
      assert user.ai_provider == "db:#{provider.id}"
      assert user.ai_model == "gpt-5-mini"

      %{rows: [[raw]]} =
        Repo.query!("SELECT api_key FROM ai_providers WHERE id = ?", [provider.id])

      refute raw =~ "segredo"
    end

    test "o segundo provedor não troca o padrão", %{user: user} do
      stub(AI.Models, :list, fn _ -> {:ok, @models} end)

      {:ok, first, _, user} = AI.add_provider(user, %{"kind" => "openai", "api_key" => "1"})
      {:ok, _second, _, user} = AI.add_provider(user, %{"kind" => "anthropic", "api_key" => "2"})

      assert user.ai_provider == "db:#{first.id}"
    end

    test "o nome só é livre nos compatíveis; nos demais vale o rótulo do tipo", %{user: user} do
      stub(AI.Models, :list, fn _ -> {:ok, @models} end)

      {:ok, openai, _, user} =
        AI.add_provider(user, %{"kind" => "openai", "name" => "Meu nome", "api_key" => "k"})

      assert openai.name == "OpenAI"

      {:ok, local, _, _} =
        AI.add_provider(user, %{
          "kind" => "openai_compatible",
          "name" => "Ollama",
          "base_url" => "http://localhost:11434/v1"
        })

      assert local.name == "Ollama"

      {:ok, unnamed, _, _} =
        AI.add_provider(user, %{"kind" => "openai_compatible", "base_url" => "http://x/v1"})

      assert unnamed.name == "Compatível com a API da OpenAI"
    end

    test "falha da API vira erro no campo certo e nada é gravado", %{user: user} do
      stub(AI.Models, :list, fn _ -> {:error, "chave ruim"} end)

      assert {:error, cs} =
               AI.add_provider(user, %{"kind" => "gemini", "name" => "G", "api_key" => "k"})

      assert %{api_key: ["chave ruim"]} = errors_on(cs)

      assert {:error, cs} =
               AI.add_provider(user, %{
                 "kind" => "openai_compatible",
                 "name" => "L",
                 "base_url" => "http://x/v1"
               })

      assert %{base_url: ["chave ruim"]} = errors_on(cs)
      assert Repo.all(ProviderConfig) == []
    end

    test "dados inválidos nem chamam a API", %{user: user} do
      reject(&AI.Models.list/1)
      assert {:error, _} = AI.add_provider(user, %{"kind" => "openai", "name" => "X"})
    end
  end

  describe "resolve/3 with the general default" do
    test "sem provedor nenhum" do
      user = user_fixture()
      assert AI.resolve(user.id, nil) == {:error, :no_api_key}
    end

    test "usa o provedor e o modelo padrão", %{user: user} do
      ai_fixture(user, %{kind: "anthropic", name: "Claude", api_key: "ant", model: "claude-x"})

      assert {:ok, config} = AI.resolve(user.id, nil)

      assert %{
               provider: "anthropic",
               name: "Claude",
               api_key: "ant",
               model: "claude-x",
               base_url: nil
             } =
               config
    end

    test "sem padrão salvo, escolhe o primeiro provedor com o modelo sugerido e grava", %{
      user: user
    } do
      put_env_keys(%{"openai" => "sk-env"})
      expect(AI.Models, :list, fn %{api_key: "sk-env"} -> {:ok, @models} end)

      assert {:ok, %{provider: "openai", model: "gpt-5-mini", api_key: "sk-env"}} =
               AI.resolve(user.id, nil)

      saved = Accounts.get_user!(user.id)
      assert saved.ai_provider == "env:openai"
      assert saved.ai_model == "gpt-5-mini"

      reject(&AI.Models.list/1)
      assert {:ok, %{model: "gpt-5-mini"}} = AI.resolve(user.id, nil)
    end

    test "se não dá para listar os modelos, não há configuração", %{user: user} do
      put_env_keys(%{"gemini" => "k"})
      stub(AI.Models, :list, fn _ -> {:error, "fora do ar"} end)
      assert AI.resolve(user.id, nil) == {:error, :no_api_key}
    end

    test "o padrão apontando para um provedor removido cai no primeiro disponível", %{user: user} do
      put_env_keys(%{"gemini" => "k"})
      {:ok, _} = AI.set_default(user, "db:999", "algum-modelo")
      stub(AI.Models, :list, fn _ -> {:ok, [%{id: "gemini-x", name: "x"}]} end)

      assert {:ok, %{provider: "gemini", model: "gemini-x"}} = AI.resolve(user.id, nil)
    end

    test "o valor antigo 'gemini' da coluna conta como sem padrão", %{user: user} do
      {:ok, _} = AI.set_default(user, "gemini", "gemini-2.0-flash")
      assert AI.resolve(user.id, nil) == {:error, :no_api_key}
    end
  end

  describe "remove_provider/2" do
    test "apaga e limpa o padrão só se era ele", %{user: user} do
      user = ai_fixture(user)
      [provider] = Repo.all(ProviderConfig)

      other =
        Repo.insert!(%ProviderConfig{
          user_id: user.id,
          kind: "openai",
          name: "Outro",
          api_key: "k"
        })

      {:ok, same} = AI.remove_provider(user, other.id)
      assert same.ai_provider == "db:#{provider.id}"

      {:ok, cleared} = AI.remove_provider(same, provider.id)
      assert cleared.ai_provider == nil
      assert cleared.ai_model == nil
      assert Repo.all(ProviderConfig) == []
    end

    test "não remove provedor de outro usuário", %{user: user} do
      other = user_fixture()
      ai_fixture(other)
      [provider] = Repo.all(ProviderConfig)

      assert_raise Ecto.NoResultsError, fn -> AI.remove_provider(user, provider.id) end
    end
  end

  test "kinds e label", %{} do
    assert {"openai", "OpenAI"} in AI.kinds()
    assert AI.label("anthropic") =~ "Claude"
  end
end
