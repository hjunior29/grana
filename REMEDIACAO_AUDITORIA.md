# Remediação da Auditoria Profunda — Grana

> Branch: `fix/deep-audit-remediation` · base: `main@c197829`
> Relatório original: `tmp/auditoria-grana.html` (127 achados)

Correções da auditoria de 29/05/2026, aplicadas do mais crítico ao menos crítico.
Cada etapa foi compilada com `--warnings-as-errors` e validada com a suíte de testes.
Estado final: **221 testes, 0 falhas**, `mix format --check-formatted` ok, `mix deps.audit` sem vulnerabilidades (exceto Decimal, ver abaixo).

> **Atualização 30/05 — rodada P1+P2:** dos 61 deferidos, priorizados e resolvidos:
> P1 (correção de dados/segurança) #50, #44, #80, #81, #110, #114; P2 #76/#77 (.env só dev/test),
> #111 (CSP nas rotas do app), #103 (parsing seguro de ids em todas as LiveViews), #45
> (parcelas), #49 (alinhamento da categorização IA), #36 (matching de transferências O(n)),
> #22 (lucro realizado por preço médio, com teste). Score estimado **3.5 → 8.5**; 67 corrigidos / 12 parciais / 48 deferidos.
> **Ação manual pendente (#73):** rotacionar os segredos do `.env` que já estiveram expostos.
> **Ainda deferidos (exigem trabalho dedicado):** #13/#37 (agregação SQL do `build_summary` —
> precisa de teste golden-master antes de migrar a classificação por heurística de texto p/ SQL,
> senão arrisca a matemática); #61 (`File.read!` de até 60MB — fix correto exige object storage/S3,
> e o design atual base64-via-DB é proposital para multi-máquina no Fly).

## Como o trabalho está organizado (commits)

1. `chore: snapshot WIP` — preserva o trabalho de UI/localização que estava sem commit.
2. `fix(security): recupera hardening do stash@{0}` — recupera a parte de backend/segurança/testes do stash (sem a UI conflitante).
3. `fix(security): IDOR get_ai_analysis e XSS` — críticos restantes.
4. `fix(high): TLS, cron, parsers, unique jobs`.
5. `fix(high): base de custo, dashboard, metas`.
6. `ci+test: gate de deploy + cobertura`.
7. `fix(medium): mass-assignment, timeouts, parsing, CVEs de deps`.
8. `fix(low): .env no build, token brapi, magic link, índices`.

## Corrigido

### Críticos
- **IDOR exclusão de extratos** — `Banking/Investments.delete_statements/2` exigem `user_id`; `upload_live` usa `get_statement!/2`.
- **IDOR análises de IA** — `Banking.get_ai_analysis!/2` filtra por usuário; `analysis_live` trata id alheio sem crashar.
- **XSS nos gráficos** — `escapeHtml` em nome/cor de categoria e labels antes de `innerHTML`/SVG (todos os hooks de chart) + validação de cor hex no changeset.

### Altos
- Cifragem AES‑256‑GCM das chaves de IA (`Grana.Encrypted.Binary`) + migration que limpa texto plano.
- Rate limiting (Hammer) em login/magic‑link/registro.
- Sanitização anti prompt‑injection (`Grana.AI.PromptSanitizer`).
- Import de extratos transacional (rollback) + unique constraints anti‑duplicata.
- TLS: SMTP (prod+dev) e Postgres validam certificado (`verify_peer` + cacerts); SSL do banco via `DB_SSL`.
- QuoteFetcher agendado no cron do Oban; cotações só batem na rede com socket conectado.
- Parsers resilientes (`Integer.parse`/`Decimal.parse`): linha ruim é descartada, não derruba o lote.
- Workers de upload com `try/rescue` por arquivo; `AIAnalysisWorker` com unique jobs + discard de erro permanente.
- Investimentos: base de custo da posição por preço médio (corrige gain/loss em vendas parciais).
- Dashboard: `build_summary` não retém a lista completa de transações em assigns (só top 15).
- Metas: `category_id` validado como do próprio usuário.
- CI: job `test` (Postgres, format/compile/test/audit) **antes** do deploy.
- Testes de escopo/IDOR, propriedade de categoria e bordas de `build_summary`.

### Médios
- `is_system` não‑castável (anti escalonamento) + cor hex validada.
- Timeout padrão (30s) no Gemini; fallback/nil‑check no worker de IA.
- Troca de senha trata sudo expirado / changeset inválido sem 500.
- `safe_to_int` em params/phx-value na `analysis_live`.
- `to_decimal` do PDF normaliza formato pt‑BR (não trunca centavos).
- Health check HTTP no `fly.toml`; índice em `category_rules.category_id`.
- `mix_audit` + Dependabot; bump de **plug 1.19.2, postgrex 0.22.2, phoenix 1.8.7, bandit 1.11.1** (CVEs).

### Baixos
- `.dockerignore` exclui `.env`; token brapi no header `Authorization` (fora de logs).
- Texto do magic link corrigido para 15 min; índices `bank_statements(user_id, statement_type)` e `financial_goals(category_id)`.

## Pendente (deferido com motivo)

Itens grandes/arquiteturais ou com risco de regressão em cálculo financeiro — recomendo PRs dedicados com validação:

| # | Item | Motivo do adiamento |
|---|------|---------------------|
| 13/37 | Agregações de `build_summary` em SQL | Classificação (transferência interna, pagamento de fatura por heurística de texto, estorno) é difícil de reproduzir fielmente em SQL; risco na matemática. Já mitigado: lista completa não fica mais em assigns (#12). |
| 22 | Lucro realizado por venda (custo médio cronológico) | Mudança algorítmica grande; precisa validação de domínio. Já corrigido o custo da posição em aberto (#21). |
| 36/58/59/61/63 | Perf: O(n²) em transferências, trabalho duplicado mount/render, `:for`→stream, `File.read!` 60MB síncrono, paginação em memória | Refactors médios/grandes de LiveView/upload; exigem teste em navegador. |
| 62 | Validação de upload por magic bytes | Mitigado por parsers resilientes + `try/rescue`; checagem de conteúdo fica para PR próprio. |
| 66/116/118 | Unique constraint de transações; precision/scale dos decimais | Migrations que alteram dados/colunas existentes; exigem janela e backfill cuidadosos. |
| 103 (amplo) | `String.to_integer` em outras LiveViews (categories, goals, dashboard, transactions) | `analysis_live` corrigida; demais são long‑tail de robustez (mesmo padrão `safe_to_int`). |
| 111 | Content‑Security‑Policy | Alto risco de quebrar estilos inline/charts/LiveView sem teste em navegador. |
| 23/55/68/69/70/101 | Mais cobertura de testes (investments, workers, IA, parsers malformados, interação de LiveView) | Stash já adicionou parte; o restante é esforço grande. |
| decimal 3.0 | CVE moderada (DoS por expoente) | Único fix é decimal 3.0, mas `postgrex` fixa `decimal ~> 2.0`. Reavaliar quando postgrex permitir 3.0. Ignorado de forma documentada no CI. |

### Stashes restantes
- `stash@{0}` (WIP) foi consumido (backend/segurança/testes recuperados; a UI dele foi deixada de lado em favor da sua UI atual). Pode descartar após revisar.
- `stash@{1}` (feature‑flags) e `stash@{2}` (ai_analyser) usam namespace antigo `Granai` e **não compilam** contra a main — precisam de port manual se ainda forem desejados.
