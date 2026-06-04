# Plano para 90% de cobertura de testes

> Planejamento para levar a cobertura do app **inteiro** de **44,4% → 90%**.
> Este documento é só o **plano** — nenhum teste é implementado aqui.

## Regra de ouro (inegociável)

**O teste se adapta ao código — nunca o código ao teste.**

O código de produção (`lib/`) **não** deve ser alterado para "ficar testável".
Em particular, é **proibido** ao escrever os testes:

- adicionar parâmetros/opções só para injetar dependência em teste;
- quebrar função em pedacinhos só para testar o pedaço;
- expor função privada (`defp → def`) ou criar `@doc false` "de teste";
- adicionar `if Mix.env() == :test` / branches que só existem por causa de teste;
- afrouxar visibilidade, mover lógica para facilitar o setup, etc.

Se um módulo "resiste" ao teste, a resposta é **mudar a técnica de teste**, não o
código (ver "Estratégias" abaixo). O que **é** permitido (não é mexer no código):

- adicionar **dependências de teste** (`only: :test`) — ex.: lib de mock;
- adicionar **fixtures** em `test/support/fixtures/`;
- adicionar **helpers de teste** em `test/support/`;
- ajustar **CI/infra** (serviços, binários, env) e `config/test.exs`/`coveralls.json`.

---

## Estado atual (medido com `mix coveralls`)

| Métrica | Valor |
|---|---|
| Linhas relevantes | **5.758** |
| Cobertas | 2.559 |
| Não cobertas | **3.199** |
| Cobertura | **44,4%** |
| **Para 90%** | cobrir **~2.623** linhas a mais (≈82% do que falta hoje) |

A lacuna está **concentrada**: ~70% das linhas faltantes estão em 6 LiveViews +
2 contexts. Atacando os módulos abaixo na ordem, chega-se a 90% sem precisar
cobrir os 121 arquivos uniformemente.

### Onde está a dívida (por linhas não cobertas)

| Módulo | Cobertura | Linhas faltando | Tipo |
|---|--:|--:|---|
| `grana_web/live/dashboard_live.ex` | 18,3% | **646** | LiveView |
| `grana_web/live/upload_live.ex` | 23,7% | **344** | LiveView |
| `grana_web/live/analysis_live.ex` | 13,0% | **300** | LiveView |
| `grana/banking/ai_analyzer.ex` | 0,6% | **291** | IA/externo |
| `grana_web/live/transactions_live.ex` | 43,2% | **285** | LiveView |
| `grana/banking.ex` | 67,4% | **192** | context |
| `grana/investments.ex` | 53,4% | **161** | context |
| `grana_web/live/goals_live.ex` | 0,0% | **146** | LiveView |
| `grana_web/live/categories_live.ex` | 0,0% | **105** | LiveView |
| `grana/banking/parsers/pdf_extractor.ex` | 0,0% | 69 | IA/PDF |
| `grana/investments/quote_provider.ex` | 0,0% | 50 | HTTP (brapi) |
| `grana/investments/parsers/pdf_extractor.ex` | 0,0% | 49 | IA/PDF |
| `grana/banking/statement_processor.ex` | 56,3% | 45 | pipeline |
| `grana/investments/parsers/generic_csv.ex` | 72,2% | 43 | parser |
| `grana/cache.ex` | 16,3% | 41 | infra (Redis) |
| `grana_web/controllers/transactions_export_controller.ex` | 0,0% | 37 | controller |
| `grana/investments/parsers/b3_xlsx.ex` | 78,8% | 29 | parser |
| `grana/workers/inactivity_reminder_worker.ex` | 0,0% | 28 | worker |
| `grana/investments/statement_processor.ex` | 64,8% | 26 | pipeline |
| `grana/investments/parsers/gcb_csv.ex` | 72,7% | 24 | parser |
| `grana/ai/providers/gemini.ex` | 0,0% | 24 | HTTP (IA) |
| `grana/banking/ai_categorizer.ex` | 0,0% | 23 | IA/externo |
| `grana/banking/csv_exporter.ex` | 0,0% | 18 | puro |
| `grana/investments/csv_exporter.ex` | 0,0% | 23 | puro |
| `grana/workers/ai_analysis_worker.ex` | 0,0% | 23 | worker |
| demais (schemas, plugs, release, controllers, etc.) | — | ~250 | vários |

