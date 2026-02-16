defmodule Granai.Banking.Parsers.NubankTest do
  use ExUnit.Case, async: true

  alias Granai.Banking.Parsers.Nubank

  @sample_csv """
  Data,Valor,Identificador,Descrição
  01/01/2026,-15.00,69568510-71d9-4de7-8840-1455aebae4a7,Pagamento de fatura
  02/01/2026,13200.00,695799b4-dab0-4ae4-bb34-79f360a4c419,Transferência recebida pelo Pix - FLAMBRA LTDA
  02/01/2026,-8.78,6957d111-ba04-4f7d-882a-45351dc50403,Compra no débito - RAYSA ATACADO E VAREJO
  """

  test "parses valid CSV content" do
    result = Nubank.parse(@sample_csv)
    assert length(result) == 3
  end

  test "parses date correctly" do
    [first | _] = Nubank.parse(@sample_csv)
    assert first.date == ~D[2026-01-01]
  end

  test "parses debit amount as negative" do
    [first | _] = Nubank.parse(@sample_csv)
    assert Decimal.compare(first.amount, Decimal.new("-15.00")) == :eq
    assert first.type == "debit"
  end

  test "parses credit amount as positive" do
    [_, second | _] = Nubank.parse(@sample_csv)
    assert Decimal.compare(second.amount, Decimal.new("13200.00")) == :eq
    assert second.type == "credit"
  end

  test "extracts identifier" do
    [first | _] = Nubank.parse(@sample_csv)
    assert first.identifier == "69568510-71d9-4de7-8840-1455aebae4a7"
  end

  test "extracts description" do
    [first | _] = Nubank.parse(@sample_csv)
    assert first.description == "Pagamento de fatura"
  end

  test "handles empty content" do
    assert Nubank.parse("Data,Valor,Identificador,Descrição\n") == []
  end

  test "handles malformed lines gracefully" do
    csv = "Data,Valor,Identificador,Descrição\nbad data\n"
    assert Nubank.parse(csv) == []
  end

  test "parses full example file" do
    content = File.read!("priv/examples/extrato-nubank.csv")
    result = Nubank.parse(content)
    assert length(result) > 70
    assert Enum.all?(result, &(&1.date != nil))
    assert Enum.all?(result, &(&1.amount != nil))
  end
end
