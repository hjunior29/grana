# Grana - Auditoria de Produção

> Relatório gerado em 27/02/2026
> Análise minuciosa do projeto para lançamento em produção

---

## Resumo Executivo

O **Grana** é uma aplicação de gestão financeira pessoal construída com Elixir/Phoenix LiveView. Permite importar extratos bancários (Nubank, Bradesco), rastrear investimentos (B3, GCB), categorizar transações com IA (Gemini) e analisar gastos. O projeto tem boa base arquitetural mas apresenta **problemas críticos que impedem o lançamento seguro em produção**.

### Score de Prontidão: 5/10

| Área | Status | Nota |
|------|--------|------|
| Segurança | Crítico | Secrets expostos, TLS desabilitado, XSS |
| Banco de Dados | Alto | N+1 queries, índices faltando, sem transações |
| Resiliência | Alto | Sem retries, sem circuit breaker, crashes com `!` |
| Frontend/UX | Médio | Acessibilidade fraca, memory leaks em assigns |
| Observabilidade | Alto | Sem logging, sem health check, métricas mínimas |
| Testes | Médio | Cobertura incompleta em paths críticos |
| Deploy | Médio | Cold starts, pool sizing inadequado |

---

## 1. SEGURANÇA — Problemas Críticos

### 1.1 [BLOQUEANTE] Arquivo `.env` com secrets no repositório

**Severidade:** CRÍTICA

O arquivo `.env` contém credenciais ativas em texto plano:
- `GEMINI_API_KEY` — chave de API do Google Gemini
- `SMTP_PASSWORD` — senha do servidor de email
- `BRAPI_TOKEN` — token da API de cotações
- `ADMIN_EMAIL` — email do administrador

**Impacto:** Qualquer pessoa com acesso ao repo (incluindo histórico git) pode usar as APIs, enviar emails e identificar o admin.

**Correção:**
1. Revogar imediatamente todas as chaves e senhas expostas
2. Remover `.env` do histórico git com `git filter-repo`
3. Adicionar `.env` ao `.gitignore`
4. Regenerar todas as credenciais
5. Usar secrets manager (Fly.io secrets, Vault, etc.)

---

### 1.2 [BLOQUEANTE] TLS desabilitado no SMTP

**Arquivo:** `config/runtime.exs:60,159`

```elixir
tls_options: [verify: :verify_none]
```

**Impacto:** Vulnerável a ataques Man-in-the-Middle. Emails com tokens de reset de senha podem ser interceptados.

**Correção:**
```elixir
tls_options: [verify: :verify_peer, cacerts: :public_key.cacerts_get()]
```

---

### 1.3 [BLOQUEANTE] XSS via innerHTML em tooltips de gráficos

**Arquivo:** `assets/js/app.js:10-35`

```javascript
tip.innerHTML = html  // Dados do usuário injetados sem sanitização
```

Nomes de categorias criadas pelo usuário são injetados diretamente no DOM via `innerHTML`. Um nome de categoria malicioso como `<script>...</script>` seria executado.

**Correção:** Usar `textContent` ou sanitizar o HTML antes da injeção.

---

### 1.4 [ALTO] API keys do usuário armazenadas sem criptografia

**Arquivo:** `lib/grana/accounts/user.ex:14`

```elixir
field :ai_api_key, :string, redact: true
```

O `:redact` apenas esconde em logs — o valor é armazenado em texto plano no banco. Além disso, a chave completa é exibida no formulário de settings.

**Correção:**
- Criptografar API keys com `Cloak.Ecto` ou similar
- Exibir apenas versão mascarada no formulário (`AIza...****`)

---

### 1.5 [ALTO] Sem rate limiting

Nenhum rate limiting encontrado para:
- Tentativas de login (brute force)
- Geração de magic links (email bombing)
- Upload de arquivos
- Chamadas à API de IA

**Correção:** Implementar com `hammer` ou `hammer_plug`.

---

### 1.6 [ALTO] Headers de segurança ausentes

Não há Content-Security-Policy, X-Content-Type-Options, X-Frame-Options ou X-XSS-Protection configurados.

**Correção:** Adicionar plug de headers de segurança no endpoint.

---

### 1.7 [MÉDIO] Admin identificado por email hardcoded

**Arquivo:** `lib/grana_web/user_auth.ex:287-298`

O acesso admin é controlado comparando o email do usuário com uma variável de ambiente. Se o email for comprometido, o atacante vira admin.

**Correção:** Usar campo `is_admin` boolean na tabela users com gestão adequada de roles.

---

### 1.8 [MÉDIO] Cookie SameSite como "Lax" ao invés de "Strict"

