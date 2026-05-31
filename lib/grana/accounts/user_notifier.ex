defmodule Grana.Accounts.UserNotifier do
  import Swoosh.Email

  alias Grana.Mailer
  alias Grana.Accounts.User

  # --- Public API ---

  @doc """
  Deliver instructions to log in with a magic link.
  Dispatches to confirmation or magic link based on user state.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
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
    app_url = GranaWeb.Endpoint.url()

    deliver(
      user.email,
      "Faz tempo que não te vemos por aqui! \u{1F44B} — Grana",
      email_html(
        "Sentimos sua falta!",
        """
        <p>Olá!</p>
        <p>Percebemos que faz mais de <strong>30 dias</strong> que você não atualiza seus dados financeiros no <strong>Grana</strong>.</p>
        <p>Manter seus extratos e investimentos em dia é essencial para ter uma visão clara das suas finanças — e leva apenas alguns minutinhos! \u{23F1}\u{FE0F}</p>
        <p>Que tal dar uma passadinha e enviar seus últimos extratos? Assim você continua no controle do seu dinheiro. \u{1F4B0}</p>
        """,
        app_url,
        "Atualizar meus dados",
        "Você recebeu este email porque tem uma conta no Grana. Se não deseja mais receber lembretes, basta ignorar esta mensagem."
      ),
      email_text(
        "Sentimos sua falta!",
        """
        Percebemos que faz mais de 30 dias que você não atualiza seus dados financeiros no Grana.

        Manter seus extratos e investimentos em dia é essencial para ter uma visão clara das suas finanças — e leva apenas alguns minutinhos!

        Que tal dar uma passadinha e enviar seus últimos extratos?
        """,
        app_url,
        "Você recebeu este email porque tem uma conta no Grana. Se não deseja mais receber lembretes, basta ignorar esta mensagem."
      )
    )
  end

  # --- Private emails ---

  defp deliver_magic_link_instructions(user, url) do
    deliver(
      user.email,
      "Seu link de acesso — Grana",
      email_html(
        "Entrar na sua conta",
        """
        <p>Olá, <strong>#{user.email}</strong>!</p>
        <p>Você solicitou um link para entrar na sua conta Grana.</p>
        <p>Clique no botão abaixo para acessar:</p>
        """,
        url,
        "Entrar na minha conta",
        "Este link expira em 15 minutos. Se você não solicitou este acesso, ignore este email."
      ),
      email_text(
        "Entrar na sua conta",
        "Você solicitou um link para entrar na sua conta Grana.\n\nClique no link abaixo para acessar:",
        url,
        "Este link expira em 15 minutos. Se você não solicitou este acesso, ignore este email."
      )
    )
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(
      user.email,
      "Confirme sua conta — Grana",
      email_html(
        "Bem-vindo ao Grana!",
        """
        <p>Olá, <strong>#{user.email}</strong>!</p>
        <p>Obrigado por criar sua conta no <strong>Grana</strong>!</p>
        <p>Para começar a organizar suas finanças, confirme seu email clicando no botão abaixo:</p>
        """,
        url,
        "Confirmar minha conta",
        "Se você não criou uma conta no Grana, ignore este email."
      ),
      email_text(
        "Bem-vindo ao Grana!",
        "Obrigado por criar sua conta no Grana!\n\nPara começar, confirme seu email clicando no link abaixo:",
        url,
        "Se você não criou uma conta no Grana, ignore este email."
      )
    )
  end

  # --- Delivery ---

  defp deliver(recipient, subject, html, text) do
    {from_name, from_address} = mail_from()

    email =
      new()
      |> to(recipient)
      |> from({from_name, from_address})
      |> subject(subject)
      |> html_body(html)
      |> text_body(text)

    with {:ok, _metadata} <- Mailer.deliver(email, Mailer.smtp_config()) do
      {:ok, email}
    end
  end

  defp mail_from do
    config = Application.get_env(:grana, :mail_from, [])
    {Keyword.get(config, :name, "Grana"), Keyword.get(config, :address, "noreply@example.com")}
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
              <!-- CTA -->
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
              <!-- URL fallback -->
              <tr>
                <td style="padding:0 32px 24px;">
                  <p style="margin:0;font-size:12px;color:#a1a1aa;line-height:1.5;">Se o botão não funcionar, copie e cole este link no navegador:</p>
                  <p style="margin:6px 0 0;font-size:12px;word-break:break-all;">
                    <a href="#{url}" style="color:#7C6DB0;text-decoration:underline;">#{url}</a>
                  </p>
                </td>
              </tr>
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

  # --- Text fallback ---

  defp email_text(heading, content, url, footer_note) do
    """
    #{heading}
    ========================================

    #{content}

    #{url}

    ----------------------------------------
    #{footer_note}

    (c) #{Date.utc_today().year} Grana - Suas financas sob controle
    """
  end
end
