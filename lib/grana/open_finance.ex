defmodule Grana.OpenFinance do
  @moduledoc """
  Integração Open Finance via Pluggy, pensada para uso pessoal: o usuário autoriza
  os bancos no Meu Pluggy e conecta o Grana a eles pelo conector MeuPluggy.

  As credenciais da aplicação Pluggy vêm do ambiente (`.env`) ou, se não houver
  nada lá, das salvas pela tela de cada usuário (secret cifrado).

  Dois papéis, sem nunca somar com os uploads:

    * **Estado atual**: o retrato das contas (saldos, faturas, limites,
      vencimentos), relido no máximo uma vez por hora.
    * **Fonte para os períodos sem upload**: o que nenhum extrato/fatura importado
      cobre entra como extratos/faturas virtuais do mesmo banco
      (`source = "open_finance"`), e todo o sistema passa a enxergá-lo. Quando um
      upload passa a cobrir o período, ele vence e o Open Finance sai.
  """

  import Ecto.Query

  require Logger

  alias Grana.Accounts.{Scope, User}
  alias Grana.Banking
  alias Grana.Banking.{BankStatement, KeywordCategorizer}
  alias Grana.Banking.Parsers.InstallmentParser
  alias Grana.Banking.Transaction, as: BankingTransaction
  alias Grana.OpenFinance.{Account, Connection, Pluggy}
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
        result when result in [:ok, {:error, :not_found}] ->
          # O cascade leva junto contas, extratos/faturas virtuais e suas transações.
          with {:ok, _} = deleted <- Repo.delete(connection) do
            Banking.detect_internal_transfers(user_id)
            deleted
          end

        {:error, _} = error ->
          error
      end
    end
  end

  ## Sincronização

  # O Meu Pluggy atualiza os dados uma vez por dia: reler a Pluggy mais de uma vez
  # por hora só gastaria chamadas. As telas pedem releitura e o TTL decide.
  @refresh_ttl_seconds 60 * 60

  # Janela (dias) para reconhecer, na fronteira de um upload, a mesma transação
  # vinda do Open Finance com data um pouco diferente.
  @boundary_days 3

  def enqueue_sync(%Connection{id: id}) do
    %{"connection_id" => id} |> OpenFinanceSyncWorker.new() |> Oban.insert()
  end

  def enqueue_user_syncs(%Scope{} = scope) do
    scope
    |> list_connections()
    |> Enum.each(&enqueue_sync/1)
  end

  @doc """
  Agenda a releitura das conexões do usuário lidas há mais de 1h. Chamado ao
  abrir as telas: na prática, um cache de 1h dos dados da Pluggy.
  """
  def refresh_if_stale(%Scope{user: user}) do
    cutoff = DateTime.add(DateTime.utc_now(:second), -@refresh_ttl_seconds)

    from(c in Connection,
      where:
        c.user_id == ^user.id and
          (is_nil(c.last_synced_at) or c.last_synced_at < ^cutoff)
    )
    |> Repo.all()
    |> Enum.each(&enqueue_sync/1)
  end

  @doc """
  Uploads do usuário mudaram (importação ou exclusão): o que o Open Finance
  cobre muda junto, então as conexões são relidas já, sem esperar o TTL.
  """
  def uploads_changed(user_id) do
    from(c in Connection, where: c.user_id == ^user_id)
    |> Repo.all()
    |> Enum.each(&enqueue_sync/1)
  end

  @doc """
  Um upload passou a cobrir `inicio..fim` de um banco/tipo: as transações do Open
  Finance desse período saem antes de o upload entrar (o upload sempre vence).
  """
  def release_period(user_id, bank, statement_type, period_start, period_end) do
    statement_ids =
      from(s in BankStatement,
        where:
          s.user_id == ^user_id and s.source == "open_finance" and s.bank == ^bank and
            s.statement_type == ^statement_type,
        select: s.id
      )

    from(t in BankingTransaction,
      where:
        t.bank_statement_id in subquery(statement_ids) and t.date >= ^period_start and
          t.date <= ^period_end
    )
    |> Repo.delete_all()
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
  Relê a conexão na Pluggy: guarda o retrato atual das contas (saldos, limites,
  vencimentos) e preenche, como uma fonte a mais do banco, os períodos que
  nenhum upload cobre. O que um upload cobre fica só com o upload.
  """
  def sync_connection(%Connection{} = connection) do
    connection = Repo.preload(connection, :user)
    now = DateTime.utc_now(:second)

    result =
      with {:ok, credentials} <- fetch_credentials(connection.user),
           {:ok, item} <- Pluggy.get_item(credentials, connection.item_id),
           {:ok, accounts} <- Pluggy.list_accounts(credentials, connection.item_id),
           {:ok, transactions} <- fetch_transactions(credentials, accounts),
           holder_type = holder_type(connection, credentials),
           {:ok, connection} <-
             store(connection, item, accounts, transactions, now, holder_type) do
        Banking.detect_internal_transfers(connection.user_id)
        {:ok, connection}
      end

    result =
      case result do
        {:ok, connection} ->
          {:ok, connection}

        {:error, reason} = error ->
          # Também conta como leitura: a próxima tentativa respeita o mesmo TTL.
          connection
          |> Connection.sync_changeset(%{sync_error: error_message(reason), last_synced_at: now})
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

  defp store(connection, item, accounts, transactions_by_account, now, holder_type) do
    attrs =
      item
      |> item_attrs()
      |> Map.merge(%{bank: infer_bank(accounts, item), holder_type: holder_type})

    Repo.transaction(fn ->
      connection =
        connection
        |> Connection.item_changeset(attrs)
        |> Connection.sync_changeset(%{last_synced_at: now, sync_error: nil})
        |> Repo.update!()

      upsert_accounts(Enum.map(accounts, &account_row(&1, connection, now)))

      from(a in Account, where: a.connection_id == ^connection.id and a.synced_at < ^now)
      |> Repo.delete_all()

      local_accounts =
        from(a in Account, where: a.connection_id == ^connection.id)
        |> Repo.all()
        |> Map.new(&{&1.pluggy_id, &1})

      fill_gaps(connection, accounts, transactions_by_account, local_accounts, now)

      connection
    end)
  end

  # PF/PJ não muda: lido uma vez. Sem identidade disponível, fica para a próxima.
  defp holder_type(%Connection{holder_type: type}, _credentials) when is_binary(type), do: type

  defp holder_type(connection, credentials) do
    case Pluggy.get_identity(credentials, connection.item_id) do
      {:ok, %{"documentType" => "CNPJ"}} -> "PJ"
      # Conta empresarial ligada ao CPF (ex.: MEI): vem com CPF, mas é de empresa.
      {:ok, %{"companyName" => name}} when is_binary(name) and name != "" -> "PJ"
      {:ok, %{"documentType" => "CPF"}} -> "PF"
      _ -> nil
    end
  end

  defp upsert_accounts(rows) do
    Repo.insert_all(Account, rows,
      on_conflict: {:replace_all_except, [:id, :pluggy_id, :inserted_at]},
      conflict_target: :pluggy_id
    )
  end

  # Pelo Meu Pluggy o conector é sempre "MeuPluggy": o banco vem do nome das
  # contas ("Banco Bradesco", "Nu Pagamentos S.A."), no vocabulário dos uploads.
  defp infer_bank(accounts, item) do
    name =
      Enum.find_value(accounts, fn a -> a["type"] == "BANK" && a["name"] end) ||
        get_in(item, ["connector", "name"]) || ""

    normalized =
      name
      |> String.downcase()
      |> :unicode.characters_to_nfd_binary()
      |> String.replace(~r/[^a-z0-9 ]/u, "")

    cond do
      normalized =~ "nubank" or normalized =~ "nu pagamentos" ->
        "nubank"

      normalized =~ "bradesco" ->
        "bradesco"

      true ->
        normalized
        |> String.replace(~r/\b(banco|bank|sa|instituicao|de|pagamento)\b/u, "")
        |> String.split()
        |> List.first() || "open_finance"
    end
  end

  # Cada conta vira extratos/faturas virtuais com as transações que caem fora dos
  # períodos de upload do mesmo banco e tipo. Tudo que não couber mais (o upload
  # passou a cobrir, ou a Pluggy reapresentou com outro id) é removido.
  defp fill_gaps(connection, accounts, transactions_by_account, local_accounts, now) do
    periods = Banking.upload_periods(connection.user_id, connection.bank)
    categorize = categorizer(connection.user_id)

    kept_statement_ids =
      Enum.flat_map(accounts, fn account ->
        local = Map.fetch!(local_accounts, account["id"])
        type = if account["type"] == "CREDIT", do: "fatura", else: "extrato"

        transactions_by_account
        |> Map.get(account["id"], [])
        |> Enum.map(&parse_transaction/1)
        |> reject_covered(connection, type, periods)
        |> Enum.group_by(&statement_key(&1, type))
        |> Enum.map(fn {key, rows} ->
          store_statement(connection, local, type, key, rows, categorize, now)
        end)
      end)

    from(s in BankStatement,
      where:
        s.user_id == ^connection.user_id and s.source == "open_finance" and
          s.open_finance_account_id in subquery(
            from(a in Account, where: a.connection_id == ^connection.id, select: a.id)
          ) and s.id not in ^kept_statement_ids
    )
    |> Repo.delete_all()
  end

  defp parse_transaction(transaction) do
    card = transaction["creditCardMetadata"] || %{}
    amount = transaction["amount"] |> to_decimal() |> Decimal.abs()
    credit? = transaction["type"] == "CREDIT"
    total = to_integer(card["totalInstallments"])

    %{
      external_id: transaction["id"],
      date: local_date(transaction["date"]),
      description: transaction["description"],
      original_description: transaction["descriptionRaw"],
      amount: if(credit?, do: amount, else: Decimal.negate(amount)),
      type: if(credit?, do: "credit", else: "debit"),
      installment_current: to_integer(card["installmentNumber"]),
      installment_total: total,
      installment_group_id:
        InstallmentParser.generate_group_id(transaction["description"], total),
      bill_id: card["billId"],
      pluggy_category_id: transaction["categoryId"]
    }
  end

  # Dentro de um período de upload, vale o upload. Fora dele, ainda descarta o
  # que bate (mesmo valor, até 3 dias de diferença) com uma transação de upload:
  # é a mesma compra vista com a data de lançamento da fatura/extrato.
  defp reject_covered([], _connection, _type, _periods), do: []

  defp reject_covered(rows, connection, type, periods) do
    type_periods = for {^type, first, last} <- periods, do: {first, last}
    {min_date, max_date} = rows |> Enum.map(& &1.date) |> Enum.min_max_by(& &1, Date)

    uploaded =
      connection.user_id
      |> Banking.upload_amounts(
        connection.bank,
        type,
        Date.add(min_date, -@boundary_days),
        Date.add(max_date, @boundary_days)
      )
      |> Enum.group_by(fn {_date, amount} -> Decimal.abs(amount) end, &elem(&1, 0))

    {kept, _uploaded} =
      rows
      |> Enum.sort_by(& &1.date, Date)
      |> Enum.reduce({[], uploaded}, fn row, {kept, uploaded} ->
        cond do
          Enum.any?(type_periods, fn {first, last} ->
            Date.compare(row.date, first) != :lt and Date.compare(row.date, last) != :gt
          end) ->
            {kept, uploaded}

          match = find_upload_match(uploaded, row) ->
            {kept, match}

          true ->
            {[row | kept], uploaded}
        end
      end)

    kept
  end

  # Devolve as transações de upload sem a que casou com `row`, ou nil se nenhuma casar.
  defp find_upload_match(uploaded, row) do
    key = Decimal.abs(row.amount)
    dates = Map.get(uploaded, key, [])

    case Enum.find_index(dates, &(abs(Date.diff(&1, row.date)) <= @boundary_days)) do
      nil -> nil
      index -> Map.put(uploaded, key, List.delete_at(dates, index))
    end
  end

  # Extrato: um por conta. Fatura: uma por fatura da Pluggy (id da fatura), para
  # o Grana atribuir o mês da fatura como faz com os uploads.
  defp statement_key(_row, "extrato"), do: "extrato"
  defp statement_key(row, "fatura"), do: row.bill_id || "aberta"

  defp store_statement(connection, account, type, key, rows, categorize, now) do
    {period_start, period_end} = rows |> Enum.map(& &1.date) |> Enum.min_max_by(& &1, Date)
    external_id = "#{account.pluggy_id}:#{key}"

    attrs = %{
      bank: connection.bank,
      filename: "Open Finance · #{account_label(account)} · #{key}",
      statement_type: type,
      status: "completed",
      period_start: period_start,
      period_end: period_end,
      total_transactions: length(rows)
    }

    statement =
      case Repo.get_by(BankStatement,
             open_finance_account_id: account.id,
             external_id: external_id
           ) do
        nil ->
          %BankStatement{
            source: "open_finance",
            external_id: external_id,
            open_finance_account_id: account.id,
            user_id: connection.user_id
          }

        statement ->
          statement
      end
      |> Ecto.Changeset.change(attrs)
      |> Repo.insert_or_update!()

    upsert_transactions(rows, statement, connection.user_id, categorize, now)

    external_ids = Enum.map(rows, & &1.external_id)

    from(t in BankingTransaction,
      where: t.bank_statement_id == ^statement.id and t.external_id not in ^external_ids
    )
    |> Repo.delete_all()

    statement.id
  end

  defp account_label(account) do
    name = account.marketing_name || account.name || "Conta"
    suffix = account.number && String.slice(account.number, -4, 4)
    if suffix, do: "#{name} ••#{suffix}", else: name
  end

  # A categoria de uma transação que já existe não é tocada: pode ter sido
  # ajustada à mão. Só as novas recebem categoria.
  defp upsert_transactions(rows, statement, user_id, categorize, now) do
    rows
    |> Enum.map(fn row ->
      row
      |> Map.drop([:bill_id, :pluggy_category_id])
      |> Map.merge(%{
        bank_statement_id: statement.id,
        user_id: user_id,
        category_id: categorize.(row),
        identifier: nil,
        is_internal_transfer: false,
        inserted_at: now,
        updated_at: now
      })
    end)
    |> Enum.chunk_every(@insert_chunk_size)
    |> Enum.each(fn chunk ->
      Repo.insert_all(BankingTransaction, chunk,
        on_conflict:
          {:replace,
           [
             :date,
             :description,
             :original_description,
             :amount,
             :type,
             :installment_current,
             :installment_total,
             :installment_group_id,
             :bank_statement_id,
             :updated_at
           ]},
        conflict_target: :external_id
      )
    end)
  end

  # Mesma ordem dos uploads (regras do usuário e palavras-chave do Grana); a
  # categoria da Pluggy entra só como reserva, antes de "Sem Categoria".
  defp categorizer(user_id) do
    categories = Banking.ensure_default_categories(user_id)
    by_name = Map.new(categories, &{&1.name, &1.id})
    uncategorized_id = by_name["Sem Categoria"]
    rules = Banking.list_category_rules(user_id)

    fn row ->
      category_id = Banking.categorize_transaction_with_rules(row.description, rules, user_id)

      if category_id in [nil, uncategorized_id] do
        name =
          KeywordCategorizer.categorize(row.description) ||
            pluggy_category_name(row.pluggy_category_id)

        by_name[name] || uncategorized_id
      else
        category_id
      end
    end
  end

  # Grupos da árvore de categorias da Pluggy (dois primeiros dígitos do id).
  defp pluggy_category_name("0101" <> _), do: "Salário"
  defp pluggy_category_name("0702" <> _), do: "Educação"
  defp pluggy_category_name("0703" <> _), do: "Saúde"
  defp pluggy_category_name("0704" <> _), do: "Lazer"
  defp pluggy_category_name("0701" <> _), do: "Moradia"
  defp pluggy_category_name("01" <> _), do: "Rendimentos"
  defp pluggy_category_name("03" <> _), do: "Investimentos"
  defp pluggy_category_name("04" <> _), do: "Transferências"
  defp pluggy_category_name("05" <> _), do: "Transferências"
  defp pluggy_category_name("08" <> _), do: "Compras"
  defp pluggy_category_name("09" <> _), do: "Assinaturas"
  defp pluggy_category_name("10" <> _), do: "Alimentação"
  defp pluggy_category_name("11" <> _), do: "Alimentação"
  defp pluggy_category_name("12" <> _), do: "Lazer"
  defp pluggy_category_name("14" <> _), do: "Lazer"
  defp pluggy_category_name("15" <> _), do: "Impostos e Taxas"
  defp pluggy_category_name("16" <> _), do: "Impostos e Taxas"
  defp pluggy_category_name("17" <> _), do: "Moradia"
  defp pluggy_category_name("18" <> _), do: "Saúde"
  defp pluggy_category_name("19" <> _), do: "Transporte"
  defp pluggy_category_name("21" <> _), do: "Lazer"

  defp pluggy_category_name(id) when is_binary(id) and id not in ["", "99999999"],
    do: "Pagamentos"

  defp pluggy_category_name(_), do: nil

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

  ## Estado atual (retrato das contas)

  def list_accounts(%Scope{user: user}) do
    from(a in Account,
      join: c in assoc(a, :connection),
      where: a.user_id == ^user.id,
      order_by: [asc: c.inserted_at, asc: c.id, asc: a.type, asc: a.name],
      preload: [connection: c]
    )
    |> Repo.all()
  end

  @doc "Totais das contas em reais: saldo das contas, fatura atual e limite disponível dos cartões."
  def totals(accounts) do
    brl = Enum.filter(accounts, &(&1.currency_code in [nil, "BRL"]))
    {cards, banks} = Enum.split_with(brl, &Account.credit_card?/1)

    %{
      bank: sum(banks, :balance),
      bank_count: length(banks),
      card_used: sum(cards, :balance),
      card_available: sum(cards, :available_credit_limit),
      card_limit: sum(cards, :credit_limit),
      card_count: length(cards)
    }
  end

  defp sum(accounts, field) do
    accounts
    |> Enum.map(&Map.fetch!(&1, field))
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
  end

  @doc """
  Calendário dos últimos 12 meses no formato do calendário de uploads (linhas por
  ano, 12 meses cada). Por mês: os tipos importados (`upload_types`) e o que veio
  do Open Finance por falta de upload (`open_finance`, ex.: `[{"bradesco", "extrato"}]`).
  """
  def coverage_calendar(%Scope{user: user}) do
    today = Date.utc_today()
    window_start = today |> Date.beginning_of_month() |> Date.shift(month: -11)
    uploads = Banking.coverage_by_statement_type(user.id)
    open_finance = open_finance_months(user.id)

    for year <- window_start.year..today.year do
      cells =
        for month <- 1..12 do
          key = {year, month}

          %{
            year: year,
            month: month,
            upload_types: for(type <- ["extrato", "fatura"], key in uploads[type], do: type),
            open_finance: Map.get(open_finance, key, []),
            future?: key > {today.year, today.month}
          }
        end

      %{year: year, cells: cells}
    end
  end

  # Meses (e de qual banco/tipo) com transações vindas do Open Finance.
  defp open_finance_months(user_id) do
    from(t in BankingTransaction,
      join: s in assoc(t, :bank_statement),
      where: t.user_id == ^user_id and s.source == "open_finance",
      distinct: true,
      select: {s.bank, s.statement_type, t.date}
    )
    |> Repo.all()
    |> Enum.group_by(fn {_bank, _type, date} -> {date.year, date.month} end, fn {bank, type, _} ->
      {bank, type}
    end)
    |> Map.new(fn {month, sources} -> {month, sources |> Enum.uniq() |> Enum.sort()} end)
  end

  @doc "Momento da leitura mais antiga entre as conexões do usuário (idade do retrato)."
  def last_refreshed_at(%Scope{user: user}) do
    Repo.one(from(c in Connection, where: c.user_id == ^user.id, select: min(c.last_synced_at)))
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