**Arquivo:** `lib/grana_web/endpoint.ex:12`

**Correção:** Alterar para `same_site: "Strict"`.

---

## 2. BANCO DE DADOS — Problemas de Performance e Integridade

### 2.1 [CRÍTICO] N+1 queries na detecção de transferências

**Arquivo:** `lib/grana/banking.ex:391-416`

`mark_inter_account_transfers/1` carrega TODAS as transações do usuário na memória e faz preload de bank_statement para cada uma. Com 100k transações, consome toda a memória.

**Correção:** Mover a lógica de filtragem para o banco com subqueries ou joins.

---

### 2.2 [CRÍTICO] N+1 queries na categorização

**Arquivo:** `lib/grana/banking.ex:462-475`

`categorize_transaction/2` é chamado por transação e cada chamada faz uma query para carregar TODAS as regras de categoria. Em um extrato de 500 transações = 500 queries.

**Correção:** Carregar regras uma vez e passar como parâmetro, ou usar cache em memória.

---

### 2.3 [ALTO] Processamento de extratos sem transação de banco

**Arquivo:** `lib/grana/banking/statement_processor.ex:26-71`

O fluxo: criar statement → categorizar → bulk insert → update statement → detectar transferências **não está envolvido em `Repo.transaction/1`**. Se o bulk insert falhar, o statement fica em "processing" eternamente.

**Correção:** Envolver todo o processamento em `Repo.transaction/1`.

Mesmo problema em `lib/grana/investments/statement_processor.ex:65-84`.

---

### 2.4 [ALTO] Índices compostos faltando

A maioria das queries filtra por `user_id + date`, mas não existem índices compostos:

```elixir
# FALTANDO nas migrations:
create index(:transactions, [:user_id, :date])
create index(:investment_transactions, [:user_id, :date])
```

**Impacto:** Full table scans em tabelas com alto volume de dados.

---

### 2.5 [ALTO] Campo `statement_type` sem NOT NULL

**Arquivo:** `priv/repo/migrations/20260217152702_add_statement_type_to_bank_statements.exs:6`

```elixir
add :statement_type, :string, default: "extrato"  # sem null: false!
```

**Impacto:** Valores NULL possíveis que quebram validações no changeset.

---

### 2.6 [MÉDIO] ILIKE search sem índice full-text

**Arquivo:** `lib/grana/banking.ex:230`

```elixir
where(query, [t], ilike(t.description, ^"%#{term}%"))
```

Busca com `ILIKE %...%` faz sequential scan. Além disso, wildcards do LIKE (`%`, `_`) no termo de busca não são escapados.

**Correção:** Adicionar índice trigram GIN e escapar wildcards:
```sql
CREATE INDEX transactions_desc_trgm ON transactions USING GIN (description gin_trgm_ops);
```

---

### 2.7 [MÉDIO] Validação de parcelas ausente

**Arquivo:** `priv/repo/migrations/20260216144623_add_installment_fields.exs:5-9`

Campos `installment_current` e `installment_total` sem:
- Constraint `CHECK (installment_current <= installment_total)`
- `validate_number` no changeset
- NOT NULL quando presentes juntos

---

### 2.8 [MÉDIO] Sem soft delete / audit trail

Quando dados são deletados (statements, categorias, transações), são permanentemente removidos. Sem trilha de auditoria para compliance financeiro.

---

### 2.9 [MÉDIO] date_trunc sem índice funcional

**Arquivo:** `lib/grana/banking.ex:771-784`

```elixir
select([t], fragment("DISTINCT date_trunc('month', ?)", t.date))
```

Sem índice funcional, calcula para cada row.

---

## 3. RESILIÊNCIA E ERROR HANDLING

### 3.1 [CRÍTICO] File.read! em uploads pode crashar LiveView

**Arquivos:** `lib/grana_web/live/upload_live.ex:433,467`

```elixir
{:ok, {entry.client_name, File.read!(path)}}
```

Qualquer erro de I/O (disco cheio, permissão negada) crasha o processo LiveView e o usuário perde a sessão.

**Correção:** Usar `File.read/1` com pattern matching.

---

### 3.2 [CRÍTICO] Sem job queue persistente

O processamento de uploads usa `Task.async/1`:
```elixir
Task.async(fn -> ... end)
```

- Se o LiveView crashar, jobs são perdidos
- Sem retry automático
- Sem visibilidade pós-upload
- Sem persistência de estado

**Correção:** Implementar Oban para processamento assíncrono com retries, persistência e observabilidade.

---

### 3.3 [ALTO] Sem retry/circuit breaker nas APIs externas

