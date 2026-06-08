defmodule Grana.Banking.TransferIdentityTest do
  use ExUnit.Case, async: true

  alias Grana.Banking.TransferIdentity, as: TI

  @nubank_self "Transferência enviada pelo Pix - Amanda Silva Lima - •••.022.012-•• - Nubank (0260) Agência: 1 Conta: 25409235-0"
  @nubank_other "Transferência recebida pelo Pix - João Pereira Souza - •••.999.888-•• - BANCO INTER (0077) Agência: 1 Conta: 1-0"
  @bradesco_self "TRANSFERENCIA PIX - AMANDA SILVA LIMA"
  @company "Transferência enviada pelo Pix - ICATU SEGUROS"

  test "transfer? reconhece pix/ted/doc/transferência e ignora o resto" do
    assert TI.transfer?(@nubank_self)
    assert TI.transfer?("TED RECEBIDA")
    refute TI.transfer?("Compra no débito - Padaria")
  end

  test "cpf6 extrai os 6 dígitos do meio do CPF mascarado" do
    assert TI.cpf6(@nubank_self) == "022012"
    assert TI.cpf6(@bradesco_self) == nil
  end

  test "cpf_middle pega posições 4-9 do CPF completo" do
    assert TI.cpf_middle("12302201245") == "022012"
    assert TI.cpf_middle("123.022.012-45") == "022012"
    assert TI.cpf_middle("123") == nil
  end

  test "counterparty_name extrai o nome normalizado" do
    assert TI.counterparty_name(@nubank_self) == "amanda silva lima"
    assert TI.counterparty_name(@bradesco_self) == "amanda silva lima"
    assert TI.counterparty_name(@company) == "icatu seguros"
  end

  test "own_identity? casa por nome completo ou pelo CPF do meio" do
    # nome + cpf batem
    assert TI.own_identity?(@nubank_self, "Amanda Silva Lima", "12302201245")
    # só nome (Bradesco sem CPF)
    assert TI.own_identity?(@bradesco_self, "Amanda Silva Lima", nil)
    # só CPF (nome diferente, mas mesmo CPF do meio)
    assert TI.own_identity?(@nubank_self, "Outro Nome", "99902201299")
    # nem nome nem CPF
    refute TI.own_identity?(@nubank_other, "Amanda Silva Lima", "12302201245")
  end

  test "nome casa por sequência de tokens, sem falso-positivo por substring" do
    # "ana lima" NÃO deve casar dentro de "mariana lima souza"
    refute TI.own_identity?(
             "Transferência recebida pelo Pix - Mariana Lima Souza",
             "Ana Lima",
             nil
           )
  end

  test "rule_key prefere cpf, cai para nome" do
    assert TI.rule_key(@nubank_self) == "cpf:022012"
    assert TI.rule_key(@bradesco_self) == "name:amanda silva lima"
    assert TI.rule_key("Compra cartão") == nil
  end

  test "rule_keys traz cpf e nome quando disponíveis" do
    assert "cpf:022012" in TI.rule_keys(@nubank_self)
    assert "name:amanda silva lima" in TI.rule_keys(@nubank_self)
  end
end
