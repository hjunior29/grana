# Grana — comandos de desenvolvimento.
# Rode `make` ou `make help` para ver os alvos disponíveis.

.DEFAULT_GOAL := help
.PHONY: help setup deps server s console iex \
        db.up db.down db.setup db.migrate db.rollback db.reset \
        test cov coverage coverage.html format format.check credo audit gate precommit \
        assets clean

# Postgres de dev (Docker) — credenciais batem com config/dev.exs e config/test.exs.
PG_CONTAINER ?= grana-pg
# CVE do Decimal ignorada de propósito (fix exige decimal 3.0, bloqueado por postgrex ~> 2.0).
AUDIT_IGNORE ?= GHSA-rhv4-8758-jx7v

help: ## Mostra esta ajuda
	@echo "Grana — comandos de dev:"
	@grep -hE '^[a-zA-Z0-9._-]+:.*?## ' $(MAKEFILE_LIST) \
		| sort \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

# ── Setup ──────────────────────────────────────────────────────────────────
setup: db.up deps ## Setup completo (Postgres + deps + banco + assets)
	mix setup

deps: ## Baixa as dependências Elixir
	mix deps.get

assets: ## Compila os assets (tailwind + esbuild)
	mix assets.build

# ── Rodar ──────────────────────────────────────────────────────────────────
server: db.up ## Sobe o servidor Phoenix (http://localhost:4000)
	mix phx.server

s: server ## Alias de `server`

console: ## Abre o console IEx com a aplicação carregada
	iex -S mix

iex: console ## Alias de `console`

# ── Banco de dados ───────────────────────────────────────────────────────────
db.up: ## Sobe o Postgres de dev (Docker)
	@docker start $(PG_CONTAINER) 2>/dev/null \
		|| docker run -d --name $(PG_CONTAINER) \
			-e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=postgres \
			-p 5432:5432 postgres:16
	@echo "Postgres ($(PG_CONTAINER)) rodando em localhost:5432"

db.down: ## Para o Postgres de dev
	@docker stop $(PG_CONTAINER)

db.setup: ## Cria o banco, roda migrations e seeds
	mix ecto.setup

db.migrate: ## Roda as migrations pendentes
	mix ecto.migrate

db.rollback: ## Reverte a última migration
	mix ecto.rollback

db.reset: ## Recria o banco do zero (drop + create + migrate + seed)
	mix ecto.reset

# ── Qualidade (espelha o quality gate do CI) ─────────────────────────────────
test: ## Roda a suíte de testes
	mix test

cov: coverage ## Alias de `coverage`

coverage: ## Roda os testes com cobertura e aplica o piso (coveralls.json)
	MIX_ENV=test mix coveralls

coverage.html: ## Gera o relatório HTML de cobertura (cover/excoveralls.html)
	MIX_ENV=test mix coveralls.html

format: ## Formata o código
	mix format

format.check: ## Verifica formatação (não altera arquivos)
	mix format --check-formatted

credo: ## Análise estática (Credo, --strict)
	mix credo --strict

audit: ## Auditoria de vulnerabilidades nas dependências
	mix deps.audit --ignore-advisory-ids $(AUDIT_IGNORE)

gate: ## Roda o quality gate completo (igual ao CI, antes do deploy)
	mix format --check-formatted
	mix deps.unlock --check-unused
	mix deps.audit --ignore-advisory-ids $(AUDIT_IGNORE)
	mix compile --warnings-as-errors
	mix credo --strict
	MIX_ENV=test mix coveralls

precommit: ## Roda o alias precommit do projeto
	mix precommit

# ── Utilitários ──────────────────────────────────────────────────────────────
clean: ## Limpa artefatos de build
	mix clean
