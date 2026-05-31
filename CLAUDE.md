# Grana — Guia do projeto (para agentes)

> Documento de contexto para agentes de IA (Claude Code). Leia isto **antes** de
> vasculhar o código — ele resume o que o projeto é, como rodar e como validar
> mudanças. O equivalente para o Codex vive em [`AGENTS.md`](AGENTS.md) (que também
> contém as regras detalhadas do framework Phoenix v1.8).

## O que é

**Grana** é um **organizador financeiro pessoal** em **Elixir / Phoenix LiveView**.
O usuário importa extratos/faturas bancárias e movimentações de investimentos; o app
extrai e categoriza as transações (regras + IA), mostra dashboards/gráficos, acompanha
metas e gera análises com IA (modelo **BYOK** — o usuário usa a própria chave Gemini).

Principais funcionalidades:
- **Importação**: extratos e faturas **Nubank** e **Bradesco** (CSV/PDF) e investimentos
  **B3** (XLSX), **GCB** (CSV) e CSV genérico/PDF.
- **Categorização**: por regras do usuário + IA (Gemini), com deduplicação.
- **Dashboard**: receitas/despesas/investimentos, gráficos por categoria, evolução mensal,
  projeção de parcelas e carteira de investimentos (com cotações via brapi.dev).
- **Metas** financeiras, **análises com IA**, exportação CSV.
- **Auth** própria (phx.gen.auth com scopes), magic link + senha, rate limiting.

## Stack

| Camada | Tecnologia |
|---|---|
| Linguagem/Framework | Elixir ~> 1.18, Phoenix 1.8 (LiveView 1.1) |
| Banco | PostgreSQL via Ecto |
| Front | LiveView + Tailwind v4 + daisyUI (tema padrão Phoenix/Elixir) |
| Jobs | Oban (filas: uploads, ai_analysis, quotes, notifications) |
| HTTP | **Req** (não usar HTTPoison/Tesla/httpc) |
| E-mail | Swoosh + gen_smtp |
| Server | Bandit |
| IA | Google Gemini (`Grana.AI.Provider`) — BYOK |
| Cifragem | AES-256-GCM (`Grana.Encrypted.Binary`) para chaves de IA at-rest |
| Rate limit | Hammer |
| Erros | ErrorTracker (admin) |
| Deploy | Fly.io |

## Arquitetura

Contextos (regra de negócio em `lib/grana/`):
- **`Grana.Accounts`** — usuários, tokens, scopes, notificações de e-mail.
- **`Grana.Banking`** — extratos (`BankStatement`), transações, categorias, regras de
  categoria, metas (`FinancialGoal`), análises de IA (`AIAnalysis`), e os resumos do
  dashboard (`build_summary`/`monthly_summary`/etc.).
- **`Grana.Investments`** — extratos, transações, instituições, cotações
  (`QuoteProvider`), `portfolio_summary`/`portfolio_with_market_data`.
- **`Grana.AI`** — `Provider` + `providers/gemini`, `PromptSanitizer` (anti prompt-injection).
- **`Grana.Workers`** — Oban: `statement_upload`, `investment_upload`, `ai_analysis`,
  `quote_fetcher` (cron 30min), `inactivity_reminder` (cron).
- **`Grana.Encrypted.Binary`** — tipo Ecto que cifra/decifra a coluna `users.ai_api_key`.

Web (`lib/grana_web/`):
- **LiveViews** (`live/`): `dashboard`, `transactions`, `upload`, `analysis`, `goals`,
  `categories`, `landing`, `terms`, `user_live/{login,registration,confirmation,settings}`.
- **Controllers**: `user_session` (login/logout/senha), `transactions_export`.
- **Components**: `core_components` (padrão phx.new — `<.input>`, `<.button>`, `<.icon>`,
  `<.table>`, `<.flash>`…), `layouts` (navbar + `<Layouts.app>`).
- **Plugs**: `GranaWeb.RateLimit` (login/magic-link/registro), `GranaWeb.Params` (parsing seguro de ids).
- **Router**: pipeline `:browser` + `:csp` (CSP só nas rotas do app, não nos dashboards admin/dev).

Parsers:
- Bancários: `lib/grana/banking/parsers/{nubank,nubank_fatura,bradesco,bradesco_fatura,installment_parser,pdf_extractor}.ex`
- Investimentos: `lib/grana/investments/parsers/{b3_xlsx,gcb_csv,generic_csv,pdf_extractor}.ex`
- Arquivos de exemplo reais para teste: **`priv/examples/`** (extrato/fatura nubank, bradesco, b3.xlsx, gcb.csv).

## Como rodar

Pré-requisito: Docker (para o Postgres) e Elixir/Erlang (ver versões no `Dockerfile`:
Elixir 1.18.4 / OTP 28). Use o **Makefile** (`make help` lista tudo):

```bash
make setup     # sobe Postgres (docker-compose), deps, cria/migra o banco e builda assets
make server    # sobe o Postgres + Phoenix em http://localhost:4000  (Ctrl+C encerra)
```

O Postgres de dev roda em container via `docker-compose.yml` (`grana-db`, postgres/postgres
@ 5432, volume persistente). `make db.up` / `make db.down` / `make db.reset` gerenciam o banco.

Sem o Makefile: `mix setup` então `mix phx.server` (precisa de um Postgres em `localhost:5432`
com usuário/senha `postgres`).

