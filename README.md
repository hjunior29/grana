<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="priv/static/images/grana-lockup-dark.svg">
    <img alt="Grana" src="priv/static/images/grana-lockup.svg" width="320">
  </picture>
</p>

# Grana

Finanças pessoais **self-hosted**, para uma pessoa só. Importe extratos e faturas
(CSV/PDF), categorize e analise com IA, converse com os seus dados num chat (Gemini, OpenAI,
Claude ou qualquer serviço compatível, com a sua chave), acompanhe o dia a dia pelo
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

- Linux com systemd (Debian 12+/Ubuntu 22.04+, glibc ≥ 2.35 e OpenSSL 3), Docker **ou** uma
  conta no [Fly.io](https://fly.io) (sem servidor seu).
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
[Releases](https://github.com/hjunior29/grana/releases) e, na mesma pasta:

```bash
sha256sum -c grana-vX.Y.Z-linux-<arch>.tar.gz.sha256
sudo useradd --system --home-dir /var/lib/grana --shell /usr/sbin/nologin grana
sudo mkdir -p /opt/grana /etc/grana
sudo tar -xzf grana-vX.Y.Z-linux-<arch>.tar.gz -C /opt/grana --strip-components=1
sudo install -m 640 -o root -g grana /opt/grana/env.example /etc/grana/grana.env
sudo cp /opt/grana/grana.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now grana
```

O serviço cria `/var/lib/grana` sozinho.

### Docker Compose

```bash
curl -fsSLO https://raw.githubusercontent.com/hjunior29/grana/main/docker-compose.yml
docker compose up -d
```

A imagem (`ghcr.io/hjunior29/grana`, amd64 e arm64) guarda tudo no volume `grana-data`
(`/data`). Para variáveis de ambiente, crie um `.env` ao lado do compose. A porta é publicada
só nesta máquina (`127.0.0.1:4000`): `BIND_IP=0.0.0.0` no `.env` a abre para a rede local, e
`PORT` troca a porta do host (dentro do container é sempre a 4000).

### Fly.io (na nuvem, sem servidor seu)

O [Fly.io](https://fly.io) roda a imagem pronta numa máquina pequena, com o banco num volume
e HTTPS no endereço `https://<app>.fly.dev`. Com o [`flyctl`](https://fly.io/docs/flyctl/install/)
instalado e logado (`fly auth login`), numa pasta vazia:

```bash
curl -fsSLO https://raw.githubusercontent.com/hjunior29/grana/main/deploy/fly.toml
fly apps create meu-grana                                  # nome único: vira meu-grana.fly.dev
fly volumes create grana_data -a meu-grana -r gru -s 1 -y  # 1 GB em São Paulo
fly deploy -a meu-grana --ha=false                         # uma máquina só: o banco é SQLite
fly logs -a meu-grana --no-tail                            # o código do setup
```

Troque `meu-grana` pelo nome do seu app em todos os comandos. O
[`deploy/fly.toml`](deploy/fly.toml) já traz o volume em `/data`, o
`TRUST_PROXY_HEADERS=true` que o proxy HTTPS do Fly exige, o health check e uma máquina de
512 MB. Dicas:

- **Auto stop:** sem acesso por alguns minutos, a máquina para e só o volume é cobrado; o
  próximo acesso a liga em alguns segundos. `auto_stop_machines = "suspend"` volta mais
  rápido, e `min_machines_running = 1` a deixa sempre ligada.
- **Com a máquina parada, nada roda em segundo plano:** a releitura do Open Finance espera o
  próximo acesso (o webhook da Pluggy acorda a máquina), e uma importação longa precisa da
  aba aberta até terminar.
- **Um código por boot:** se a máquina parar antes de você criar a conta, o próximo acesso gera
  outro código; vale o último do `fly logs`.
- **Backup:** o Fly tira snapshots diários do volume (5 dias; `snapshot_retention` no
  `fly.toml` vai até 60), e o backup pela tela continua valendo.
- **Links de email e webhook:** `fly secrets set -a meu-grana PUBLIC_URL=https://meu-grana.fly.dev`.
  Os outros segredos (SMTP, chaves de IA, Pluggy) também vão por `fly secrets set`, ou pela tela.
- **Outra região:** `fly platform regions`; o volume e o `primary_region` precisam ser da mesma.

### PikaPods

O [PikaPods](https://www.pikapods.com) hospeda apps open source do catálogo deles, sem
terminal, a partir de US$ 1,80/mês. O Grana ainda não está no catálogo: para pedir, vote ou
sugira o app em [feedback.pikapods.com](https://feedback.pikapods.com). Até lá, o Fly.io é o
caminho na nuvem.

## Primeiro acesso

O app escuta só na própria máquina (`127.0.0.1:4000`). Para abrir de outro computador da
rede, defina `LISTEN_IP=0.0.0.0` em `/etc/grana/grana.env` (systemd) ou `BIND_IP=0.0.0.0` no
`.env` (Docker) e abra `http://IP-DO-SERVIDOR:4000`; para um domínio com HTTPS, veja
[HTTPS e rede local](#https-e-rede-local). No Fly.io, abra `https://<app>.fly.dev`.

Com a instância sem dono, as telas do app levam ao assistente de setup (`/setup`), que pede o
**código de uso único** impresso no log:

```bash
sudo journalctl -u grana | grep -A3 "configuração inicial"   # systemd
docker compose logs grana                                     # Docker
fly logs -a meu-grana --no-tail                               # Fly.io
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
| `PORT` | Porta HTTP (4000). No Docker Compose, a porta publicada no host (o container usa sempre a 4000) |
| `LISTEN_IP` | IP em que o app escuta (padrão `127.0.0.1`; `0.0.0.0` abre para a rede local). A imagem Docker já usa `0.0.0.0` |
| `BIND_IP` | Docker Compose: IP do host em que a porta é publicada (padrão `127.0.0.1`; `0.0.0.0` para a rede local) |
| `PUBLIC_URL` | URL pública, usada nos links de email e no webhook da Pluggy |
| `SECRET_KEY_BASE`, `CLOAK_KEY` | Gerados no primeiro boot em `$DATA_DIR/secrets/`; defina só para controlá-los |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_TLS`, `MAIL_FROM_NAME`, `MAIL_FROM_ADDRESS` | SMTP (liga o 2FA) |
| `GEMINI_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY` | Provedores de IA pelo ambiente (aparecem na tela como `.env`) |
| `PLUGGY_CLIENT_ID`, `PLUGGY_CLIENT_SECRET`, `PLUGGY_WEBHOOK_URL` | Open Finance |
| `TRUST_PROXY_HEADERS` | `true` atrás de proxy reverso ou no Fly.io: confia no `X-Forwarded-*` para o HTTPS (cookies seguros e o LiveView) e para o IP real no rate limit. Sem proxy na frente, deixe desligado |
| `POOL_SIZE`, `CACHE_ENABLED`, `CACHE_TTL_SECONDS`, `SKIP_MIGRATIONS` | Ajustes finos |

> **Guarde a `CLOAK_KEY`** em local seguro e **separada** do arquivo de backup (por exemplo, no seu gerenciador de senhas). Ela
> decifra as credenciais salvas (chaves de IA, Pluggy, SMTP, CPF); sem ela, ao restaurar em outra
> instância você precisa cadastrá-las de novo. Não guarde o arquivo `secrets/` no mesmo diretório público do backup.

## Inteligência artificial

Em **Configurações → Inteligência artificial** você cadastra quantos provedores quiser:
**Google Gemini**, **OpenAI**, **Anthropic (Claude)** ou qualquer serviço compatível com a API
de chat da OpenAI (OpenRouter, Groq, Together, Ollama, LM Studio... informe o endereço, ex.:
`http://localhost:11434/v1`). A chave é conferida na hora e guardada cifrada. Provedores
definidos por variável de ambiente aparecem na lista com a tag `.env` e não são editáveis
pela tela.

A IA entra em quatro lugares, cada um um **especialista** com o seu próprio modelo padrão
(e um seletor na tela para trocar só naquela vez):

- **Pesquisa avançada**: descreva a busca em português e a IA monta a string da pesquisa,
  validada pelo próprio Grana antes de chegar a você.
- **Análise**: no Painel, logo abaixo dos filtros, a nota, o resumo, os pontos e as dicas do
  mês ou do ano selecionado. Roda em segundo plano (pode sair da tela), guarda o modelo que a
  gerou e só é refeita quando os dados do período mudam.
- **Processamento**: leitura de PDFs que os parsers não entendem e categorização do que as
  regras não pegaram. O histórico mostra o modelo usado em cada extrato.
- **Chat**: conversa com os seus dados por mês, ano, banco, conta ou categoria. Todo número
  vem de consultas ao banco; a IA só redige a resposta (em HTML, no estilo da tela) e pode
  acionar os outros especialistas.

Os **modelos não ficam no código**: a lista vem da API de cada provedor, então um modelo novo
aparece sozinho. Para a lista não encher de modelos de imagem, áudio e gerações antigas, o
Grana a cruza uma vez por dia com o catálogo aberto [models.dev](https://models.dev): ficam
só os modelos de texto com suporte a ferramentas, o mais novo de cada família e nada com mais
de um ano em relação ao modelo mais novo do provedor. Essa é a única chamada de rede fora dos
seus provedores; se o catálogo estiver fora do ar, vale uma filtragem por palavra. Se um modelo
recusar algum parâmetro (ex.: `temperature` em modelos de raciocínio), o Grana ajusta e tenta
de novo.

> **Privacidade:** ao configurar provedores em nuvem (Gemini, OpenAI, Claude), dados das requisições (como descrições de transações e perguntas de chat) são transmitidos diretamente à API do provedor. Para manter 100% dos dados na sua máquina/rede local, utilize provedores locais como Ollama ou LM Studio via conector OpenAI-compatível.

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

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

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
bash install.sh --update                        # systemd, pelo tarball: baixa a última versão e reinicia
git pull && ./deploy/install.sh --from-source   # systemd, compilado no servidor
docker compose pull && docker compose up -d     # Docker
fly deploy -a meu-grana --ha=false              # Fly.io: baixa a imagem latest de novo
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
sudo -u grana /opt/grana/bin/grana-reset-password   # systemd
docker exec grana /app/bin/grana-reset-password     # Docker
fly ssh console -a meu-grana -C "su -s /bin/sh grana -c 'DATA_DIR=/data /app/bin/grana-reset-password'"   # Fly.io
```

Se um SMTP salvo pela tela estiver quebrado e o 2FA te trancou para fora:

```bash
sudo -u grana /opt/grana/bin/grana-disable-smtp
docker exec grana /app/bin/grana-disable-smtp
fly ssh console -a meu-grana -C "su -s /bin/sh grana -c 'DATA_DIR=/data /app/bin/grana-disable-smtp'"
```

No Fly.io, abra o site antes para acordar a máquina se ela estiver parada.

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