**Arquivos:**
- `lib/grana/ai/providers/gemini.ex:46-70` — Gemini API
- `lib/grana/investments/quote_provider.ex:57-67` — BRAPI
- `lib/grana/banking/parsers/pdf_extractor.ex:17` — PDF extraction (120s timeout!)

Nenhuma chamada externa tem:
- Retry com exponential backoff
- Circuit breaker
- Fallback gracioso diferenciado

O quote_provider retorna `{:ok, ...}` mesmo quando a API falha (mascarando o erro):
```elixir
{:error, reason} ->
  Logger.warning("QuoteProvider: API fetch failed...")
  stale = lookup_stale(missing)
  {:ok, Map.merge(cached, stale)}  # Retorna OK com dados stale!
```

---

### 3.4 [ALTO] Logging quase inexistente

Apenas 1 módulo usa `require Logger` entre os módulos críticos. Sem logging em:
- `banking/ai_analyzer.ex`
- `banking/ai_categorizer.ex`
- `banking/statement_processor.ex`
- `investments/statement_processor.ex`
- `upload_live.ex`

**Impacto:** Impossível debugar problemas em produção.

---

### 3.5 [ALTO] Sem endpoint de health check

Não existe `/health` ou `/ready` para monitoramento por load balancers ou Fly.io.

**Correção:** Adicionar rota simples que verifica banco e retorna 200.

---

### 3.6 [MÉDIO] Recursos de Xlsxir não são limpos em caso de erro

**Arquivo:** `lib/grana/investments/parsers/b3_xlsx.ex:10-31`

```elixir
File.write!(tmp_path, file_content)
# ... processamento ...
Enum.each(table_ids, &Xlsxir.close/1)  # Só executa se não houver exception
```

Se uma exception ocorrer entre `File.write!` e `Xlsxir.close`, o arquivo temporário e handles ficam vazando.

**Correção:** Usar `try/after` para garantir cleanup.

---

### 3.7 [MÉDIO] String.to_integer sem validação

**Arquivo:** `lib/grana_web/live/upload_live.ex:351`

```elixir
"bank_" <> raw -> {[String.to_integer(raw) | banks], invs}
```

Se `raw` não for numérico, crasha o LiveView.

---

### 3.8 [MÉDIO] Erro silencioso na categorização por IA

**Arquivo:** `lib/grana/banking/statement_processor.ex:146`

```elixir
case AICategorizer.categorize_batch(descriptions, categories, user_id) do
  {:ok, ai_category_ids} -> ...
  # Sem handler para {:error, _} !!
end
```

---

## 4. FRONTEND, UX E ACESSIBILIDADE

### 4.1 [CRÍTICO] Imagens sem alt text (20+ ocorrências)

**Arquivos:** `dashboard_live.ex`, `transactions_live.ex`, `investments_live.ex`, `upload_live.ex`, `landing_live.ex`, `analysis_live.ex`

```heex
<img src={bank_logo(b)} alt="" class="w-4 h-4 rounded-full" />
```

Falha WCAG 2.1 AA. Screen readers não conseguem identificar as imagens.

---

### 4.2 [ALTO] Assigns grandes sem temporary_assigns (memory leak)

**Arquivos:** `dashboard_live.ex`, `transactions_live.ex`, `upload_live.ex`

Datasets como `@summary`, `@transactions`, `@daily_spending`, `@monthly_ie`, `@yearly_spending` permanecem na memória do socket para todos os clientes conectados.

```elixir
{:ok, socket}  # Sem temporary_assigns!
```

**Correção:**
```elixir
{:ok, socket, temporary_assigns: [daily_spending: [], monthly_ie: []]}
```

---

### 4.3 [ALTO] handle_event sem tratamento de erro

**Arquivos:** `transactions_live.ex:309-327`, `upload_live.ex:307-336`

```elixir
{:ok, _} = Banking.update_transaction(transaction, %{category_id: cat_id})
```

Pattern match com `{:ok, _}` crasha o LiveView se a operação falhar.

**Correção:** Usar `case` ou `with` com fallback para error.

---

### 4.4 [MÉDIO] Formulários sem labels e aria-labels

Inputs de busca, filtros de data e valores em `transactions_live.ex:495-600` não têm `<label>` nem `aria-label`.

---

### 4.5 [MÉDIO] Botões com ícone sem aria-label

Botões de fechar, filtros e tabs em `dashboard_live.ex:625-642`, `upload_live.ex:625-652` são apenas ícones sem descrição para leitores de tela.

---

### 4.6 [MÉDIO] Paginação sem contexto para acessibilidade

**Arquivo:** `transactions_live.ex:784-809`

