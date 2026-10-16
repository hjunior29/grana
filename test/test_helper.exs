ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Grana.Repo, :manual)

# Módulos que podem ser mockados com mimic em testes.
# Mimic.copy deve ser chamado antes de qualquer test start.
Mimic.copy(Req)
Mimic.copy(Grana.Accounts.UserNotifier)
Mimic.copy(Grana.PlatformImport)
Mimic.copy(Grana.OpenFinance.Pluggy)
Mimic.copy(Grana.Mailer)
Mimic.copy(Grana.AI.Models)
Mimic.copy(LangChain.ChatModels.ChatGoogleAI)
Mimic.copy(LangChain.ChatModels.ChatOpenAI)
Mimic.copy(LangChain.ChatModels.ChatAnthropic)
Mimic.copy(LangChain.ChatModels.ChatOpenAICompatible)
