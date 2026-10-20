defmodule Grana.Banking.TransferIdentityTest do
  use ExUnit.Case, async: true

  alias Grana.Banking.TransferIdentity, as: TI

  @nubank_self "Transferência enviada pelo Pix - Ana Costa Ramos - •••.555.444-•• - Nubank (0260) Agência: 1 Conta: 11112222-3"
  @nubank_other "Transferência recebida pelo Pix - João Pereira Souza - •••.999.888-•• - BANCO INTER (0077) Agência: 1 Conta: 1-0"
  @bradesco_self "TRANSFERENCIA PIX - ANA COSTA RAMOS"
  @company "Transferência enviada pelo Pix - SEGURADORA EXEMPLO"

  test "transfer? reconhece pix/ted/doc/transferência e ignora o resto" do
    assert TI.transfer?(@nubank_self)
    assert TI.transfer?("TED RECEBIDA")
    refute TI.transfer?("Compra no débito - Padaria")
  end

  test "cpf6 extrai os 6 dígitos do meio do CPF mascarado" do
    assert TI.cpf6(@nubank_self) == "555444"
    assert TI.cpf6(@bradesco_self) == nil
  end

  test "cpf_middle pega posições 4-9 do CPF completo" do
    assert TI.cpf_middle("12355544445") == "555444"
    assert TI.cpf_middle("123.555.444-99") == "555444"
    assert TI.cpf_middle("123") == nil
  end

  test "counterparty_name extrai o nome normalizado" do
    assert TI.counterparty_name(@nubank_self) == "ana costa ramos"
    assert TI.counterparty_name(@bradesco_self) == "ana costa ramos"
    assert TI.counterparty_name(@company) == "seguradora exemplo"
  end

  test "own_identity? casa por nome completo ou pelo CPF do meio" do
    # nome + cpf batem
    assert TI.own_identity?(@nubank_self, "Ana Costa Ramos", "12355544445")
    # só nome (Bradesco sem CPF)
    assert TI.own_identity?(@bradesco_self, "Ana Costa Ramos", nil)
    # só CPF (nome diferente, mas mesmo CPF do meio)
    assert TI.own_identity?(@nubank_self, "Outro Nome", "99955544499")
    # nem nome nem CPF
    refute TI.own_identity?(@nubank_other, "Ana Costa Ramos", "12355544445")
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
    assert TI.rule_key(@nubank_self) == "cpf:555444"
    assert TI.rule_key(@bradesco_self) == "name:ana costa ramos"
    assert TI.rule_key("Compra cartão") == nil
  end

  test "rule_keys traz cpf e nome quando disponíveis" do
    assert "cpf:555444" in TI.rule_keys(@nubank_self)
    assert "name:ana costa ramos" in TI.rule_keys(@nubank_self)
  end
end