---

## Estratégias por tipo de módulo (sem tocar no código)

| Tipo | Técnica | Por que não exige mexer no código |
|---|---|---|
| **Contexts** (`banking.ex`, `investments.ex`) | `Grana.DataCase` + fixtures; exercitar cada `def` público com vários filtros, e os ramos de erro (changeset inválido, IDOR, posse cross-user). | Já são API pública; só faltam casos. |
| **LiveViews** | `Phoenix.LiveViewTest`: `live/2`, `render_*`, `element/3`, `has_element?/2`, `render_hook`, navegação. Cobrir `mount` por papel/cenário, cada `handle_event`/`handle_info`, estados vazios e de erro. | Dirige a tela como usuário; nenhuma função interna é tocada. |
| **Parsers** (CSV/XLSX) | Fixtures reais em `test/support/fixtures/`; um caso por layout/banco + arquivos malformados/edge (encoding, linhas quebradas, cabeçalho ausente). | Funções puras `parse/1`; só faltam fixtures. |
| **Integrações HTTP** (`quote_provider` brapi, `ai/providers/gemini`) | Lib de mock por **substituição de módulo em runtime** (recomendo **`mimic`**): no teste, `stub`/`expect` em `Req`/no provider. **Não** usar Mox aqui — Mox exige behaviour + injeção de dependência (= mexer no código). | `mimic` intercepta o módulo concreto sem alterar `lib/`. |
| **IA** (`ai_analyzer`, `ai_categorizer`) | Mockar o provider/`Req` com `mimic`; fixtures de resposta JSON; cobrir parse OK, contagem divergente, erro de rede, anti-prompt-injection. | Idem acima. |
| **PDF** (`pdf_extractor`, `pdf_text`) | Fixtures PDF (já há `test/support/fixtures/pdf/`) para o caminho determinístico (pdftotext); mockar a IA para o fallback. Exige `poppler-utils` no CI. | Fixtures + mock no boundary. |
| **Workers (Oban)** | Chamar `perform/1` direto com `%Oban.Job{args: ...}` (ou `Oban.Testing`); mockar e-mail (`Swoosh.Adapters.Test`, já configurado) e IA. | Worker é chamado pela API pública `perform/1`. |
| **Controllers** (`transactions_export`) | `Phoenix.ConnTest`: `get/post` autenticado, assert headers/corpo do CSV. | Dirige via `conn`. |
| **`cache.ex`** | Tag `:redis`; habilitar o cache só nesses testes (override de `config`) contra o Redis do CI; cobrir get/miss/hit, invalidação, e o caminho de degradação (Redis fora → fallback). | Exercita a API pública `get_or_store/4`, `invalidate_user/1`. |
| **`release.ex`** | Chamar as funções de migração/rollback contra o DB de teste. | API pública. |

---

## Roadmap em fases

Cada fase tem uma meta de cobertura e sobe o **piso do CI** (`minimum_coverage`
em `coveralls.json`) junto — assim o número nunca regride. As fases estão na
ordem de **melhor retorno/esforço**.

### Fase 0 — Preparo de tooling (sem testes ainda)
- Adicionar dep de teste de mock: `{:mimic, "~> 1.7", only: :test}` (ou `:meck`).
- CI: adicionar `poppler-utils` (job de teste) para os parsers de PDF, e um
  serviço `redis` no job de teste para os testes de `cache.ex`.
- Decidir o **enforcement por módulo**: além do piso global, considerar falhar
  o build se um módulo crítico cair abaixo de uma meta (script sobre o
  `cover/excoveralls.json`), evitando "cobrir tela fácil e ignorar o context".

### Fase 1 — Backend determinístico → meta **~58%** (piso CI 55%)
Maior ROI, **sem mocks**. Alvos:
- `banking.ex` (−192) e `investments.ex` (−161): completar filtros e ramos de erro.
- `statement_processor.ex` banking (−45) e investimentos (−26): dedupe, período, rollback de duplicado, reconciliação.
- Parsers `generic_csv` (−43), `b3_xlsx` (−29), `gcb_csv` (−24): layouts + malformados.
- `csv_exporter` banking (−18) e investimentos (−23): puros, triviais.
- Schemas <100% (`financial_goal`, `institution`, `transaction`, `constants`, `recurring_rule`): changesets válidos/ inválidos.
- **~580 linhas**.

