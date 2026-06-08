defmodule Grana.Banking.KeywordCategorizerTest do
  use ExUnit.Case, async: true

  alias Grana.Banking.KeywordCategorizer, as: KC

  test "IOF e siglas de tributo viram Impostos e Taxas" do
    assert KC.categorize(~s(IOF de "Claude.Ai")) == "Impostos e Taxas"
    assert KC.categorize("IRRF sobre rendimentos") == "Impostos e Taxas"
    assert KC.categorize("IPTU 2026 parcela 3") == "Impostos e Taxas"
    assert KC.categorize("IPVA 2026") == "Impostos e Taxas"
    assert KC.categorize("Pagamento INSS") == "Impostos e Taxas"
    assert KC.categorize("DARF Simples") == "Impostos e Taxas"
  end

  test "DAS MEI / Simples Nacional / multa / anuidade / tarifa / imposto" do
    assert KC.categorize("Pagamento DAS MEI") == "Impostos e Taxas"
    assert KC.categorize("DAS - Simples Nacional") == "Impostos e Taxas"
    assert KC.categorize("Multa de trânsito") == "Impostos e Taxas"
    assert KC.categorize("Anuidade do cartão") == "Impostos e Taxas"
    assert KC.categorize("Tarifa bancária mensal") == "Impostos e Taxas"
    assert KC.categorize("Imposto sobre serviço") == "Impostos e Taxas"
  end

  test "não classifica descrições comuns (siglas só casam como token inteiro)" do
    # 'iof' está DENTRO de 'biofarma' mas não é um token → não casa
    assert KC.categorize("Compra Biofarma") == nil
    assert KC.categorize("Mercado Livre") == nil
    # 'das' preposição não é tributo
    assert KC.categorize("Transferência das contas") == nil
  end

  test "clear_tax? é estrito: imposto inequívoco sim, taxa/tarifa genérica não" do
    assert KC.clear_tax?("IOF de X")
    assert KC.clear_tax?("Multa de atraso")
    assert KC.clear_tax?("DAS MEI")
    assert KC.clear_tax?("IPTU 2026")

    refute KC.clear_tax?("Tarifa de energia")
    refute KC.clear_tax?("Taxa de entrega")
    refute KC.clear_tax?("Compra padaria")
  end
end
