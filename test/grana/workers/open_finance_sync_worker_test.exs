defmodule Grana.Workers.OpenFinanceSyncWorkerTest do
  use Grana.DataCase, async: false

  use Mimic
  use Oban.Testing, repo: Grana.Repo, engine: Oban.Engines.Lite

  import Grana.AccountsFixtures
  import Grana.OpenFinanceFixtures

  alias Grana.OpenFinance.{Connection, Pluggy}
  alias Grana.Workers.OpenFinanceSyncWorker

  setup do
    stub(Pluggy, :get_identity, fn _, _ -> {:ok, %{"documentType" => "CPF"}} end)
    %{user: with_pluggy_credentials(user_fixture())}
  end

  describe "connection sync" do
    test "syncs the connection", %{user: user} do
      connection = connection_fixture(user)
      stub(Pluggy, :get_item, fn _, _ -> {:ok, item_payload(%{"status" => "OUTDATED"})} end)
      stub(Pluggy, :list_accounts, fn _, _ -> {:ok, []} end)

      assert :ok = perform_job(OpenFinanceSyncWorker, %{"connection_id" => connection.id})
      assert Repo.get!(Connection, connection.id).status == "OUTDATED"
    end

    test "does not retry items removed on Pluggy", %{user: user} do
      connection = connection_fixture(user)
      stub(Pluggy, :get_item, fn _, _ -> {:error, :not_found} end)

      assert :ok = perform_job(OpenFinanceSyncWorker, %{"connection_id" => connection.id})
    end

    test "retries temporary failures", %{user: user} do
      connection = connection_fixture(user)
      stub(Pluggy, :get_item, fn _, _ -> {:error, :rate_limited} end)

      assert {:error, message} =
               perform_job(OpenFinanceSyncWorker, %{"connection_id" => connection.id})

      assert message =~ "Limite"
    end
  end

  describe "registration from the item/created webhook" do
    test "links the item to the user", %{user: user} do
      item = item_payload()
      stub(Pluggy, :get_item, fn _, _ -> {:ok, item} end)

      assert :ok =
               perform_job(OpenFinanceSyncWorker, %{"user_id" => user.id, "item_id" => item["id"]})

      assert Repo.get_by!(Connection, item_id: item["id"]).user_id == user.id
    end

    test "is idempotent and tolerates removed users or items", %{user: user} do
      connection = connection_fixture(user)

      assert :ok =
               perform_job(OpenFinanceSyncWorker, %{
                 "user_id" => user.id,
                 "item_id" => connection.item_id
               })

      assert :ok =
               perform_job(OpenFinanceSyncWorker, %{
                 "user_id" => -1,
                 "item_id" => Ecto.UUID.generate()
               })

      stub(Pluggy, :get_item, fn _, _ -> {:error, :not_found} end)

      assert :ok =
               perform_job(OpenFinanceSyncWorker, %{
                 "user_id" => user.id,
                 "item_id" => Ecto.UUID.generate()
               })
    end

    test "retries when Pluggy is unavailable", %{user: user} do
      stub(Pluggy, :get_item, fn _, _ -> {:error, {:transport, "timeout"}} end)

      assert {:error, _} =
               perform_job(OpenFinanceSyncWorker, %{
                 "user_id" => user.id,
                 "item_id" => Ecto.UUID.generate()
               })
    end
  end
end
