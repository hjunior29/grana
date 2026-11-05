defmodule Grana.AISpecialistsTest do
  use Grana.DataCase, async: false
  use Mimic

  import Grana.AccountsFixtures

  alias Grana.AI
  alias Grana.AI.ChatModel
  alias Grana.AI.ProviderConfig
  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.ChatModels.ChatGoogleAI
  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.ChatModels.ChatOpenAICompatible

  setup do
    user = user_fixture() |> ai_fixture()

    other =
      Repo.insert!(%ProviderConfig{
        user_id: user.id,
        kind: "anthropic",
        name: "Anthropic (Claude)",
        api_key: "sk-ant"
      })

    %{user: user, other_ref: ProviderConfig.ref(other)}
  end

  describe "resolve/3" do
    test "without a choice or specialist default, uses the general default", %{user: user} do
      assert {:ok, %{provider: "gemini", model: "gemini-test-model", name: "Google Gemini"}} =
               AI.resolve(user, "analysis")
    end

    test "the specialist default wins over the general one", %{user: user, other_ref: ref} do
      {:ok, user} = AI.set_specialist_default(user, "analysis", AI.choice(ref, "claude-x"))

      assert {:ok, %{provider: "anthropic", model: "claude-x", api_key: "sk-ant"}} =
               AI.resolve(user, "analysis")

      assert {:ok, %{model: "gemini-test-model"}} = AI.resolve(user, "chat")
    end

    test "the choice of the call wins over every default", %{user: user, other_ref: ref} do
      {:ok, user} = AI.set_specialist_default(user, "search", AI.choice(ref, "claude-x"))

      assert {:ok, %{model: "claude-y"}} =
               AI.resolve(user.id, "search", AI.choice(ref, "claude-y"))
    end

    test "choices pointing to unknown providers are skipped", %{user: user} do
      {:ok, user} = AI.set_specialist_default(user, "chat", "db:999999|ghost")

      assert {:ok, %{model: "gemini-test-model"}} = AI.resolve(user, "chat", "env:openai|gpt")
      assert {:ok, %{model: "gemini-test-model"}} = AI.resolve(user, "chat", "garbage")
    end

    test "a blank choice clears the specialist default", %{user: user, other_ref: ref} do
      {:ok, user} = AI.set_specialist_default(user, "chat", AI.choice(ref, "claude-x"))
      {:ok, user} = AI.set_specialist_default(user, "chat", "")

      assert user.ai_specialists == %{}
      assert AI.specialist_choice(user, "chat") == nil
    end
  end

  test "describe/2 reports the effective default without the network", %{
    user: user,
    other_ref: ref
  } do
    assert AI.describe(user, "search") == {"Google Gemini", "gemini-test-model"}

    {:ok, user} = AI.set_specialist_default(user, "search", AI.choice(ref, "claude-x"))
    assert AI.describe(user, "search") == {"Anthropic (Claude)", "claude-x"}

    assert AI.describe(user_fixture(), "search") == nil
  end

  test "model_choices/1 lists every provider with its models", %{user: user} do
    stub(AI.Models, :list, fn %{provider: kind} ->
      {:ok, [%{id: "#{kind}-1", name: "#{kind} 1"}]}
    end)

    assert [
             %{name: "Google Gemini", models: {:ok, [%{id: "gemini-1"}]}},
             %{name: "Anthropic (Claude)", models: {:ok, [%{id: "anthropic-1"}]}}
           ] = AI.model_choices(user)
  end

  test "removing a provider drops the specialist defaults that used it", %{
    user: user,
    other_ref: ref
  } do
    {:ok, user} = AI.set_specialist_default(user, "analysis", AI.choice(ref, "claude-x"))
    "db:" <> id = ref

    {:ok, user} = AI.remove_provider(user, String.to_integer(id))

    assert user.ai_specialists == %{}
    assert {:ok, %{provider: "gemini"}} = AI.resolve(user, "analysis")
  end

  describe "ChatModel.new/2" do
    test "builds the LangChain model of each provider kind" do
      assert %ChatGoogleAI{model: "g", api_key: "k", temperature: 0.2} =
               ChatModel.new(%{provider: "gemini", model: "g", api_key: "k"}, temperature: 0.2)

      assert %ChatOpenAI{model: "o", max_tokens: 100} =
               ChatModel.new(%{provider: "openai", model: "o", api_key: "k"}, max_tokens: 100)

      assert %ChatAnthropic{model: "a", max_tokens: 50, receive_timeout: 5} =
               ChatModel.new(%{provider: "anthropic", model: "a", api_key: "k"},
                 max_tokens: 50,
                 receive_timeout: 5
               )

      assert %ChatOpenAICompatible{
               endpoint: "http://localhost:11434/v1/chat/completions",
               api_key: nil
             } =
               ChatModel.new(%{
                 provider: "openai_compatible",
                 model: "llama",
                 api_key: "",
                 base_url: "http://localhost:11434/v1/"
               })
    end

    test "default_temperature/1 goes back to what the provider accepts" do
      assert %{temperature: 1.0} = ChatModel.default_temperature(%ChatOpenAI{temperature: 0.1})

      assert %{temperature: nil} =
               ChatModel.default_temperature(%ChatOpenAICompatible{temperature: 0.1})
    end
  end

  describe "LLM.run/2" do
    alias Grana.AI.LLM
    alias LangChain.Chains.LLMChain
    alias LangChain.Message

    defp chain(temperature) do
      %{llm: ChatOpenAI.new!(%{model: "gpt-5", api_key: "k", temperature: temperature})}
      |> LLMChain.new!()
      |> LLMChain.add_message(Message.new_user!("oi"))
    end

    test "retries once with the default temperature when the model rejects it" do
      agent =
        Grana.LLMStub.script([
          {:error, "Unsupported value: 'temperature' does not support 0.1 with this model."},
          "olá"
        ])

      assert {:ok, result} = LLM.run(chain(0.1))
      assert LLM.last_text(result) == "olá"
      assert [{%{temperature: 0.1}, _}, {%{temperature: 1.0}, _}] = Grana.LLMStub.calls(agent)
    end

    test "a second temperature error is reported" do
      Grana.LLMStub.script([
        {:error, "temperature not supported"},
        {:error, "temperature still not supported"}
      ])

      assert {:error, "A IA respondeu com erro: temperature still" <> _} = LLM.run(chain(0.1))
    end

    test "errors without a message get a generic one" do
      stub(ChatOpenAI, :call, fn _model, _messages, _tools ->
        {:error, LangChain.LangChainError.exception(type: "x", message: nil)}
      end)

      assert {:error, "Não foi possível falar com a IA." <> _} = LLM.run(chain(0.5))

      stub(ChatOpenAI, :call, fn _model, _messages, _tools ->
        {:error, LangChain.LangChainError.exception(type: "exceeded_max_runs", message: "m")}
      end)

      assert {:error, "A IA não chegou a uma resposta." <> _} = LLM.run(chain(0.5))
    end

    test "turns errors into messages for the user" do
      Grana.LLMStub.script([{:error, "boom"}])
      assert {:error, "A IA respondeu com erro: boom"} = LLM.run(chain(0.5))
    end

    test "timeouts and rate limits get their own message" do
      stub(ChatOpenAI, :call, fn _model, _messages, _tools ->
        {:error, LangChain.LangChainError.exception(type: "timeout", message: "t")}
      end)

      assert {:error, "A IA demorou demais" <> _} = LLM.run(chain(0.5))

      stub(ChatOpenAI, :call, fn _model, _messages, _tools ->
        {:error, LangChain.LangChainError.exception(type: "rate_limited", message: "r")}
      end)

      assert {:error, "Limite de requisições" <> _} = LLM.run(chain(0.5))
    end

    test "transport and connection errors provide clear feedback" do
      stub(ChatOpenAI, :call, fn _model, _messages, _tools ->
        {:error,
         LangChain.LangChainError.exception(
           type: "unexpected_response",
           message: "Unexpected response",
           original: {:error, %Req.TransportError{reason: :econnrefused}}
         )}
      end)

      assert {:error, "Não foi possível conectar ao servidor de IA (conexão recusada)." <> _} =
               LLM.run(chain(0.5))

      stub(ChatOpenAI, :call, fn _model, _messages, _tools ->
        {:error,
         LangChain.LangChainError.exception(
           type: "unexpected_response",
           message: "Unexpected response",
           original: {:error, %Req.TransportError{reason: :nxdomain}}
         )}
      end)

      assert {:error, "Endereço do servidor de IA não encontrado" <> _} = LLM.run(chain(0.5))
    end

    test "http status errors from the provider are mapped" do
      stub(ChatOpenAI, :call, fn _model, _messages, _tools ->
        {:error,
         LangChain.LangChainError.exception(
           message: "Unauthorized",
           type: "unexpected_response",
           original: %Req.Response{status: 401}
         )}
      end)

      assert {:error, "Chave de API inválida" <> _} = LLM.run(chain(0.5))

      stub(ChatOpenAI, :call, fn _model, _messages, _tools ->
        {:error,
         LangChain.LangChainError.exception(
           message: "Service Unavailable",
           type: "unexpected_response",
           original: %Req.Response{status: 503}
         )}
      end)

      assert {:error, "O servidor de IA retornou instabilidade temporária (HTTP 503)." <> _} =
               LLM.run(chain(0.5))
    end

    test "last_text/1 is empty without messages" do
      assert LLM.last_text(%LLMChain{}) == ""
    end
  end
end
