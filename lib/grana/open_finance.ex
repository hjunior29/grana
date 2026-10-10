defmodule Grana.OpenFinance do
  @moduledoc """
  Integração Open Finance via Pluggy, pensada para uso pessoal: o usuário autoriza
  os bancos no Meu Pluggy e conecta o Grana a eles pelo conector MeuPluggy.

  As credenciais da aplicação Pluggy vêm do ambiente (`.env`) ou, se não houver
  nada lá, das salvas pela tela de cada usuário (secret cifrado).

  Os dados são espelhados em tabelas próprias (`open_finance_*`) e, por enquanto,
  apenas exibidos — não se misturam com os extratos e faturas importados.
  """

  import Ecto.Query

  require Logger

  alias Grana.Accounts.{Scope, User}
  alias Grana.OpenFinance.{Account, Connection, Pluggy, Transaction}
  alias Grana.Repo
  alias Grana.Workers.OpenFinanceSyncWorker

  # Header que exigimos nos webhooks. A Pluggy não assina os webhooks de dados;
  # headers customizados (só configuráveis via API) são a forma de autenticá-los.
  @webhook_secret_header "x-grana-webhook-secret"

  # Datas da Pluggy vêm em UTC; o horário de Brasília é UTC-3 (sem horário de verão desde 2019).
  @brt_offset_hours -3

  @insert_chunk_size 500

  defdelegate meu_pluggy_connector_id, to: Pluggy
  defdelegate webhook_url, to: Pluggy

  def webhook_secret_header, do: @webhook_secret_header

  @doc "Tópico PubSub com as atualizações de Open Finance do usuário."
  def topic(user_id), do: "open_finance:#{user_id}"

  ## Credenciais

  @doc """
  Credenciais da Pluggy do usuário: as do ambiente ou, se não houver, as salvas
  no Grana. `nil` quando a integração não está configurada.
  """
  def credentials(%Scope{user: user}), do: credentials(user)
  def credentials(%User{} = user), do: Pluggy.env_credentials() || saved_credentials(user)

  defp saved_credentials(%User{pluggy_client_id: client_id, pluggy_client_secret: secret})
       when is_binary(client_id) and is_binary(secret),
       do: %{client_id: client_id, client_secret: secret}

  defp saved_credentials(%User{}), do: nil

  @doc "De onde vêm as credenciais em uso: `:env`, `:database` ou `nil`."
  def credentials_source(%Scope{user: user}) do
    cond do
      Pluggy.env_credentials() -> :env
      saved_credentials(user) -> :database
      true -> nil
    end
  end

  def configured?(scope), do: credentials(scope) != nil

  defp fetch_credentials(scope_or_user) do
    case credentials(scope_or_user) do
      nil -> {:error, :not_configured}
      credentials -> {:ok, credentials}
    end
  end

  @doc "Changeset do formulário de credenciais. O secret salvo nunca volta para a tela."
  def change_credentials(%Scope{user: user}, attrs \\ %{}) do
    User.pluggy_credentials_changeset(%{user | pluggy_client_secret: nil}, attrs)
  end

  @doc """
  Salva as credenciais depois de conferi-las na Pluggy, para que um secret errado
  apareça na hora como erro do formulário.
  """
  def save_credentials(%Scope{user: user}, attrs) do
    changeset = User.pluggy_credentials_changeset(user, attrs)

    with {:ok, valid_user} <- Ecto.Changeset.apply_action(changeset, :update),
         :ok <- Pluggy.verify_credentials(credentials(valid_user)) do
      Repo.update(changeset)
    else
      {:error, %Ecto.Changeset{}} = error ->
        error

      {:error, reason} ->
        {:error,
         changeset
         |> Ecto.Changeset.add_error(:pluggy_client_secret, error_message(reason))
         |> Map.put(:action, :update)}
    end
  end

  @doc "Apaga as credenciais salvas (e o segredo do webhook). As conexões continuam no banco."
  def remove_credentials(%Scope{user: user}) do
    user
    |> Ecto.Changeset.change(
      pluggy_client_id: nil,
      pluggy_client_secret: nil,
      pluggy_webhook_secret: nil
    )
    |> Repo.update()
  end

  ## Conexões

  def list_connections(%Scope{user: user}) do
    accounts_query = from(a in Account, order_by: [asc: a.type, asc: a.name])

    from(c in Connection,
      where: c.user_id == ^user.id,
      order_by: [asc: c.inserted_at, asc: c.id],
      preload: [accounts: ^accounts_query]
    )
    |> Repo.all()
  end

  def get_connection!(%Scope{user: user}, id),
    do: Repo.get_by!(Connection, id: id, user_id: user.id)

  @doc "Connect token (30 min) para abrir o widget Pluggy Connect no navegador."
  def create_connect_token(%Scope{user: user} = scope) do
    with {:ok, credentials} <- fetch_credentials(scope) do
      Pluggy.create_connect_token(credentials, to_string(user.id))
    end
  end

  @doc """
  Vincula um Item da Pluggy ao usuário e agenda a primeira sincronização.

  O id chega do widget (`onSuccess`), do webhook `item/created` ou colado à mão,
  então sempre conferimos o Item na API com as credenciais da aplicação antes de
  gravar — um id de outra aplicação ou inexistente dá `{:error, :not_found}`.
  """
  def add_connection(%Scope{user: user} = scope, item_id) when is_binary(item_id) do
    with {:ok, credentials} <- fetch_credentials(scope),
         {:ok, item_id} <- cast_item_id(item_id),
         :ok <- ensure_not_connected(item_id),
         {:ok, item} <- Pluggy.get_item(credentials, item_id),
         {:ok, connection} <- insert_connection(user, item_id, item) do
      enqueue_sync(connection)
      {:ok, connection}
    end
  end

  defp cast_item_id(item_id) do
    case Ecto.UUID.cast(String.trim(item_id)) do
      {:ok, item_id} -> {:ok, item_id}
      :error -> {:error, :invalid_item_id}
    end
  end

  defp ensure_not_connected(item_id) do
    if Repo.exists?(from(c in Connection, where: c.item_id == ^item_id)),
      do: {:error, :already_connected},
      else: :ok
  end

  defp insert_connection(user, item_id, item) do
    %Connection{user_id: user.id, item_id: item_id}
    |> Connection.item_changeset(item_attrs(item))
    |> Repo.insert()
    |> case do
      {:ok, connection} -> {:ok, connection}
      # Corrida com outro caminho (widget x webhook) gravando o mesmo Item.
      {:error, %Ecto.Changeset{}} -> {:error, :already_connected}
    end
  end

  @doc """
  Remove a conexão: apaga o Item na Pluggy (revoga o acesso desta aplicação) e
  os dados espelhados aqui. A conexão original no Meu Pluggy continua intacta.
  """
  def delete_connection(
        %Scope{user: %{id: user_id}} = scope,
        %Connection{user_id: user_id} = connection
      ) do
    with {:ok, credentials} <- fetch_credentials(scope) do
      case Pluggy.delete_item(credentials, connection.item_id) do
        result when result in [:ok, {:error, :not_found}] -> Repo.delete(connection)
        {:error, _} = error -> error
      end
    end
  end

  ## Sincronização

  def enqueue_sync(%Connection{id: id}) do
    %{"connection_id" => id} |> OpenFinanceSyncWorker.new() |> Oban.insert()
  end

  def enqueue_user_syncs(%Scope{} = scope) do
    scope
    |> list_connections()
    |> Enum.each(&enqueue_sync/1)
  end

  def enqueue_sync_all do
    Connection
    |> Repo.all()
    |> Enum.each(&enqueue_sync/1)
  end

  @doc """
  Sincroniza pelo id da conexão (usado pelo worker) e, de carona, garante o webhook
  do usuário. Conexão já removida é ignorada.
  """
  def sync(connection_id) do
    case Connection |> Repo.get(connection_id) |> Repo.preload(:user) do
      nil ->
        {:ok, :removed}

      connection ->
        ensure_webhook_quietly(connection.user)
        sync_connection(connection)
    end
  end

  # O webhook só acelera a chegada dos dados; se a Pluggy falhar aqui, a
  # sincronização segue e a próxima tenta registrar de novo.
  defp ensure_webhook_quietly(user) do
    case ensure_webhook(Scope.for_user(user)) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Open Finance: webhook não garantido: #{error_message(reason)}")
    end
  end

  @doc """
  Relê o Item, as contas e as transações na Pluggy e regrava o espelho local:
  o que sumiu na Pluggy (ex.: transações de cartão reapresentadas com outro id
  no fechamento da fatura) também some aqui. Só apaga depois de buscar tudo.
  """
  def sync_connection(%Connection{} = connection) do
    connection = Repo.preload(connection, :user)
    now = DateTime.utc_now(:second)

    result =
      with {:ok, credentials} <- fetch_credentials(connection.user),
           {:ok, item} <- Pluggy.get_item(credentials, connection.item_id),
           {:ok, accounts} <- Pluggy.list_accounts(credentials, connection.item_id),
           {:ok, transactions} <- fetch_transactions(credentials, accounts) do
        store_snapshot(connection, item, accounts, transactions, now)
      end

    result =
      case result do
        {:ok, connection} ->
          {:ok, connection}

        {:error, reason} = error ->
          connection
          |> Connection.sync_changeset(%{sync_error: error_message(reason)})
          |> Repo.update!()

          error
      end

    Phoenix.PubSub.broadcast(
      Grana.PubSub,
      topic(connection.user_id),
      {:open_finance_synced, connection.id}
    )

    result
  end

  defp fetch_transactions(credentials, accounts) do
    Enum.reduce_while(accounts, {:ok, %{}}, fn account, {:ok, acc} ->
      case Pluggy.list_transactions(credentials, account["id"]) do
        {:ok, transactions} -> {:cont, {:ok, Map.put(acc, account["id"], transactions)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp store_snapshot(connection, item, accounts, transactions_by_account, now) do
    Repo.transaction(fn ->
      connection =
        connection
        |> Connection.item_changeset(item_attrs(item))
        |> Connection.sync_changeset(%{last_synced_at: now, sync_error: nil})
        |> Repo.update!()

      upsert(
        Account,
        Enum.map(accounts, &account_row(&1, connection, now))
      )

      account_ids =
        from(a in Account, where: a.connection_id == ^connection.id, select: {a.pluggy_id, a.id})
        |> Repo.all()
        |> Map.new()

      transaction_rows =
        for {pluggy_account_id, transactions} <- transactions_by_account,
            transaction <- transactions do
          transaction_row(
            transaction,
            Map.fetch!(account_ids, pluggy_account_id),
            connection,
            now
          )
        end

      upsert(Transaction, transaction_rows)

      account_query = from(a in Account, where: a.connection_id == ^connection.id)

      from(t in Transaction,
        where: t.account_id in subquery(select(account_query, [a], a.id)) and t.synced_at < ^now
      )
      |> Repo.delete_all()

      account_query |> where([a], a.synced_at < ^now) |> Repo.delete_all()

      connection
    end)
  end

  defp upsert(schema, rows) do
    rows
    |> Enum.chunk_every(@insert_chunk_size)
    |> Enum.each(fn chunk ->
      Repo.insert_all(schema, chunk,
        on_conflict: {:replace_all_except, [:id, :pluggy_id, :inserted_at]},
        conflict_target: :pluggy_id
      )
    end)
  end

  defp item_attrs(item) do
    connector = item["connector"] || %{}

    %{
      connector_id: connector["id"],
      connector_name: connector["name"],
      connector_image_url: connector["imageUrl"],
      status: item["status"],
      execution_status: item["executionStatus"],
      error_message: get_in(item, ["error", "message"]),
      pluggy_updated_at: item["lastUpdatedAt"],
      consent_expires_at: item["consentExpiresAt"]
    }
  end

  defp account_row(account, connection, now) do
    bank = account["bankData"] || %{}
    credit = account["creditData"] || %{}

    %{
      pluggy_id: account["id"],
      type: account["type"],
      subtype: account["subtype"],
      name: account["name"],
      marketing_name: account["marketingName"],
      number: account["number"],
      owner: account["owner"],
      currency_code: account["currencyCode"],
      balance: to_decimal(account["balance"]),
      transfer_number: bank["transferNumber"],
      automatically_invested_balance: to_decimal(bank["automaticallyInvestedBalance"]),
      credit_limit: to_decimal(credit["creditLimit"]),
      available_credit_limit: to_decimal(credit["availableCreditLimit"]),
      minimum_payment: to_decimal(credit["minimumPayment"]),
      balance_close_date: to_date(credit["balanceCloseDate"]),
      balance_due_date: to_date(credit["balanceDueDate"]),
      brand: credit["brand"],
      level: credit["level"],
      synced_at: now,
      connection_id: connection.id,
      user_id: connection.user_id,
      inserted_at: now,
      updated_at: now
    }
  end

  defp transaction_row(transaction, account_id, connection, now) do
    card = transaction["creditCardMetadata"] || %{}

    %{
      pluggy_id: transaction["id"],
      date: local_date(transaction["date"]),
      description: transaction["description"],
      amount: to_decimal(transaction["amount"]),
      currency_code: transaction["currencyCode"],
      type: transaction["type"],
      status: transaction["status"],
      category: transaction["category"],
      operation_type: transaction["operationType"],
      installment_number: to_integer(card["installmentNumber"]),
      total_installments: to_integer(card["totalInstallments"]),
      bill_id: card["billId"],
      provider_id: transaction["providerId"],
      synced_at: now,
      account_id: account_id,
      user_id: connection.user_id,
      inserted_at: now,
      updated_at: now
    }
  end

  defp to_decimal(nil), do: nil
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)

  defp to_decimal(value) when is_float(value),
    do: value |> Decimal.from_float() |> Decimal.round(2)

  defp to_integer(value) when is_float(value), do: trunc(value)
  defp to_integer(value), do: value

  defp to_date(nil), do: nil
  defp to_date(value), do: value |> String.slice(0, 10) |> Date.from_iso8601!()

  # 2026-10-05T03:00:00.000Z é 05/10 no horário de Brasília (e não 04/10).
  defp local_date(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        datetime |> DateTime.add(@brt_offset_hours, :hour) |> DateTime.to_date()

      {:error, _} ->
        to_date(value)
    end
  end

  ## Leitura dos dados espelhados

  @doc "Totais das contas em reais: saldo das contas, fatura atual e limite disponível dos cartões."
  def totals(accounts) do
    brl = Enum.filter(accounts, &(&1.currency_code in [nil, "BRL"]))
    {cards, banks} = Enum.split_with(brl, &Account.credit_card?/1)

    %{
      bank: sum(banks, :balance),
      bank_count: length(banks),
      card_used: sum(cards, :balance),
      card_available: sum(cards, :available_credit_limit),
      card_count: length(cards)
    }
  end

  defp sum(accounts, field) do
    accounts
    |> Enum.map(&Map.fetch!(&1, field))
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
  end

  def list_accounts(%Scope{user: user}) do
    from(a in Account,
      join: c in assoc(a, :connection),
      where: a.user_id == ^user.id,
      order_by: [asc: c.inserted_at, asc: c.id, asc: a.type, asc: a.name],
      preload: [connection: c]
    )
    |> Repo.all()
  end

  def list_transactions(%Scope{user: user}, account_id, opts \\ []) do
    from(t in Transaction,
      where: t.user_id == ^user.id and t.account_id == ^account_id,
      order_by: [desc: t.date, asc: t.id],
      limit: ^Keyword.get(opts, :limit, 50),
      offset: ^Keyword.get(opts, :offset, 0)
    )
    |> Repo.all()
  end

  def count_transactions(%Scope{user: user}, account_id) do
    Repo.aggregate(
      from(t in Transaction, where: t.user_id == ^user.id and t.account_id == ^account_id),
      :count
    )
  end

  ## Webhooks

  @doc "Dono do segredo de webhook recebido (cada usuário registra o seu), ou `nil`."
  def webhook_user(secret) when is_binary(secret) do
    from(u in User, where: not is_nil(u.pluggy_webhook_secret))
    |> Repo.all()
    |> Enum.find(&Plug.Crypto.secure_compare(&1.pluggy_webhook_secret, secret))
  end

  @doc """
  Trata um webhook da Pluggy, já autenticado como sendo do usuário do `scope`. O
  payload é só um aviso: nunca usamos seus dados, apenas enfileiramos uma
  sincronização que relê tudo na API com as credenciais do usuário.
  """
  def handle_webhook(%Scope{user: user}, %{"itemId" => item_id} = payload)
      when is_binary(item_id) do
    case Repo.get_by(Connection, item_id: item_id, user_id: user.id) do
      %Connection{} = connection -> enqueue_sync(connection)
      nil -> maybe_enqueue_registration(user, payload)
    end
  end

  def handle_webhook(_scope, _payload), do: :ignored

  # Item criado pelo widget do Grana (clientUserId = id do usuário) cujo onSuccess
  # não chegou ao servidor — ex.: a aba foi fechada antes do fim da conexão.
  defp maybe_enqueue_registration(
         user,
         %{"event" => "item/created", "itemId" => item_id} = payload
       ) do
    if payload["clientUserId"] == to_string(user.id) do
      %{"user_id" => user.id, "item_id" => item_id}
      |> OpenFinanceSyncWorker.new()
      |> Oban.insert()
    else
      :ignored
    end
  end

  defp maybe_enqueue_registration(_user, _payload), do: :ignored

  @doc """
  Garante que o webhook do Grana (PLUGGY_WEBHOOK_URL + header com o segredo do
  usuário) está registrado na Pluggy, registrando-o se faltar. O dashboard da
  Pluggy não permite headers customizados, por isso o registro é feito pela API.
  Sem PLUGGY_WEBHOOK_URL não faz nada.
  """
  def ensure_webhook(%Scope{user: user} = scope) do
    with url when is_binary(url) <- webhook_url(),
         {:ok, credentials} <- fetch_credentials(scope),
         {:ok, webhooks} <- Pluggy.list_webhooks(credentials) do
      if Enum.any?(webhooks, &grana_webhook?(&1, url, user.pluggy_webhook_secret)),
        do: :ok,
        else: register_webhook(user, credentials, url, webhooks)
    else
      nil -> :ok
      {:error, _} = error -> error
    end
  end

  defp grana_webhook?(_webhook, _url, nil), do: false

  defp grana_webhook?(webhook, url, secret) do
    provided = (webhook["headers"] || %{})[@webhook_secret_header]
    webhook["url"] == url and is_binary(provided) and Plug.Crypto.secure_compare(provided, secret)
  end

  # Cada registro gera um segredo novo, substitui webhooks antigos na mesma URL e
  # grava o segredo cifrado.
  defp register_webhook(user, credentials, url, webhooks) do
    secret = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    with :ok <- delete_webhooks(credentials, Enum.filter(webhooks, &(&1["url"] == url))),
         {:ok, _user} <-
           user |> Ecto.Changeset.change(pluggy_webhook_secret: secret) |> Repo.update(),
         {:ok, _webhook} <-
           Pluggy.create_webhook(credentials, url, "all", %{@webhook_secret_header => secret}) do
      :ok
    end
  end

  defp delete_webhooks(credentials, webhooks) do
    Enum.reduce_while(webhooks, :ok, fn webhook, :ok ->
      case Pluggy.delete_webhook(credentials, webhook["id"]) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  ## Mensagens

  @doc "Mensagem amigável para os erros da integração."
  def error_message(:not_configured),
    do:
      "Integração não configurada: informe o Client ID e o Client Secret da Pluggy em Configurações."

  def error_message(:invalid_credentials),
    do: "A Pluggy recusou o CLIENT_ID/CLIENT_SECRET. Confira as credenciais no dashboard."

  def error_message(:unauthorized), do: "A Pluggy recusou a autenticação da aplicação."

  def error_message(:not_found),
    do: "Item não encontrado na Pluggy — foi removido ou pertence a outra aplicação."

  def error_message(:invalid_item_id),
    do: "itemId inválido. Copie o id (UUID) do item na página Demo do dashboard da Pluggy."

  def error_message(:already_connected), do: "Essa conexão já está vinculada ao Grana."

  def error_message(:rate_limited),
    do: "Limite de requisições da Pluggy atingido. Tente de novo em um minuto."

  def error_message({:http_error, status, nil}), do: "Erro na API da Pluggy (HTTP #{status})."

  def error_message({:http_error, status, message}),
    do: "Erro na API da Pluggy (HTTP #{status}): #{message}"

  def error_message({:transport, message}), do: "Falha de conexão com a Pluggy: #{message}"
end
