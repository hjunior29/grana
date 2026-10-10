defmodule Grana.Workers.InactivityReminderWorker do
  @moduledoc """
  Cron worker that checks for inactive users (no uploads in 30+ days)
  and sends them a friendly reminder email.

  Runs every 5 minutes via Oban Cron. Checks completed jobs to avoid
  sending duplicate emails to the same user within a 7-day window.
  Results are stored in job meta for inspection in the Oban dashboard.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 2

  require Logger

  import Ecto.Query

  alias Grana.Repo
  alias Grana.Accounts.User
  alias Grana.Accounts.UserNotifier
  alias Grana.Banking.BankStatement

  # @inactivity_days 0  # descomente para testar
  @inactivity_days 30
  @cooldown_days 5

  @impl Oban.Worker
  def perform(job) do
    cutoff = DateTime.utc_now() |> DateTime.add(-@inactivity_days, :day)
    inactive_users = fetch_inactive_users(cutoff)
    already_notified = recently_notified_emails()

    {skipped, to_notify} =
      Enum.split_with(inactive_users, fn user ->
        MapSet.member?(already_notified, user.email)
      end)

    results =
      Enum.map(to_notify, fn user ->
        case UserNotifier.deliver_inactivity_reminder(user) do
          {:ok, _email} ->
            Logger.info("InactivityReminder: sent to #{user.email}")
            %{email: user.email, status: "sent"}

          {:error, reason} ->
            Logger.warning("InactivityReminder: failed #{user.email}: #{inspect(reason)}")
            %{email: user.email, status: "failed", error: inspect(reason)}
        end
      end)

    sent = Enum.count(results, &(&1.status == "sent"))
    failed = Enum.count(results, &(&1.status == "failed"))

    meta = %{
      inactive_users_found: length(inactive_users),
      already_notified_skipped: length(skipped),
      emails_sent: sent,
      emails_failed: failed,
      details: results
    }

    Oban.Job
    |> Repo.get(job.id)
    |> Ecto.Changeset.change(%{meta: Map.merge(job.meta, meta)})
    |> Repo.update()

    Logger.info(
      "InactivityReminder: #{length(inactive_users)} inactive, #{length(skipped)} skipped, #{sent} sent, #{failed} failed"
    )

    :ok
  end

  # Busca emails que já receberam reminder nos últimos @cooldown_days
  # verificando os jobs completados deste worker no Oban.
  defp recently_notified_emails do
    since = DateTime.utc_now() |> DateTime.add(-@cooldown_days, :day)

    from(j in "oban_jobs",
      where: j.worker == "Grana.Workers.InactivityReminderWorker",
      where: j.state == "completed",
      where: j.completed_at >= ^since,
      select: j.meta
    )
    |> Repo.all()
    |> Enum.flat_map(fn meta ->
      case meta do
        %{"details" => details} when is_list(details) ->
          details
          |> Enum.filter(&(&1["status"] == "sent"))
          |> Enum.map(& &1["email"])

        _ ->
          []
      end
    end)
    |> MapSet.new()
  end

  defp fetch_inactive_users(cutoff) do
    latest_bank =
      from(bs in BankStatement,
        where: bs.user_id == parent_as(:user).id,
        select: max(bs.inserted_at)
      )

    from(u in User,
      as: :user,
      where: not is_nil(u.confirmed_at),
      where: subquery(latest_bank) < ^cutoff or is_nil(subquery(latest_bank))
    )
    |> Repo.all()
  end
end
