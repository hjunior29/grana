defmodule Grana.Accounts.UserNotifierTest do
  use Grana.DataCase, async: false

  import Grana.AccountsFixtures

  alias Grana.Accounts.UserNotifier

  setup do
    %{user: smtp_fixture(user_fixture())}
  end

  test "todo email leva a logo embutida e o mesmo layout", %{user: user} do
    {:ok, email} = UserNotifier.deliver_inactivity_reminder(user)

    assert [%Swoosh.Attachment{type: :inline, cid: "grana-logo", content_type: "image/png"}] =
             email.attachments

    assert email.html_body =~ ~s(src="cid:grana-logo")
    assert email.html_body =~ "Enviar meus extratos"
    assert email.text_body =~ "Enviar meus extratos: "
  end

  test "o código de acesso aparece numa caixa simples, em fonte monospace", %{user: user} do
    {:ok, email} = UserNotifier.deliver_two_factor_code(user, "482913")

    assert email.subject == "482913 é o seu código de acesso ao Grana"
    assert email.html_body =~ ~r/monospace[^>]*>482913</
    refute email.html_body =~ "$ grana"
    assert email.text_body =~ "\n482913\n"
  end

  test "o teste de SMTP mostra o envio numa janela de terminal", %{user: user} do
    {:ok, email} = UserNotifier.deliver_smtp_test(user, nil)

    assert email.html_body =~ "$ grana smtp teste"
    assert email.text_body =~ "$ grana smtp teste\nenviado com sucesso"
  end

  test "os textos não usam hífens nem travessões", %{user: user} do
    emails = [
      UserNotifier.deliver_smtp_test(user, nil),
      UserNotifier.deliver_two_factor_code(user, "123456"),
      UserNotifier.deliver_reset_password_instructions(user, "http://grana.local/reset"),
      UserNotifier.deliver_financial_alerts(user, ["Saldo negativo na conta corrente"]),
      UserNotifier.deliver_update_email_instructions(user, "http://grana.local/confirmar"),
      UserNotifier.deliver_inactivity_reminder(user)
    ]

    for {:ok, email} <- emails do
      refute email.subject =~ ~r/[—–]| - /u
      refute email.text_body =~ ~r/[—–]|^- | - /mu
    end
  end

  test "dados do usuário são escapados no HTML", %{user: user} do
    {:ok, email} =
      UserNotifier.deliver_update_email_instructions(
        %{user | email: "<b>x</b>@exemplo.com"},
        "http://grana.local/confirmar"
      )

    assert email.html_body =~ "&lt;b&gt;x&lt;/b&gt;@exemplo.com"
    refute email.html_body =~ "<b>x</b>"
  end
end
