# Fider - Feedback & Feature Requests

Instância do [Fider](https://fider.io) para coletar solicitações de novos bancos e instituições de investimento.

## Deploy

### 1. Criar app no Fly.io

```bash
cd fider/
fly apps create gra-na-fider
```

### 2. Criar e anexar Postgres

```bash
fly postgres create --name gra-na-fider-db --region gru --vm-size shared-cpu-1x --volume-size 1
fly postgres attach gra-na-fider-db -a gra-na-fider
```

> O `fly postgres attach` configura `DATABASE_URL` automaticamente como secret.

### 3. Configurar secrets

```bash
fly secrets set \
  BASE_URL="https://gra-na-fider.fly.dev" \
  JWT_SECRET="$(openssl rand -hex 32)" \
  EMAIL_NOREPLY="noreply@vertices.me" \
  EMAIL_SMTP_HOST="smtp.mailersend.net" \
  EMAIL_SMTP_PORT="587" \
  EMAIL_SMTP_USERNAME="MS_pwjBAB@vertices.me" \
  EMAIL_SMTP_PASSWORD="<ver .env do projeto>" \
  EMAIL_SMTP_ENABLE_STARTTLS="true" \
  -a gra-na-fider
```

### 4. Deploy

```bash
fly deploy
```

### 5. Verificar

```bash
fly status -a gra-na-fider
fly logs -a gra-na-fider
curl https://gra-na-fider.fly.dev/_health
```

## Pós-deploy

No primeiro acesso, o Fider pedirá para criar o tenant (nome do site + email do admin). Após isso:

1. Acesse **Site Settings > Authentication** para configurar OAuth (opcional)
2. Crie categorias como "Novo Banco", "Nova Corretora", "Melhoria"
3. Compartilhe o link `https://gra-na-fider.fly.dev` com os usuários

## Variáveis de ambiente

| Variável | Descrição |
|----------|-----------|
| `DATABASE_URL` | Auto-configurado pelo `fly postgres attach` |
| `BASE_URL` | URL pública do Fider |
| `JWT_SECRET` | Secret para tokens JWT |
| `EMAIL_NOREPLY` | Email remetente |
| `EMAIL_SMTP_*` | Configuração SMTP (MailerSend) |

## Manutenção

```bash
# Atualizar para nova versão do Fider
# Edite fly.toml: image = "getfider/fider:X.Y.Z"
fly deploy

# Ver logs
fly logs -a gra-na-fider

# Console do banco
fly postgres connect -a gra-na-fider-db
```