Links de página são apenas números sem `aria-label` ou `aria-current`.

---

### 4.7 [MÉDIO] Gráficos vazios sem feedback visual

**Arquivo:** `assets/js/app.js:52-120`

Quando dados estão vazios, o chart simplesmente não renderiza nada — sem mensagem "Sem dados".

---

### 4.8 [BAIXO] Sem loading state em formulários de categorias

**Arquivo:** `lib/grana_web/live/categories_live.ex`

Botão de salvar sem `phx-disable-with`, permitindo múltiplos cliques.

---

## 5. DEPLOY E INFRAESTRUTURA

### 5.1 [ALTO] min_machines_running = 0

**Arquivo:** `fly.toml`

```toml
min_machines_running = 0
auto_stop_machines = 'stop'
```

A aplicação pode ser completamente desligada entre requests, causando cold starts de vários segundos.

**Correção:** `min_machines_running = 1`

---

### 5.2 [MÉDIO] Pool size pode ser insuficiente

**Arquivo:** `config/runtime.exs`

Default de 10 conexões com limite de 1000 conexões HTTP simultâneas pode causar timeouts no banco.

---

### 5.3 [MÉDIO] Sem configuração de connection timeout no Repo

```elixir
pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
# Falta: pool_timeout, queue_timeout
```

---

### 5.4 [BAIXO] 1 CPU / 1 GB de memória

Para processamento de PDFs com IA (120s timeout), cálculos financeiros e múltiplos uploads simultâneos, recursos podem ser insuficientes em pico.

---

## 6. TESTES

### 6.1 [MÉDIO] Cobertura incompleta em paths críticos

**Presente:**
- Autenticação de usuário
- Parsers CSV (Nubank, Bradesco)
- AI analyzer
- Módulo banking

**Ausente:**
- Quote provider (API externa crítica)
- PDF extractor
- Statement processor (integração)
- Investment statement processor
- Testes de falha de API
- Testes de upload concurrent
- Testes de edge cases em parsers

---

## Checklist para Produção

### Bloqueantes (Fazer ANTES do lançamento)

- [ ] Revogar e regenerar todos os secrets expostos no `.env`
- [ ] Remover `.env` do histórico git
- [ ] Habilitar verificação TLS no SMTP (`verify: :verify_peer`)
- [ ] Corrigir XSS no `innerHTML` dos tooltips (app.js)
- [ ] Criptografar API keys do usuário no banco
- [ ] Implementar rate limiting em endpoints de autenticação
- [ ] Adicionar headers de segurança (CSP, X-Frame-Options, etc.)
- [ ] Substituir `File.read!` por `File.read` com error handling
- [ ] Envolver processamento de statement em `Repo.transaction`
- [ ] Adicionar health check endpoint `/health`
- [ ] Setar `min_machines_running = 1` no fly.toml

### Alta Prioridade (Semana 1 pós-launch)

- [ ] Implementar Oban para processamento assíncrono
- [ ] Adicionar retry com backoff nas chamadas de API (Gemini, BRAPI)
- [ ] Adicionar logging estruturado nos módulos críticos
- [ ] Criar índices compostos `[user_id, date]` em transactions
- [ ] Adicionar `NOT NULL` em `statement_type`
- [ ] Implementar `temporary_assigns` nos LiveViews
- [ ] Adicionar error handling em todos `handle_event`
- [ ] Adicionar alt text em todas as imagens
- [ ] Corrigir N+1 queries em `mark_inter_account_transfers` e `categorize_transaction`

### Média Prioridade (Mês 1)

- [ ] Implementar circuit breaker para APIs externas
- [ ] Adicionar audit logging para operações sensíveis
- [ ] Implementar soft delete para compliance
- [ ] Adicionar índice trigram para busca de transações
- [ ] Adicionar índice funcional para `date_trunc`
- [ ] Melhorar validação de parcelas (check constraint)
- [ ] Adicionar aria-labels em botões, forms e paginação
- [ ] Adicionar estados de loading em todos os formulários
- [ ] Escapar wildcards LIKE na busca
- [ ] Garantir cleanup de recursos Xlsxir com `try/after`
- [ ] Expandir cobertura de testes para paths críticos
- [ ] Admin por role ao invés de email

### Baixa Prioridade (Backlog)

- [ ] Particionamento de tabelas de alto volume
- [ ] Scanning de malware em uploads
- [ ] Validação de magic bytes em arquivos
- [ ] Melhorar feedback visual em gráficos vazios
- [ ] Testar `scrollbar-gutter` cross-browser
- [ ] Cookie SameSite para Strict
- [ ] Focus styles adequados para navegação por teclado