### Fase 2 — LiveViews → meta **~85%** (piso CI 80%)
O maior bloco (≈1.850 linhas), **sem mocks**, via `Phoenix.LiveViewTest`:
- `dashboard_live` (−646), `upload_live` (−344), `analysis_live` (−300),
  `transactions_live` (−285), `goals_live` (−146), `categories_live` (−105),
  + sobras de `settings`/`calendar`.
- Para cada uma: `mount` (com/sem dados, por filtro), cada `handle_event`
  (criar/editar/excluir/filtrar/ordenar/paginar), `handle_info` (PubSub de
  upload), estados vazios, e erros (params inválidos, posse de outro usuário).
- Uploads: usar `file_input`/`render_upload` do LiveViewTest com fixtures.

### Fase 3 — Integrações externas (IA, brapi, PDF) → meta **~92%** (piso CI 90%)
Com **mocks/fixtures** (Fase 0):
- `ai_analyzer` (−291) e `ai_categorizer` (−23): mock do provider; parse OK,
  contagem divergente, erro, sanitização de prompt.
- `quote_provider` (−50) e `gemini` (−24): mock de `Req`; OK, 4xx/5xx, timeout,
  payload inesperado; cache ETS de cotações.
- `pdf_extractor` banking (−69) e investimentos (−49): fixtures PDF + mock da IA.
- **Aqui cruzamos os 90%.**

### Fase 4 — Workers, controllers, plugs, cache, release → meta **>93%** (piso CI 92%)
Fechamento:
- Workers: `ai_analysis` (−23), `inactivity_reminder` (−28), `quote_fetcher` (−6),
  + sobras dos upload workers — via `perform/1` + mocks.
- `transactions_export_controller` (−37) e `page_controller` (−1): ConnTest.
- `cache.ex` (−41): tag `:redis` contra o Redis do CI + caminho de degradação.
- `rate_limit` plug (−13), `router` (−8), `release.ex` (−8).

---

## Enforcement e medição

- **Piso incremental** em `coveralls.json` (`minimum_coverage`): 36 → 55 → 80 →
  90 → 92, subindo a cada fase fechada. Nunca baixar.
- Rodar localmente: `make coverage` (piso) e `make coverage.html` (relatório por linha).
- Manter `skip_files` enxuto. Hoje pula `test/`, `priv/`, `layouts.ex`,
  `core_components.ex`. Para 90% **real**, não adicionar módulos de produção ao
  skip só para "passar o número" — a única exceção defensável é arquivo 100%
  declarativo sem lógica.
- O job `🧪 test` do CI já aplica o piso; ao chegar na Fase 3, adicionar o
  serviço `redis` e `poppler-utils` ao job.

## Riscos / armadilhas

- **Tentação de mexer no código.** O maior risco. Se bater a vontade de
  refatorar para testar: pare e troque a técnica (mock no boundary, fixture,
  dirigir pela tela). Documente no PR por que o código ficou intacto.
- **Mox × mimic.** Mox força behaviour + injeção (mexeria no código). Por isso a
  recomendação é `mimic`/`meck` (mock do módulo concreto) para HTTP/IA.
- **Flakiness de tempo/rede.** Sempre mockar rede; nunca chamar brapi/IA reais
  no CI. Datas relativas (ex.: janela do `recurring_analysis`): fixar `today`
  via opts nas asserts.
- **LiveViews longas.** São volume, não dificuldade — dá para paralelizar por
  tela entre PRs. É onde mora a maior parte das 2.623 linhas.

## Resumo do esforço

| Fase | Foco | ~linhas cobertas | Cobertura acumulada | Mocks? |
|---|---|--:|--:|:--:|
| 1 | Contexts, parsers, exporters, schemas | ~580 | ~58% | não |
| 2 | LiveViews | ~1.850 | ~85% | não |
| 3 | IA, brapi, PDF | ~510 | **~92%** | sim |
| 4 | Workers, controllers, cache, release | ~165 | >93% | parcial |

A meta de **90% sai ao fim da Fase 3**. A Fase 2 (LiveViews) é o grosso do
trabalho e não precisa de nenhum mock — só de paciência e `Phoenix.LiveViewTest`.
