# Grana

**Organizador financeiro pessoal** em Elixir / Phoenix LiveView. Importe extratos e faturas
(Nubank, Bradesco) e movimentações de investimentos (B3, GCB), categorize transações por
regras + IA, acompanhe dashboards, metas e análises com IA (BYOK — sua própria chave Gemini).

## Começando

Pré-requisitos: Docker (para o Postgres) e Elixir/Erlang (ver `Dockerfile`: Elixir 1.18 / OTP 28).

```bash
make setup     # sobe o Postgres (docker-compose) + deps + cria/migra o banco + assets
make server    # http://localhost:4000
```

`make help` lista todos os comandos (banco, testes, cobertura, lint, gate, etc.).

Sem o Makefile: `mix setup` e depois `mix phx.server` (requer um Postgres em `localhost:5432`,
usuário/senha `postgres`).

## Testes e quality gate

```bash
make test      # roda a suíte
make gate      # quality gate completo (igual ao CI): format, deps.audit, compile --warnings-as-errors, credo, coverage
```

O CI ([.github/workflows/fly-deploy.yml](.github/workflows/fly-deploy.yml)) roda o gate em
pushes e PRs para `main`; o deploy (Fly.io) só ocorre no merge em `main`.

## Documentação para agentes de IA

Antes de mexer no código, agentes devem ler o guia do projeto:

- **[CLAUDE.md](CLAUDE.md)** — guia para o Claude Code (o que é, arquitetura, como rodar/testar, convenções).
- **[AGENTS.md](AGENTS.md)** — mesmo guia para o Codex + regras do framework Phoenix v1.8.

## Estrutura

```
lib/grana/      contextos: Accounts, Banking, Investments, AI, Workers, Encrypted
lib/grana_web/  LiveViews, controllers, components, plugs, router
priv/examples/  arquivos reais de extrato/fatura para testes de parser
test/           testes (espelha lib/)
```
