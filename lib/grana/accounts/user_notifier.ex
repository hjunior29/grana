defmodule Grana.Accounts.UserNotifier do
  import Swoosh.Email

  alias Grana.Accounts.User
  alias Grana.Mailer

  # --- Public API ---

  @doc "Email de teste enviado ao salvar o SMTP; usa a configuração candidata."
  def deliver_smtp_test(%User{} = user, smtp_config) do
    deliver(
      user.email,
      "Teste de email — Grana",
      email_html(
        "Email configurado!",
        "<p>Se você recebeu esta mensagem, o Grana consegue enviar emails por este servidor.</p><p>A partir de agora, o login passa a pedir um código de 6 dígitos enviado para este endereço.</p>",
        nil,
        nil,
        "Você recebeu este email porque configurou o SMTP no Grana."
      ),
      email_text(
        "Email configurado!",
        "Se você recebeu esta mensagem, o Grana consegue enviar emails por este servidor.\n\nA partir de agora, o login passa a pedir um código de 6 dígitos enviado para este endereço.",
        nil,
        "Você recebeu este email porque configurou o SMTP no Grana."
      ),
      smtp_config
    )
  end

  def deliver_two_factor_code(%User{} = user, code) do
    deliver(
      user.email,
      "#{code} é o seu código de acesso — Grana",
      email_html(
        "Seu código de acesso",
        """
        <p>Use o código abaixo para concluir o login no Grana:</p>
        <p style="margin:16px 0;font-size:32px;font-weight:700;letter-spacing:8px;color:#18181b;">#{code}</p>
        """,
        nil,
        nil,
        "O código vale por 10 minutos. Se não foi você, ignore este email e troque sua senha."
      ),
      email_text(
        "Seu código de acesso",
        "Use o código abaixo para concluir o login no Grana:\n\n#{code}",
        nil,
        "O código vale por 10 minutos. Se não foi você, ignore este email e troque sua senha."
      )
    )
  end

  def deliver_reset_password_instructions(%User{} = user, url) do
    deliver(
      user.email,
      "Recuperação de senha — Grana",
      email_html(
        "Recuperar senha",
        "<p>Recebemos um pedido para redefinir a senha da sua conta Grana.</p><p>Clique no botão abaixo para escolher uma nova senha:</p>",
        url,
        "Redefinir senha",
        "O link expira em 30 minutos. Se você não pediu, ignore este email — sua senha continua a mesma."
      ),
      email_text(
        "Recuperar senha",
        "Recebemos um pedido para redefinir a senha da sua conta Grana.\n\nAcesse o link abaixo para escolher uma nova senha:",
        url,
        "O link expira em 30 minutos. Se você não pediu, ignore este email."
      )
    )
  end

  @doc "Resumo diário com os alertas financeiros do Open Finance (lista de textos)."
  def deliver_financial_alerts(%User{} = user, alerts) when alerts != [] do
    items = Enum.map_join(alerts, "", &"<li>#{Plug.HTML.html_escape(&1)}</li>")
    url = Grana.Accounts.public_base_url(user) <> "/dashboard"

    deliver(
      user.email,
      "Alertas financeiros de hoje — Grana",
      email_html(
        "Alertas de hoje",
        "<p>Pontos de atenção nas suas contas conectadas:</p><ul>#{items}</ul>",
        url,
        "Abrir o Grana",
        "Você recebe este resumo porque o Open Finance e o email estão configurados no Grana."
      ),
      email_text(
        "Alertas de hoje",
        Enum.map_join(alerts, "\n", &"- #{&1}"),
        url,
        "Você recebe este resumo porque o Open Finance e o email estão configurados no Grana."
      )
    )
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(
      user.email,
      "Confirme seu novo email — Grana",
      email_html(
        "Alteração de email",
        """
        <p>Olá, <strong>#{user.email}</strong>!</p>
        <p>Recebemos uma solicitação para alterar o email da sua conta Grana.</p>
        <p>Clique no botão abaixo para confirmar o novo endereço:</p>
        """,
        url,
        "Confirmar novo email",
        "Se você não solicitou esta alteração, ignore este email. Seu email atual continuará o mesmo."
      ),
      email_text(
        "Alteração de email",
        "Recebemos uma solicitação para alterar o email da sua conta Grana.\n\nClique no link abaixo para confirmar:",
        url,
        "Se você não solicitou esta alteração, ignore este email."
      )
    )
  end

  @doc """
  Deliver a friendly reminder to inactive users to come back and update their finances.
  """
  def deliver_inactivity_reminder(user) do
    app_url = Grana.Accounts.public_base_url(user)

    deliver(
      user.email,
      "Faz tempo que não te vemos por aqui! \u{1F44B} — Grana",
      email_html(
        "Sentimos sua falta!",
        """
        <p>Olá!</p>
        <p>Percebemos que faz mais de <strong>30 dias</strong> que você não atualiza seus dados financeiros no <strong>Grana</strong>.</p>
        <p>Manter seus extratos e faturas em dia é essencial para ter uma visão clara das suas finanças — e leva apenas alguns minutinhos! \u{23F1}\u{FE0F}</p>
        <p>Que tal dar uma passadinha e enviar seus últimos extratos? Assim você continua no controle do seu dinheiro. \u{1F4B0}</p>
        """,
        app_url,
        "Atualizar meus dados",
        "Você recebeu este lembrete porque sua instância do Grana está com o email configurado."
      ),
      email_text(
        "Sentimos sua falta!",
        """
        Percebemos que faz mais de 30 dias que você não atualiza seus dados financeiros no Grana.

        Manter seus extratos e faturas em dia é essencial para ter uma visão clara das suas finanças — e leva apenas alguns minutinhos!

        Que tal dar uma passadinha e enviar seus últimos extratos?
        """,
        app_url,
        "Você recebeu este lembrete porque sua instância do Grana está com o email configurado."
      )
    )
  end

  # --- Private emails ---

  # --- Delivery ---

  defp deliver(recipient, subject, html, text, smtp_config \\ nil) do
    email =
      new()
      |> to(recipient)
      |> subject(subject)
      |> html_body(html)
      |> text_body(text)

    with {:ok, _metadata} <- Mailer.send_email(email, smtp_config) do
      {:ok, email}
    end
  end

  # --- HTML Template ---

  defp email_html(heading, content, url, button_text, footer_note) do
    year = Date.utc_today().year

    ~s"""
    <!DOCTYPE html>
    <html lang="pt-BR">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <link href="https://fonts.googleapis.com/css2?family=Grand+Hotel&display=swap" rel="stylesheet">
    </head>
    <body style="margin:0;padding:0;background-color:#f4f4f5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#f4f4f5;padding:32px 16px;">
        <tr>
          <td align="center">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background-color:#ffffff;border-radius:12px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,0.08);">
              <!-- Header -->
              <tr>
                <td style="background:linear-gradient(135deg,#9B8EC4 0%,#7C6DB0 100%);padding:28px 32px;text-align:center;">
                  <span style="font-family:'Grand Hotel',cursive;font-size:28px;font-weight:bold;color:#ffffff;letter-spacing:0.5px;">Grana</span>
                </td>
              </tr>
              <!-- Body -->
              <tr>
                <td style="padding:32px 32px 16px;">
                  <h1 style="margin:0 0 20px;font-size:22px;font-weight:700;color:#18181b;line-height:1.3;">#{heading}</h1>
                  <div style="font-size:15px;line-height:1.7;color:#3f3f46;">
                    #{content}
                  </div>
                </td>
              </tr>
              #{cta_html(url, button_text)}
              <!-- Divider -->
              <tr>
                <td style="padding:0 32px;"><hr style="border:none;border-top:1px solid #e4e4e7;margin:0;"></td>
              </tr>
              <!-- Footer note -->
              <tr>
                <td style="padding:20px 32px 28px;">
                  <p style="margin:0;font-size:13px;color:#a1a1aa;line-height:1.5;">#{footer_note}</p>
                </td>
              </tr>
            </table>
            <!-- Branding -->
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;">
              <tr>
                <td style="padding:20px 32px;text-align:center;">
                  <p style="margin:0;font-size:12px;color:#a1a1aa;">&copy; #{year} Grana &mdash; Suas finanças sob controle</p>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </body>
    </html>
    """
  end

  defp cta_html(nil, _button_text), do: ""

  defp cta_html(url, button_text) do
    """
    <tr>
      <td style="padding:8px 32px 28px;" align="center">
        <table role="presentation" cellpadding="0" cellspacing="0">
          <tr>
            <td style="background-color:#8B7CB8;border-radius:8px;">
              <a href="#{url}" target="_blank" style="display:inline-block;padding:14px 36px;font-size:15px;font-weight:600;color:#ffffff;text-decoration:none;">#{button_text}</a>
            </td>
          </tr>
        </table>
      </td>
    </tr>
    <tr>
      <td style="padding:0 32px 24px;">
        <p style="margin:0;font-size:12px;color:#a1a1aa;line-height:1.5;">Se o botão não funcionar, copie e cole este link no navegador:</p>
        <p style="margin:6px 0 0;font-size:12px;word-break:break-all;">
          <a href="#{url}" style="color:#7C6DB0;text-decoration:underline;">#{url}</a>
        </p>
      </td>
    </tr>
    """
  end

  # --- Text fallback ---

  defp email_text(heading, content, url, footer_note) do
    """
    #{heading}
    ========================================

    #{content}
    #{if url, do: "\n" <> url <> "\n"}
    ----------------------------------------
    #{footer_note}

    (c) #{Date.utc_today().year} Grana - Suas financas sob controle
    """
  end
end
