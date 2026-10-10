defmodule Grana.Workers.InactivityReminderWorker do
  @moduledoc """
  Cron que lembra o dono da instância de atualizar os extratos quando faz mais de
  30 dias sem upload. Só roda com SMTP efetivo, no máximo um lembrete a cada 5 dias
  (`users.inactivity_reminded_at`). O resultado fica no meta do job, visível no
  painel do Oban.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 2

  require Logger

  import Ecto.Query

  alias Grana.Accounts
  alias Grana.Accounts.UserNotifier
  alias Grana.Banking.BankStatement
  alias Grana.Repo

  @inactivity_days 30
  @cooldown_days 5

  @impl Oban.Worker
  def perform(job) do
    outcome = remind(Accounts.get_owner(), Accounts.smtp_configured?())

    Oban.Job
    |> Repo.get(job.id)
    |> Ecto.Changeset.change(%{meta: Map.merge(job.meta, %{"outcome" => to_string(outcome)})})
    |> Repo.update()

    Logger.info("InactivityReminder: #{outcome}")
    :ok
  end

  defp remind(nil, _smtp?), do: :no_owner
  defp remind(_owner, false), do: :smtp_not_configured

  defp remind(owner, true) do
    now = DateTime.utc_now(:second)

    cond do
      not inactive?(owner, now) -> :active
      recently_reminded?(owner, now) -> :cooldown
      true -> send_reminder(owner, now)
    end
  end

  # Sem nenhum upload, conta a partir da criação da conta.
  defp inactive?(owner, now) do
    last_upload =
      Repo.one(
        from bs in BankStatement, where: bs.user_id == ^owner.id, select: max(bs.inserted_at)
      )

    reference = last_upload || owner.inserted_at
    DateTime.diff(now, reference |> as_utc(), :day) >= @inactivity_days
  end

  defp as_utc(%NaiveDateTime{} = naive), do: DateTime.from_naive!(naive, "Etc/UTC")
  defp as_utc(%DateTime{} = datetime), do: datetime

  defp recently_reminded?(%{inactivity_reminded_at: nil}, _now), do: false

  defp recently_reminded?(%{inactivity_reminded_at: at}, now),
    do: DateTime.diff(now, at, :day) < @cooldown_days

  defp send_reminder(owner, now) do
    case UserNotifier.deliver_inactivity_reminder(owner) do
      {:ok, _email} ->
        owner |> Ecto.Changeset.change(inactivity_reminded_at: now) |> Repo.update!()
        :sent

      {:error, reason} ->
        Logger.warning("InactivityReminder: falha no envio: #{inspect(reason)}")
        :failed
    end
  end
end