### Variáveis de ambiente
- **Dev/test**: nenhuma obrigatória (há defaults; `CLOAK_KEY` tem default fixo em `config/dev.exs`/`config/test.exs`). Opcional: `.env` na raiz é carregado **só em dev/test**.
- **Produção** (obrigatórias, com `raise` se faltarem): `DATABASE_URL`, `SECRET_KEY_BASE`, `CLOAK_KEY` (chave de cifragem das chaves de IA), `SMTP_HOST`.
- Opcionais: `BRAPI_TOKEN` (cotações), `ADMIN_EMAIL` (libera `/admin/*`), `ROADMAP_URL`, `DB_SSL=true`, `PHX_HOST`, `POOL_SIZE`, `ECTO_IPV6`.
- A **chave Gemini é por usuário** (BYOK), definida em *Configurações* na UI e cifrada no banco — não é env var.

## Como testar e validar implementações

A suíte precisa do Postgres de pé (`make db.up`). O alias `mix test` cria/migra o banco de
teste automaticamente.

```bash
make test        # mix test (245+ testes)
make coverage    # testes + cobertura (ExCoveralls), com piso mínimo (coveralls.json)
make gate        # QUALITY GATE completo — rode isto antes de abrir PR
```

**`make gate`** é o que o CI exige e espelha exatamente o pipeline:
1. `mix format --check-formatted`
2. `mix deps.unlock --check-unused`
3. `mix deps.audit` (ignora 1 CVE do `decimal`, bloqueado pelo `postgrex ~> 2.0`)
4. `mix compile --warnings-as-errors`
5. `mix credo --strict` (config em `.credo.exs`; débito estrutural legado está em baseline)
6. `mix coveralls` (piso de cobertura em `coveralls.json`)

### Padrões de teste (siga ao adicionar features)
- Use `Grana.DataCase` (testes de contexto) e `Grana.AccountsFixtures` (`user_fixture/0`, `user_scope_fixture/0`).
- **Sempre** adicione teste de **isolamento por usuário (IDOR)** para qualquer query nova: criar 2 usuários e garantir que um não acessa dados do outro.
- Parsers: teste com os arquivos reais de `priv/examples/` + casos malformados (não devem derrubar o lote).
- Cálculos financeiros: asserte com `Decimal.equal?/2` (nunca compare float).
- Testes ficam em `test/` espelhando `lib/` (ex.: `test/grana/banking_test.exs`).

## Convenções e invariantes (IMPORTANTE)

Estas regras são críticas — quebrar uma é um bug de segurança ou de dados:

1. **Dinheiro é `Decimal`**, nunca float. Use `Decimal.add/sub/mult/div` e `Decimal.equal?`.
2. **Toda query Ecto é escopada por `user_id`** (multi-tenant). Funções `get_*!/2` recebem
   `user_id` e filtram por ele. Nunca busque por id puro vindo do cliente sem o dono.
   Valide `category_id`/ids cross-tenant antes de gravar (ver `Banking.category_belongs_to_user?/2`).
3. **Chaves de IA são cifradas at-rest** (`Grana.Encrypted.Binary`). `CLOAK_KEY` é obrigatória em produção.
4. **IDs vindos do cliente** (URL/`phx-value`) passam por `GranaWeb.Params.to_int/2` ou `parse_int/2` (nunca `String.to_integer` cru).
5. **HTTP**: use `Req`. **UI**: textos em **PT-BR**. **Phoenix 1.8**: toda LiveView começa com `<Layouts.app flash={@flash} current_scope={@current_scope}>`; use os componentes de `core_components` (`<.input>`, `<.button>`, `<.icon name="hero-...">`).
6. **Importação de extrato é transacional** (rollback em falha) e tem **unique constraint** anti-duplicata; parsers descartam linha malformada em vez de derrubar o lote; workers de upload têm `try/rescue` por arquivo.
7. Rode **`make gate`** antes de qualquer PR. Não baixe o piso de cobertura nem desabilite checks do Credo para "passar" — corrija o código.

## CI / Deploy

`.github/workflows/fly-deploy.yml`:
- **Job `test` (o gate)** roda em **push para `main` E em PRs para `main`**.
- **Job `deploy`** (Fly.io) roda **só no push/merge em `main`** (`if: github.event_name != 'pull_request'`).
- Dependabot configurado em `.github/dependabot.yml`.

## Mapa rápido de diretórios

```
lib/grana/            contextos (Accounts, Banking, Investments, AI, Workers, Encrypted)
lib/grana_web/        LiveViews, controllers, components, plugs, router, endpoint
priv/repo/migrations/ migrations Ecto
priv/examples/        arquivos reais de extrato/fatura p/ testes de parser
test/                 testes (espelha lib/)
config/               config.exs, dev.exs, test.exs, prod.exs, runtime.exs
assets/               app.js (hooks de gráfico, tema) e app.css (Tailwind v4 + daisyUI)
Makefile              comandos de dev (make help)
docker-compose.yml    Postgres de desenvolvimento
.credo.exs            config do Credo (quality gate)
coveralls.json        piso de cobertura
REMEDIACAO_AUDITORIA.md  histórico da auditoria de segurança e remediação
```

## Armadilhas conhecidas

- **`decimal`** está fixado em 2.x (CVE de DoS conhecido) porque `postgrex ~> 2.0` bloqueia o 3.0; o CVE é ignorado de propósito no `mix deps.audit` (ver flag no Makefile/CI).
- Cotações (brapi.dev) só são buscadas na rede quando o socket está conectado; em cache frio podem demorar — há fallback de cache.
- O `QuoteFetcher` roda via cron do Oban (a cada 30min) para manter o cache quente.
