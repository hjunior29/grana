defmodule Grana.Demo do
  @moduledoc """
  Demonstração pública (`GRANA_DEMO=true`): a landing e uma conta compartilhada com
  dados fictícios (`Grana.Demo.Dataset`).

  O boot apaga a instância e recria a conta (`reset!/0`), então o que os visitantes
  mudam dura até o próximo reinício. Uma instância com dono de verdade se recusa a subir
  nesse modo, para que ligá-lo por engano não apague dados reais.

  Ficam desligados, cada um com o motivo em `reason/1` e bloqueado no servidor por
  `allow/1`, os recursos que dependem de chaves (IA, SMTP, Open Finance) e os que mexem
  na instância ou na conta compartilhada (backup, restauração, "apagar tudo", troca de
  email e senha, envio de arquivos, painéis técnicos). O login é o de sempre, com o
  acesso de `credentials/0` à vista.
  """

  import Ecto.Query

  alias Grana.Accounts
  alias Grana.Accounts.User
  alias Grana.Repo

  @email "demo@grana.local"
  @password "demonstracao"
  @name "Marina Alves Duarte"
  @cpf "111.444.777-35"

  @preference_fields [:theme, :visual_style, :hide_values, :hide_names, :analysis_open]

  @reasons %{
    ai:
      "Na demonstração a IA fica desligada: ela usaria uma chave de API de verdade. " <>
        "A análise do Painel e a conversa do Chat já vêm escritas com a conta.",
    smtp: "Na demonstração o email fica desligado: ele usaria uma conta SMTP de verdade.",
    open_finance:
      "Na demonstração o Open Finance fica desligado: ele usaria credenciais da Pluggy " <>
        "e acessaria bancos de verdade.",
    account:
      "A conta da demonstração é compartilhada entre os visitantes: email, senha e titular " <>
        "não podem ser trocados.",
    backup:
      "Na demonstração backup, restauração e \"apagar tudo\" ficam desligados: a conta é " <>
        "compartilhada e volta ao original quando o servidor reinicia.",
    upload:
      "Como esta é uma demonstração, não há importação de fato: os extratos do Histórico " <>
        "já vêm com a conta. Na sua instância, é aqui que você envia os CSVs e PDFs do banco."
  }

  @doc "Se a instância é a demonstração pública (`GRANA_DEMO=true`)."
  def enabled?, do: Application.get_env(:grana, :demo, false)

  @doc "Por que um recurso fica desligado na demonstração."
  def reason(feature), do: Map.fetch!(@reasons, feature)

  @doc "`:ok` fora da demonstração; nela, `{:error, :demo}` para os recursos de `reason/1`."
  def allow(feature) when is_map_key(@reasons, feature) do
    if enabled?(), do: {:error, :demo}, else: :ok
  end

  @doc "A conta da demonstração, se existir."
  def user, do: Repo.one(from u in User, where: u.demo, limit: 1)

  @doc """
  Apaga a instância e recria a conta da demonstração com os dados de base. Roda no boot
  (`Grana.Demo.Boot`). Se houver um usuário que não é da demonstração, levanta em vez de
  apagar: o modo foi ligado numa instância de verdade.
  """
  def reset!(today \\ Grana.LocalTime.today()) do
    if Repo.exists?(from u in User, where: not u.demo) do
      raise """
      GRANA_DEMO=true numa instância que tem dono. O modo demonstração apaga todos os \
      dados a cada boot, então o Grana não sobe assim. Desligue GRANA_DEMO ou use um \
      DATA_DIR vazio para a demonstração.\
      """
    end

    :ok = Grana.Backup.wipe()
    user = create_user!()
    Accounts.invalidate_setup_cache()
    Grana.Demo.Dataset.seed!(user, today)
    user
  end

  defp create_user! do
    %User{}
    |> User.owner_changeset(%{
      email: @email,
      name: @name,
      password: @password,
      password_confirmation: @password
    })
    |> Ecto.Changeset.put_change(:demo, true)
    |> Ecto.Changeset.put_change(:onboarded_at, DateTime.utc_now(:second))
    |> Repo.insert!()
    |> User.identity_changeset(%{name: @name, cpf: @cpf})
    |> Repo.update!()
  end

  @doc "Email e senha da conta da demonstração, mostrados na tela de login."
  def credentials, do: %{email: @email, password: @password}

  @doc "Nome do titular da conta da demonstração, o mesmo dos extratos fictícios."
  def holder_name, do: @name

  @doc "CPF fictício do titular, o mesmo dos extratos fictícios."
  def holder_cpf, do: @cpf

  # Preferências por visitante: a conta é uma só, então tema, privacidade e a análise
  # aberta ficam na sessão (chave derivada do token), não no usuário, e só as outras
  # abas do mesmo visitante recebem a mudança.

  @doc "Chave da sessão de um visitante, derivada do token de sessão."
  def session_key(token) when is_binary(token), do: :crypto.hash(:sha256, token)

  @doc "Aplica ao usuário da demonstração as preferências guardadas na sessão do visitante."
  def with_session_preferences(%User{demo: true} = user, token) when is_binary(token) do
    case :ets.lookup(Grana.Demo.Sessions, session_key(token)) do
      [{_key, fields}] -> struct(user, fields)
      [] -> user
    end
  end

  def with_session_preferences(user, _token), do: user

  @doc "Grava as preferências na sessão do visitante e avisa as outras abas dele."
  def put_session_preferences(key, %User{demo: true} = user, attrs) do
    with {:ok, user} <-
           user |> User.preferences_changeset(attrs) |> Ecto.Changeset.apply_action(:update) do
      fields = Map.take(user, @preference_fields)
      :ets.insert(Grana.Demo.Sessions, {key, fields})
      Phoenix.PubSub.broadcast(Grana.PubSub, session_topic(key), {:preferences_updated, fields})
      {:ok, user}
    end
  end

  @doc "Assina as mudanças de preferência das outras abas do mesmo visitante."
  def subscribe_session(key), do: Phoenix.PubSub.subscribe(Grana.PubSub, session_topic(key))

  defp session_topic(key), do: "demo_preferences:#{Base.url_encode64(key)}"
end
