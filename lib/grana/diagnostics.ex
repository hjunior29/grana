defmodule Grana.Diagnostics do
  @moduledoc "Resumo técnico da instância para a seção Diagnóstico de Configurações."

  import Ecto.Query, only: [from: 2]

  alias Grana.{Accounts, DataDir, OpenFinance, Repo}
  alias Grana.Accounts.Scope

  def summary(%Accounts.User{} = user) do
    %{
      version: to_string(Application.spec(:grana, :vsn)),
      data_dir: DataDir.path(),
      database_size: database_size(),
      public_url: Accounts.public_base_url(user),
      uptime_seconds: div(elem(:erlang.statistics(:wall_clock), 0), 1000),
      runtime: %{
        elixir: System.version(),
        otp: to_string(:erlang.system_info(:otp_release)),
        sqlite: sqlite_version()
      },
      data: data_counts(user),
      jobs: job_counts(),
      unresolved_errors: unresolved_errors(),
      ai_model: user.ai_model,
      open_finance_connections: connection_count(user),
      credentials: [
        {"Chave do Gemini", ai_source(user)},
        {"Pluggy (Open Finance)", OpenFinance.credentials_source(Scope.for_user(user))},
        {"Email (SMTP)", Accounts.smtp_source()}
      ]
    }
  end

  defp sqlite_version do
    %{rows: [[version]]} = Repo.query!("SELECT sqlite_version()")
    version
  end

  defp data_counts(user) do
    count = fn table -> Repo.aggregate(from(r in table, where: r.user_id == ^user.id), :count) end

    %{
      transactions: count.("transactions"),
      statements: count.("bank_statements"),
      categories: count.("categories"),
      last_upload:
        Repo.one(
          from(s in "bank_statements", where: s.user_id == ^user.id, select: max(s.inserted_at))
        )
    }
  end

  # Jobs do Oban por estado (só os que interessam para quem opera a instância).
  defp job_counts do
    counts =
      from(j in "oban_jobs", group_by: j.state, select: {j.state, count(j.id)})
      |> Repo.all()
      |> Map.new()

    %{
      pending: Enum.sum(for s <- ~w(available scheduled executing retryable), do: counts[s] || 0),
      failed: Enum.sum(for s <- ~w(discarded), do: counts[s] || 0)
    }
  end

  defp unresolved_errors do
    Repo.aggregate(from(e in "error_tracker_errors", where: e.status == "unresolved"), :count)
  end

  defp connection_count(user) do
    Repo.aggregate(from(c in "open_finance_connections", where: c.user_id == ^user.id), :count)
  end

  @doc "Tempo ligado em texto curto (`2 d 3 h`, `5 min`)."
  def format_uptime(seconds) when seconds < 60, do: "#{seconds} s"
  def format_uptime(seconds) when seconds < 3600, do: "#{div(seconds, 60)} min"

  def format_uptime(seconds) when seconds < 86_400,
    do: "#{div(seconds, 3600)} h #{div(rem(seconds, 3600), 60)} min"

  def format_uptime(seconds), do: "#{div(seconds, 86_400)} d #{div(rem(seconds, 86_400), 3600)} h"

  defp ai_source(user) do
    cond do
      Accounts.env_ai_api_key() -> :env
      user.ai_api_key -> :database
      true -> nil
    end
  end

  defp database_size do
    path = Repo.config()[:database]

    case File.stat(path) do
      {:ok, %{size: size}} -> size
      {:error, _} -> nil
    end
  end

  @doc "Tamanho legível (`3,4 MB`)."
  def format_bytes(nil), do: "—"
  def format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"

  def format_bytes(bytes) do
    {value, unit} =
      cond do
        bytes < 1024 * 1024 -> {bytes / 1024, "KB"}
        bytes < 1024 * 1024 * 1024 -> {bytes / (1024 * 1024), "MB"}
        true -> {bytes / (1024 * 1024 * 1024), "GB"}
      end

    value |> Float.round(1) |> to_string() |> String.replace(".", ",") |> Kernel.<>(" #{unit}")
  end
end
