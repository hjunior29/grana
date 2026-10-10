# Grana

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Open Finance (Pluggy) — opcional

O Grana pode ler saldos, cartões e transações direto dos seus bancos pelo
[Open Finance Brasil](https://openfinancebrasil.org.br), via [Pluggy](https://pluggy.ai).
O caminho é o de **uso pessoal** da Pluggy (gratuito, até 5 conexões, sem uso comercial):
você autoriza seus bancos no **Meu Pluggy** e o Grana lê esses dados pelo conector MeuPluggy.

O Open Finance tem dois papéis, e **os uploads continuam sendo o histórico oficial**:

- **Estado atual**: o bloco *Hoje*, no topo do Resumo do Dashboard, mostra saldos, faturas
  abertas, limites e vencimentos.
- **Fonte para os períodos sem upload**: o que nenhum extrato/fatura importado cobre (por
  exemplo, o mês que ainda não fechou) entra como se fosse um extrato/fatura do próprio
  banco, marcado como "Open Finance", e aparece em todo o sistema. Quando você importa o
  arquivo daquele período, **o upload vence** e os dados do Open Finance saem dele.

A Pluggy é lida no máximo uma vez por hora (o Meu Pluggy atualiza uma vez por dia), ao
abrir o Dashboard ou as Transações — não há botão de sincronizar.

1. Defina uma chave própria de criptografia no `.env` **antes** de salvar qualquer segredo
   (sem ela o Grana usa a chave de desenvolvimento, que é pública neste repositório):

   ```bash
   CLOAK_KEY=   # gere com: openssl rand -base64 32
   ```

   Não troque essa chave depois de salvar dados cifrados — eles deixariam de ser legíveis.
2. Crie uma conta em [meu.pluggy.ai](https://meu.pluggy.ai) e conecte seus bancos lá
   (cada banco é autorizado no app do próprio banco).
3. Entre no [dashboard da Pluggy](https://dashboard.pluggy.ai) com a **mesma conta** e copie
   o Client ID e o Client Secret da sua aplicação em *Aplicações*.
4. Defina `PLUGGY_CLIENT_ID`/`PLUGGY_CLIENT_SECRET` no `.env` **ou**, se preferir, cole as
   credenciais em **Configurações → Open Finance** (a tela só oferece isso quando não há nada
   no `.env`). Pela tela elas são conferidas na Pluggy e o secret é guardado cifrado
   (AES-256-GCM); ele nunca volta para a tela. A chave do Gemini segue a mesma regra
   (`GEMINI_API_KEY`).
5. Clique em *Conectar via Meu Pluggy*, entre com sua conta do Meu Pluggy e escolha um banco.
   Repita para cada banco. (Também dá para colar o `itemId` de um item criado na página *Demo*
   do dashboard.)

Opcional: para o Grana saber assim que o Meu Pluggy atualizar, exponha o Grana em uma URL HTTPS
pública (ex.: `ngrok http 4000`) e defina `PLUGGY_WEBHOOK_URL=https://seu-dominio/webhooks/pluggy`
no `.env`. Não cadastre o webhook pelo dashboard da Pluggy: ele não aceita o header secreto que
autentica as chamadas. O próprio Grana registra o webhook pela API na próxima sincronização
(gera o segredo, guarda cifrado e o confere a cada sincronização).

Segurança: credenciais e segredos ficam só no servidor (o navegador recebe apenas um connect
token de 30 minutos para abrir o widget); salvar ou remover credenciais exige login recente; o
webhook só aceita chamadas com o header secreto, e o conteúdo dele nunca é usado — ele só
dispara uma nova leitura na API com as suas credenciais.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
