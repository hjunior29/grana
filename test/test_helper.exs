ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Grana.Repo, :manual)

# Módulos que podem ser mockados com mimic em testes.
# Mimic.copy deve ser chamado antes de qualquer test start.
Mimic.copy(Req)
Mimic.copy(Grana.AI.Provider)
Mimic.copy(Grana.AI.Providers.Gemini)
Mimic.copy(Grana.Accounts.UserNotifier)
Mimic.copy(Grana.PlatformImport)
Mimic.copy(Grana.OpenFinance.Pluggy)
Mimic.copy(Grana.Mailer)
