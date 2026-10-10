defmodule GranaWeb.UserLive.SettingsAiTest do
  use GranaWeb.ConnCase, async: false
  use Mimic

  import Phoenix.LiveViewTest
  import Grana.AccountsFixtures

  alias Grana.{Accounts, AI}
  alias Grana.AI.ProviderConfig

  setup :set_mimic_global

  @models [
    %{id: "gpt-5", name: "gpt-5"},
    %{id: "gpt-5-mini", name: "gpt-5-mini"},
    %{id: "gpt-4.1", name: "gpt-4.1"}
  ]

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  defp put_env_keys(keys) do
    Application.put_env(:grana, :ai_env_keys, keys)
    on_exit(fn -> Application.delete_env(:grana, :ai_env_keys) end)
  end

  defp add_openai(lv, key \\ "sk-segredo") do
    lv |> element("#ai-add-provider") |> render_click()

    lv
    |> form("#ai-provider-form", provider: %{kind: "openai", api_key: key})
    |> render_submit()
  end

  test "o nome só aparece para provedores compatíveis", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/settings")
    lv |> element("#ai-add-provider") |> render_click()

    for kind <- ~w(gemini openai anthropic) do
      lv |> form("#ai-provider-form", provider: %{kind: kind}) |> render_change()
      refute has_element?(lv, "#provider_name")
    end

    lv |> form("#ai-provider-form", provider: %{kind: "openai_compatible"}) |> render_change()
    assert has_element?(lv, "#provider_name")
  end

  test "sem provedores explica como cadastrar", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    assert has_element?(lv, "#ai-no-providers")
    refute has_element?(lv, "#ai-default-form")
    refute has_element?(lv, "#ai-provider-form")
  end

  test "cadastra um provedor conferindo a chave nos modelos da API e o torna padrão", %{
    conn: conn,
    user: user
  } do
    expect(AI.Models, :list, fn config ->
      assert %{provider: "openai", api_key: "sk-segredo"} = config
      {:ok, @models}
    end)

    {:ok, lv, _html} = live(conn, ~p"/users/settings")
    html = add_openai(lv)

    assert html =~ "OpenAI cadastrado"
    refute html =~ "sk-segredo"
    assert has_element?(lv, "#ai-provider-list", "OpenAI")
    assert has_element?(lv, "#ai-provider-list .badge", "chave salva")

    user = Accounts.get_user!(user.id)

    assert [%ProviderConfig{kind: "openai", name: "OpenAI", api_key: "sk-segredo"} = provider] =
             Grana.Repo.all(ProviderConfig)

    assert user.ai_provider == "db:#{provider.id}"
    assert user.ai_model == "gpt-5-mini"
  end

  test "chave recusada pela API não cadastra e mostra o motivo sem devolver a chave", %{
    conn: conn
  } do
    expect(AI.Models, :list, fn _ -> {:error, "Chave de API inválida para OpenAI."} end)

    {:ok, lv, _html} = live(conn, ~p"/users/settings")
    html = add_openai(lv)

    assert html =~ "Chave de API inválida"
    refute html =~ "sk-segredo"
    assert has_element?(lv, "#ai-provider-form")
    assert Grana.Repo.all(ProviderConfig) == []
  end

  test "provedor compatível exige o endereço; a chave é opcional", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/users/settings")
    lv |> element("#ai-add-provider") |> render_click()

    lv |> form("#ai-provider-form", provider: %{kind: "openai_compatible"}) |> render_change()
    assert has_element?(lv, "#provider_base_url")

    html =
      lv
      |> form("#ai-provider-form", provider: %{kind: "openai_compatible", name: "Ollama"})
      |> render_submit()

    assert html =~ "informe o endereço da API"

    expect(AI.Models, :list, fn config ->
      assert config.base_url == "http://localhost:11434/v1"
      assert config.api_key in [nil, ""]
      {:ok, [%{id: "llama3.3", name: "llama3.3"}]}
    end)

    lv
    |> form("#ai-provider-form",
      provider: %{
        kind: "openai_compatible",
        name: "Ollama",
        base_url: "http://localhost:11434/v1"
      }
    )
    |> render_submit()

    assert [%ProviderConfig{name: "Ollama"}] = Grana.Repo.all(ProviderConfig)
    assert Accounts.get_user!(user.id).ai_model == "llama3.3"
  end

  test "não permite dois provedores com o mesmo nome", %{conn: conn, user: user} do
    ai_fixture(user, %{name: "OpenAI", kind: "openai"})
    stub(AI.Models, :list, fn _ -> {:ok, @models} end)

    {:ok, lv, _html} = live(conn, ~p"/users/settings")
    html = add_openai(lv)

    assert html =~ "OpenAI já está cadastrado"
  end

  test "o padrão mostra os modelos vindos da API e salva a escolha", %{conn: conn, user: user} do
    user = ai_fixture(user, %{kind: "openai", name: "OpenAI", model: "gpt-5"})
    stub(AI.Models, :list, fn _ -> {:ok, @models} end)

    {:ok, lv, _html} = live(conn, ~p"/users/settings")
    render_async(lv)

    assert has_element?(lv, "#ai-default-model option", "gpt-4.1")
    assert has_element?(lv, "#ai-default-model option[selected]", "gpt-5")

    lv
    |> form("#ai-default-form", default: %{provider: user.ai_provider, model: "gpt-4.1"})
    |> render_submit()

    assert Accounts.get_user!(user.id).ai_model == "gpt-4.1"
  end

  test "um modelo salvo que saiu da lista continua selecionável", %{conn: conn, user: user} do
    ai_fixture(user, %{kind: "openai", name: "OpenAI", model: "gpt-antigo"})
    stub(AI.Models, :list, fn _ -> {:ok, @models} end)

    {:ok, lv, _html} = live(conn, ~p"/users/settings")
    render_async(lv)

    assert has_element?(lv, "#ai-default-model option[selected]", "gpt-antigo")
  end

  test "falha ao listar modelos mostra o erro", %{conn: conn, user: user} do
    ai_fixture(user)
    stub(AI.Models, :list, fn _ -> {:error, "Chave de API inválida para Google Gemini."} end)

    {:ok, lv, _html} = live(conn, ~p"/users/settings")
    html = render_async(lv)

    assert html =~ "Chave de API inválida"
    assert has_element?(lv, "#ai-models-error")
  end

  test "trocar de provedor carrega os modelos dele", %{conn: conn, user: user} do
    user = ai_fixture(user, %{kind: "openai", name: "OpenAI"})

    Grana.Repo.insert!(%ProviderConfig{
      user_id: user.id,
      kind: "anthropic",
      name: "Claude",
      api_key: "k"
    })

    stub(AI.Models, :list, fn
      %{provider: "anthropic"} -> {:ok, [%{id: "claude-sonnet-x", name: "Claude Sonnet X"}]}
      _ -> {:ok, @models}
    end)

    {:ok, lv, _html} = live(conn, ~p"/users/settings")
    render_async(lv)

    lv
    |> form("#ai-default-form",
      default: %{provider: "db:#{anthropic_id()}", model: "gemini-test-model"}
    )
    |> render_change()

    render_async(lv)
    assert has_element?(lv, "#ai-default-model option", "Claude Sonnet X")
  end

  defp anthropic_id, do: Grana.Repo.get_by!(ProviderConfig, kind: "anthropic").id

  test "remove um provedor e limpa o padrão se era ele", %{conn: conn, user: user} do
    ai_fixture(user)
    stub(AI.Models, :list, fn _ -> {:ok, @models} end)

    {:ok, lv, _html} = live(conn, ~p"/users/settings")
    [provider] = Grana.Repo.all(ProviderConfig)

    lv |> element("#ai-remove-#{provider.id}") |> render_click()

    assert has_element?(lv, "#ai-no-providers")
    assert Grana.Repo.all(ProviderConfig) == []
    assert Accounts.get_user!(user.id).ai_provider == nil
  end

  describe "provedores do .env" do
    test "aparecem sem edição, sem expor a chave, e viram o padrão sozinhos", %{
      conn: conn,
      user: user
    } do
      put_env_keys(%{"gemini" => "AIza-do-env", "openai" => nil})

      stub(AI.Models, :list, fn %{api_key: "AIza-do-env"} ->
        {:ok, [%{id: "gemini-flash-x", name: "Gemini Flash X"}]}
      end)

      {:ok, lv, html} = live(conn, ~p"/users/settings")
      html = html <> render_async(lv)

      refute html =~ "AIza-do-env"
      assert has_element?(lv, "#ai-provider-env\\:gemini .badge", ".env")
      refute has_element?(lv, "#ai-provider-env\\:gemini button")

      user = Accounts.get_user!(user.id)
      assert user.ai_provider == "env:gemini"
      assert user.ai_model == "gemini-flash-x"
    end

    test "o env tem os três provedores conhecidos", %{user: user} do
      put_env_keys(%{"gemini" => "a", "openai" => "b", "anthropic" => "c", "outro" => "d"})

      assert [{"gemini", :env}, {"openai", :env}, {"anthropic", :env}] =
               user |> AI.list_providers() |> Enum.map(&{&1.kind, &1.source})
    end
  end
end
