defmodule Grana.Workers.NotificationWorkersTest do
  use Grana.DataCase, async: false
  use Mimic

  import Grana.AccountsFixtures
  import Grana.OpenFinanceFixtures
  import Swoosh.TestAssertions

  alias Grana.{Accounts, Banking}
  alias Grana.Workers.{FinancialAlertsWorker, InactivityReminderWorker}

  defp run(worker, args \\ %{}) do
    job = args |> worker.new() |> Oban.insert!()
    assert :ok = worker.perform(job)
    Repo.get!(Oban.Job, job.id)
  end

  defp age_account(user, days) do
    past = DateTime.add(DateTime.utc_now(:second), -days, :day)
    user |> Ecto.Changeset.change(inserted_at: past) |> Repo.update!()
  end

  describe "InactivityReminderWorker" do
    test "sem dono não faz nada" do
      assert run(InactivityReminderWorker).meta["outcome"] == "no_owner"
    end

    test "sem SMTP não envia" do
      user_fixture() |> age_account(40)
      reject(&Grana.Accounts.UserNotifier.deliver_inactivity_reminder/1)

      assert run(InactivityReminderWorker).meta["outcome"] == "smtp_not_configured"
    end

    test "dono com upload recente continua ativo" do
      user = user_fixture() |> smtp_fixture() |> age_account(60)

      {:ok, _} =
        Banking.create_statement(%{
          bank: "nubank",
          filename: "recent.csv",
          statement_type: "extrato",
          user_id: user.id
        })

      assert run(InactivityReminderWorker).meta["outcome"] == "active"
      refute_email_sent()
    end

    test "conta nova sem uploads ainda não é inativa" do
      user_fixture() |> smtp_fixture()
      assert run(InactivityReminderWorker).meta["outcome"] == "active"
    end

    test "envia o lembrete uma vez e respeita o cooldown de 5 dias" do
      user = user_fixture() |> smtp_fixture() |> age_account(40)

      assert run(InactivityReminderWorker).meta["outcome"] == "sent"
      assert_email_sent(to: {nil, user.email})
      assert Accounts.get_user!(user.id).inactivity_reminded_at

      assert run(InactivityReminderWorker).meta["outcome"] == "cooldown"
    end

    test "volta a lembrar depois do cooldown" do
      user = user_fixture() |> smtp_fixture() |> age_account(40)
      old = DateTime.add(DateTime.utc_now(:second), -6, :day)
      user |> Ecto.Changeset.change(inactivity_reminded_at: old) |> Repo.update!()

      assert run(InactivityReminderWorker).meta["outcome"] == "sent"
    end

    test "falha no envio não marca como lembrado" do
      user = user_fixture() |> smtp_fixture() |> age_account(40)

      expect(Grana.Accounts.UserNotifier, :deliver_inactivity_reminder, fn _ ->
        {:error, :timeout}
      end)

      assert run(InactivityReminderWorker).meta["outcome"] == "failed"
      assert Accounts.get_user!(user.id).inactivity_reminded_at == nil
    end
  end

  describe "FinancialAlertsWorker" do
    setup do
      %{user: user_fixture()}
    end

    defp negative_account(user) do
      connection = connection_fixture(user)
      account_fixture(connection, %{balance: Decimal.new("-10.00")})
    end

    test "sem SMTP não envia", %{user: user} do
      negative_account(user)
      run(FinancialAlertsWorker)
      refute_email_sent()
    end

    test "sem conexões não envia", %{user: user} do
      smtp_fixture(user)
      run(FinancialAlertsWorker)
      refute_email_sent()
    end

    test "sem alertas não envia", %{user: user} do
      smtp_fixture(user)
      connection = connection_fixture(user)
      account_fixture(connection)

      run(FinancialAlertsWorker)
      refute_email_sent()
    end

    test "com alertas manda um resumo", %{user: user} do
      smtp_fixture(user)
      negative_account(user)

      run(FinancialAlertsWorker)

      assert_email_sent(fn email ->
        assert email.subject =~ "Alertas financeiros"
        assert email.text_body =~ "Saldo negativo"
      end)
    end

    test "sem dono não faz nada" do
      Repo.delete_all(Accounts.User)
      assert run(FinancialAlertsWorker)
    end

    test "falha no envio não derruba o job", %{user: user} do
      smtp_fixture(user)
      negative_account(user)

      expect(Grana.Accounts.UserNotifier, :deliver_financial_alerts, fn _, _ ->
        {:error, :timeout}
      end)

      assert run(FinancialAlertsWorker)
    end
  end
end
