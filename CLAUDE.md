# Grana — instruções para agentes de IA

## Quality gate obrigatório

**Antes de declarar qualquer implementação concluída, sempre rode o quality gate local completo:**

```bash
mix format --check-formatted && \
mix compile --warnings-as-errors && \
mix credo --strict && \
MIX_ENV=test mix coveralls
```

Se qualquer etapa falhar, corrija antes de reportar como pronto.

Atalho rápido para checar apenas testes com cobertura:
```bash
MIX_ENV=test mix coveralls
```

## Regras de teste

- **Nunca modificar `lib/` para facilitar testes.** Os testes devem se adaptar ao código existente.
- Proibido: adicionar parâmetros de DI, expor `defp → def`, branches `if Mix.env() == :test`, `@doc false` para testes.
- Mocks via **Mimic** (`async: false` obrigatório). Módulos mockáveis: `Req`, `Grana.AI.Provider`, `Grana.AI.Providers.Gemini`, `Grana.Investments`, `Grana.Accounts.UserNotifier`, `Grana.PlatformImport`.
- Piso de cobertura atual: **80%** (definido em `coveralls.json`).

## Convenções de código

- Sem comentários óbvios — só quando o **porquê** é não-óbvio.
- Sem tratamento de erros para cenários impossíveis. Confie nas garantias do framework.
- Sem abstrações antecipadas. Três linhas parecidas é melhor que uma abstração prematura.
