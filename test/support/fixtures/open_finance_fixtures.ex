defmodule Grana.OpenFinanceFixtures do
  @moduledoc """
  Payloads no formato da API da Pluggy (baseados em respostas reais do Sandbox)
  e registros Open Finance prontos para os testes.
  """

  alias Grana.Banking.BankStatement
  alias Grana.OpenFinance.{Account, Connection}
  alias Grana.Repo

  def item_payload(attrs \\ %{}) do
    Map.merge(
      %{
        "id" => Ecto.UUID.generate(),
        "connector" => %{
          "id" => 200,
          "name" => "MeuPluggy",
          "imageUrl" => "https://cdn.pluggy.ai/assets/connector-icons/meupluggy.svg"
        },
        "status" => "UPDATED",
        "executionStatus" => "SUCCESS",
        "lastUpdatedAt" => "2026-10-10T06:17:59.640Z",
        "consentExpiresAt" => nil,
        "error" => nil,
        "clientUserId" => nil
      },
      attrs
    )
  end

  def bank_account_payload(attrs \\ %{}) do
    Map.merge(
      %{
        "id" => Ecto.UUID.generate(),
        "type" => "BANK",
        "subtype" => "CHECKING_ACCOUNT",
        "name" => "Conta Corrente",
        "marketingName" => "GOLD Conta Corrente",
        "number" => "0001/12345-0",
        "owner" => "John Doe",
        "currencyCode" => "BRL",
        "balance" => 36_471.9,
        "bankData" => %{
          "transferNumber" => "123/0001/12345-0",
          "automaticallyInvestedBalance" => 3647.1900000000005
        },
        "creditData" => nil
      },
      attrs
    )
  end

  def card_account_payload(attrs \\ %{}) do
    Map.merge(
      %{
        "id" => Ecto.UUID.generate(),
        "type" => "CREDIT",
        "subtype" => "CREDIT_CARD",
        "name" => "Mastercard Black",
        "marketingName" => "PLUGGY UNICLASS MASTERCARD BLACK",
        "number" => "9437",
        "owner" => nil,
        "currencyCode" => "BRL",
        "balance" => 838.5,
        "bankData" => nil,
        "creditData" => %{
          "level" => "BLACK",
          "brand" => "MASTERCARD",
          "balanceCloseDate" => "2026-10-10",
          "balanceDueDate" => "2026-10-15",
          "availableCreditLimit" => 2000,
          "creditLimit" => 3000,
          "minimumPayment" => 167.7
        }
      },
      attrs
    )
  end

  def transaction_payload(attrs \\ %{}) do
    Map.merge(
      %{
        "id" => Ecto.UUID.generate(),
        "description" => "SALARIO EMPRESA XYZ LTDA",
        "currencyCode" => "BRL",
        "amount" => 8500,
        "date" => "2026-10-05T03:00:00.000Z",
        "type" => "CREDIT",
        "status" => "POSTED",
        "category" => "Salary",
        "categoryId" => "01010000",
        "operationType" => nil,
        "creditCardMetadata" => nil,
        "providerId" => nil
      },
      attrs
    )
  end

  @client_id "0b0e2a4c-6c2d-4b8e-9f3a-1d2c3b4a5e6f"

  def pluggy_client_id, do: @client_id

  @doc "Salva credenciais da Pluggy (fictícias) no usuário, como se feitas pela tela."
  def with_pluggy_credentials(user, attrs \\ %{}) do
    user
    |> Ecto.Changeset.change(
      Map.merge(%{pluggy_client_id: @client_id, pluggy_client_secret: "test-secret"}, attrs)
    )
    |> Repo.update!()
  end

  def connection_fixture(user, attrs \\ %{}) do
    %Connection{
      user_id: user.id,
      item_id: Ecto.UUID.generate(),
      connector_id: 200,
      connector_name: "MeuPluggy",
      status: "UPDATED",
      execution_status: "SUCCESS",
      last_synced_at: DateTime.utc_now(:second)
    }
    |> struct!(attrs)
    |> Repo.insert!()
  end

  def account_fixture(connection, attrs \\ %{}) do
    %Account{
      pluggy_id: Ecto.UUID.generate(),
      type: "BANK",
      subtype: "CHECKING_ACCOUNT",
      name: "Conta Corrente",
      currency_code: "BRL",
      balance: Decimal.new("1500.00"),
      synced_at: DateTime.utc_now(:second),
      connection_id: connection.id,
      user_id: connection.user_id
    }
    |> struct!(attrs)
    |> Repo.insert!()
  end

  @doc "Extrato/fatura virtual do Open Finance (período sem upload) de uma conta."
  def open_finance_statement_fixture(account, attrs \\ %{}) do
    %BankStatement{
      source: "open_finance",
      bank: "nubank",
      filename: "Open Finance · fixture #{System.unique_integer([:positive])}",
      statement_type: "extrato",
      status: "completed",
      period_start: ~D[2026-10-01],
      period_end: ~D[2026-10-09],
      external_id: "#{account.pluggy_id}:extrato",
      open_finance_account_id: account.id,
      user_id: account.user_id
    }
    |> struct!(attrs)
    |> Repo.insert!()
  end
end
