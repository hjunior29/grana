<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="priv/static/images/grana-lockup-dark.svg">
    <img alt="Grana" src="priv/static/images/grana-lockup.svg" width="320">
  </picture>
</p>

# Grana

Finanças pessoais **self-hosted**, para uma pessoa só. Importe extratos e faturas
(CSV/PDF), categorize com IA (Gemini, OpenAI, Claude ou qualquer serviço compatível, com a sua chave), acompanhe o dia a dia pelo
Open Finance (opcional) e veja tudo num painel. Seus dados ficam num único arquivo SQLite,
no seu servidor.

- **Uploads são o histórico oficial.** O Open Finance mostra o estado de hoje e só preenche
  os meses sem upload; o upload sempre vence.
- **Uma conta, a do dono.** Não existe cadastro: o primeiro acesso é um assistente
  protegido por um código impresso no log do servidor.
- **Login com 2FA por email** quando o SMTP está configurado; recuperação de senha por
  email ou por comando no servidor.
- **Backup e restauração pela tela**, num arquivo.

## Requisitos

- Linux com systemd (Debian 12+/Ubuntu 22.04+, glibc ≥ 2.35 e OpenSSL 3) **ou** Docker.
- `poppler-utils` (`pdftotext`) para ler PDFs — o `install.sh` e a imagem Docker já cuidam disso.
- Para compilar no próprio servidor: Erlang/OTP 28 e Elixir 1.18 (o `.tool-versions` fixa as
  versões; funciona com [mise](https://mise.jdx.dev) ou asdf).

Nenhuma variável de ambiente é obrigatória.

## Instalação

### Release com systemd (recomendado)

```bash
curl -fsSL https://raw.githubusercontent.com/hjunior29/grana/main/deploy/install.sh -o install.sh
bash install.sh                      # última versão, tarball pronto do GitHub Releases
bash install.sh --version v1.0.0     # uma versão específica
```

O script baixa o tarball da sua arquitetura (x86_64 ou arm64), confere o `sha256`, cria o
usuário `grana`, instala em `/opt/grana`, cria `/etc/grana/grana.env` e ativa o serviço
(`systemctl status grana`). Dados em `/var/lib/grana`.

Para compilar no próprio servidor, a partir de um clone:

```bash
git clone https://github.com/hjunior29/grana && cd grana
./deploy/install.sh --from-source
```

**Tarball manual:** baixe `grana-vX.Y.Z-linux-<arch>.tar.gz` e o `.sha256` em
[Releases](https://github.com/hjunior29/grana/releases), confira com `sha256sum -c`,
extraia em `/opt/grana`, copie `env.example` para `/etc/grana/grana.env` e `grana.service`
para `/etc/systemd/system/`.

### Docker Compose

```bash
curl -fsSLO https://raw.githubusercontent.com/hjunior29/grana/main/docker-compose.yml
docker compose up -d
```

A imagem (`ghcr.io/hjunior29/grana`, amd64 e arm64) guarda tudo no volume `grana-data`
(`/data`). Para variáveis de ambiente, crie um `.env` ao lado do compose.

## Primeiro acesso

Abra `http://IP-DO-SERVIDOR:4000`. Com a instância sem dono, qualquer endereço leva ao
assistente de setup, que pede o **código de uso único** impresso no log:

```bash
sudo journalctl -u grana | grep -A3 "configuração inicial"   # systemd
docker compose logs grana                                     # Docker
```

O assistente explica como o Grana funciona e pergunta se você quer uma **nova instalação** ou
**restaurar um backup**. Depois de criar a conta (nome, email e senha), um onboarding opcional
configura aparência, email (SMTP), IA e Open Finance — cada etapa pode ser
pulada e refeita em Configurações. O código vale só até o dono ser criado; um novo boot gera
outro.

## Variáveis de ambiente

Todas opcionais — veja o [`.env.example`](.env.example) comentado. O que estiver no
ambiente **tem prioridade** sobre o que for salvo pela tela (a tela só oferece salvar
quando não há nada no ambiente).

| Variável | Para quê |
|---|---|
| `DATA_DIR` | Pasta de dados (padrão `/var/lib/grana`; `/data` no Docker) |
| `DATABASE_PATH` | Caminho do banco (padrão `$DATA_DIR/grana.db`) |
| `PORT` | Porta HTTP (4000) |
| `PUBLIC_URL` | URL pública, usada nos links de email e no webhook da Pluggy |
| `SECRET_KEY_BASE`, `CLOAK_KEY` | Gerados no primeiro boot em `$DATA_DIR/secrets/`; defina só para controlá-los |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_TLS`, `MAIL_FROM_NAME`, `MAIL_FROM_ADDRESS` | SMTP (liga o 2FA) |
| `GEMINI_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY` | Provedores de IA pelo ambiente (aparecem na tela como `.env`) |
| `PLUGGY_CLIENT_ID`, `PLUGGY_CLIENT_SECRET`, `PLUGGY_WEBHOOK_URL` | Open Finance |
| `TRUST_PROXY_HEADERS` | `true` atrás de proxy reverso (usa `X-Forwarded-For` no rate limit) |
| `POOL_SIZE`, `CACHE_ENABLED`, `CACHE_TTL_SECONDS`, `SKIP_MIGRATIONS` | Ajustes finos |

> **Guarde a `CLOAK_KEY`** (ou a pasta `$DATA_DIR/secrets/`) junto dos seus backups. Ela
> decifra as credenciais salvas (chaves de IA, Pluggy, SMTP, CPF); sem ela, ao restaurar em outra
> instância você precisa cadastrá-las de novo.

## Provedores de IA

Em **Configurações → LLM** você cadastra quantos provedores quiser: **Google Gemini**,
**OpenAI**, **Anthropic (Claude)** ou qualquer serviço compatível com a API de chat da OpenAI
(OpenRouter, Groq, Together, Ollama, LM Studio... informe o endereço, ex.:
`http://localhost:11434/v1`). A chave é conferida na hora e guardada cifrada.

Os **modelos não ficam no código**: a lista vem da própria API de cada provedor, então um
modelo novo aparece sozinho, sem atualizar o Grana. Você escolhe o provedor + modelo padrão
(usado na categorização, nas análises e na leitura de PDFs). Se um modelo recusar algum
parâmetro (ex.: `temperature` em modelos de raciocínio), o Grana ajusta e tenta de novo.

Provedores definidos por variável de ambiente aparecem na lista com a tag `.env` e não são
editáveis pela tela.

## HTTPS e rede local

O app **não força HTTPS**: ele responde por HTTP na rede local (`http://192.168.x.x:4000`,
Tailscale etc.) e o HTTPS no seu domínio fica por conta de um proxy reverso. Defina
`PUBLIC_URL=https://grana.seudominio.com` e, atrás de proxy, `TRUST_PROXY_HEADERS=true`.

**Caddy**

```caddyfile
grana.seudominio.com {
    reverse_proxy 127.0.0.1:4000
}
```

**Nginx** (o LiveView usa WebSocket — o `Upgrade` é obrigatório)

```nginx
server {
    server_name grana.seudominio.com;
    # listen 443 ssl; ssl_certificate ...; ssl_certificate_key ...;

    location / {
        proxy_pass http://127.0.0.1:4000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 500m;   # restaurar backups grandes
    }
}
```

**Cloudflare Tunnel:** `cloudflared tunnel --url http://localhost:4000` (ou um túnel nomeado
apontando para `http://localhost:4000`), com `PUBLIC_URL` no domínio do túnel.

## Atualização

```bash
./deploy/install.sh --update              # systemd: refaz o download/build e reinicia
docker compose pull && docker compose up -d   # Docker
```

As migrations rodam sozinhas no boot. **Baixe um backup antes** (Configurações → Backup).

## Backup e restauração

Em **Configurações → Backup**: *Baixar backup* gera um `.db` consistente (exige login recente).
Para restaurar, envie o arquivo em Configurações ou no passo "Restaurar um backup" do setup
de uma instância nova:

- se o backup tiver mais de um usuário, escolha qual manter (a instância é de uma pessoa só);
- informe a `CLOAK_KEY` da instância de origem para levar as credenciais cifradas — sem ela,
  elas são apagadas e você as cadastra de novo;
- se o usuário não tinha senha no backup, defina uma nova.

Restaurar **substitui todos os dados**. Para recomeçar do zero, **Configurações → Zona de Perigo →
Apagar todos os dados** (pede a senha e `APAGAR`) devolve a instância ao assistente de setup.

## Esqueci a senha / SMTP quebrado

Com SMTP configurado, use *Esqueci a senha* na tela de login. Sem ele (ou se o email não
chegar), gere o link no servidor:

```bash
sudo -u grana /opt/grana/bin/grana-reset-password          # systemd
docker exec -u nobody grana /app/bin/grana-reset-password  # Docker
```

Se um SMTP salvo pela tela estiver quebrado e o 2FA te trancou para fora:

```bash
sudo -u grana /opt/grana/bin/grana-disable-smtp
docker exec -u nobody grana /app/bin/grana-disable-smtp
```

(SMTP vindo de variáveis de ambiente só se desliga removendo as variáveis e reiniciando.)

## Open Finance (Pluggy) — opcional

O Grana lê saldos, cartões e transações direto dos seus bancos pelo
[Open Finance Brasil](https://openfinancebrasil.org.br), via [Pluggy](https://pluggy.ai), no
caminho de **uso pessoal** (gratuito, até 5 conexões, sem uso comercial): você autoriza seus
bancos no **Meu Pluggy** e o Grana lê esses dados pelo conector MeuPluggy.

- **Estado atual:** o bloco *Hoje*, no topo do Resumo, mostra saldos, faturas abertas, limites
  e vencimentos.
- **Fonte para os períodos sem upload:** o que nenhum extrato/fatura importado cobre entra
  como extrato/fatura do próprio banco, marcado como "Open Finance". Quando você importa o
  arquivo daquele período, **o upload vence**.

A Pluggy é lida no máximo uma vez por hora, ao abrir o Dashboard ou as Transações.

1. Crie uma conta em [meu.pluggy.ai](https://meu.pluggy.ai) e conecte seus bancos lá.
2. No [dashboard da Pluggy](https://dashboard.pluggy.ai), com a **mesma conta**, copie o
   Client ID e o Client Secret da sua aplicação (*Aplicações*).
3. Informe-os em `PLUGGY_CLIENT_ID`/`PLUGGY_CLIENT_SECRET` **ou** em **Configurações → Open
   Finance** (a tela só oferece isso quando não há nada no ambiente; o secret é conferido na
   Pluggy e guardado cifrado, e nunca volta para a tela).
4. Clique em *Conectar via Meu Pluggy* e escolha um banco. Repita para cada banco.

**Webhook (opcional):** para o Grana saber assim que o Meu Pluggy atualizar, a instância
precisa de uma URL **pública** em HTTPS. Com `PUBLIC_URL` definido, o webhook é
`$PUBLIC_URL/webhooks/pluggy` automaticamente (ou defina `PLUGGY_WEBHOOK_URL`). Não cadastre o
webhook pelo dashboard da Pluggy: ele não aceita o header secreto que autentica as chamadas —
o Grana o registra pela API na próxima sincronização. Sem webhook, a releitura de 1 h continua
funcionando.

## Desenvolvimento

```bash
mix setup            # deps, banco SQLite e assets
mix phx.server       # http://localhost:4000 (sem dono: cai no /setup, código no console)
make help            # atalhos (testes, cobertura, quality gate)
```

Em dev, os emails vão para `http://localhost:4000/dev/mailbox` (ou use `SMTP_IN_DEV=true`
com SMTP no `.env`). Quality gate completo:

```bash
mix format --check-formatted && mix compile --warnings-as-errors && mix credo --strict && MIX_ENV=test mix coveralls
```

Para validar uma release como em produção:

```bash
MIX_ENV=prod mix assets.deploy && MIX_ENV=prod mix release
DATA_DIR=$(mktemp -d) PORT=4010 PHX_SERVER=true _build/prod/rel/grana/bin/grana start
```
