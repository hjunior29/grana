defmodule Grana.Accounts.UserNotifier do
  @moduledoc """
  Emails do Grana. Todos usam o mesmo layout: a assinatura da marca no topo (imagem
  embutida no próprio email, para aparecer mesmo quando a instância só existe na rede
  local) e um cartão com o conteúdo, montado por blocos que geram ao mesmo tempo o
  HTML e a versão em texto puro.
  """
  import Swoosh.Email

  alias Grana.Accounts.User
  alias Grana.Mailer

  @logo_cid "grana-logo"

  # Paleta do email (clara de propósito: o layout pede `color-scheme: light only`).
  @ink "#0F172A"
  @body_text "#3F3F46"
  @muted "#71717A"
  @line "#E4E4E7"
  @terminal_bg "#0F172A"
  @terminal_bar "#1E293B"
  @terminal_dim "#94A3B8"
  @terminal_text "#34D399"

  # --- API pública ---

  @doc "Email de teste enviado ao salvar o SMTP; usa a configuração candidata."
  def deliver_smtp_test(%User{} = user, smtp_config) do
    deliver(
      user.email,
      "Seu email no Grana está funcionando",
      "Seu email está funcionando",
      [
        paragraph(
          "Se esta mensagem chegou, o Grana já consegue enviar emails pelo servidor que você configurou."
        ),
        terminal("grana smtp teste", "enviado com sucesso"),
        paragraph(
          "A partir de agora, todo login vai pedir um código de 6 dígitos enviado para este endereço."
        )
      ],
      "Você recebeu este email porque configurou o envio de emails no seu Grana.",
      smtp_config
    )
  end

  def deliver_two_factor_code(%User{} = user, code) do
    deliver(
      user.email,
      "#{code} é o seu código de acesso ao Grana",
      "Seu código de acesso",
      [
        paragraph("Use este código para terminar de entrar no Grana."),
        code_box(code)
      ],
      "O código vale por 10 minutos. Se não foi você que tentou entrar, ignore este email e troque sua senha."
    )
  end

  def deliver_reset_password_instructions(%User{} = user, url) do
    deliver(
      user.email,
      "Redefinição de senha do Grana",
      "Vamos criar uma senha nova",
      [
        paragraph(
          "Recebemos um pedido para redefinir a senha da sua conta. É só clicar no botão abaixo e escolher a senha nova."
        ),
        button(url, "Escolher nova senha")
      ],
      "O link vale por 30 minutos. Se não foi você que pediu, pode ignorar este email: sua senha continua a mesma."
    )
  end

  @doc "Resumo diário com os alertas financeiros do Open Finance (lista de textos)."
  def deliver_financial_alerts(%User{} = user, alerts) when alerts != [] do
    deliver(
      user.email,
      "Seus alertas financeiros de hoje",
      "Seus alertas de hoje",
      [
        paragraph("Separamos o que pede atenção nas suas contas conectadas."),
        alert_list(alerts),
        button(Grana.Accounts.public_base_url(user) <> "/dashboard", "Abrir o Grana")
      ],
      "Você recebe este resumo porque o Open Finance e o envio de emails estão configurados no seu Grana."
    )
  end

  @doc "Confirmação do novo endereço de email."
  def deliver_update_email_instructions(user, url) do
    deliver(
      user.email,
      "Confirme seu novo email no Grana",
      "Confirme seu novo email",
      [
        paragraph(
          "Recebemos um pedido para trocar o email da sua conta no Grana para #{strong(user.email)}.",
          "Recebemos um pedido para trocar o email da sua conta no Grana para #{user.email}."
        ),
        paragraph("Para confirmar que este endereço é seu, clique no botão abaixo."),
        button(url, "Confirmar novo email")
      ],
      "Se você não pediu essa troca, ignore este email. Seu email atual continua valendo."
    )
  end

  @doc "Lembrete gentil quando faz mais de 30 dias sem upload de extrato ou fatura."
  def deliver_inactivity_reminder(user) do
    deliver(
      user.email,
      "Faz um tempinho que você não atualiza o Grana",
      "Faz um tempinho que você não aparece",
      [
        paragraph(
          "Já passou mais de 30 dias desde o último extrato ou fatura que você enviou para o Grana."
        ),
        paragraph(
          "Manter tudo em dia leva poucos minutos e deixa o seu painel fiel ao que está acontecendo com o seu dinheiro."
        ),
        button(Grana.Accounts.public_base_url(user) <> "/upload", "Enviar meus extratos")
      ],
      "Você recebe este lembrete porque o envio de emails está configurado no seu Grana."
    )
  end

  # --- Envio ---

  defp deliver(recipient, subject, heading, blocks, note, smtp_config \\ nil) do
    email =
      new()
      |> to(recipient)
      |> subject(subject)
      |> html_body(layout_html(subject, heading, blocks, note))
      |> text_body(layout_text(heading, blocks, note))
      |> attachment(
        Swoosh.Attachment.new(logo_path(),
          filename: "grana.png",
          content_type: "image/png",
          type: :inline,
          cid: @logo_cid
        )
      )

    with {:ok, _metadata} <- Mailer.send_email(email, smtp_config) do
      {:ok, email}
    end
  end

  defp logo_path, do: Application.app_dir(:grana, "priv/static/images/email-logo.png")

  # --- Blocos (cada um devolve {html, texto}) ---

  defp paragraph(text), do: paragraph(escape(text), text)

  defp paragraph(html, text) do
    {~s(<p style="margin:0 0 16px;font-size:15px;line-height:1.7;color:#{@body_text};">#{html}</p>),
     text}
  end

  defp strong(text), do: ~s(<strong style="color:#{@ink};">#{escape(text)}</strong>)

  # Janela de terminal: três pontinhos, o comando digitado e a saída centralizada.
  defp terminal(command, output) do
    dot = fn color ->
      ~s(<span style="display:inline-block;width:10px;height:10px;border-radius:5px;background:#{color};margin-right:6px;"></span>)
    end

    html = """
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:8px 0 24px;border-collapse:separate;">
      <tr>
        <td style="background:#{@terminal_bar};border-radius:12px 12px 0 0;padding:10px 14px;line-height:10px;">
          #{dot.("#F87171")}#{dot.("#FBBF24")}#{dot.("#34D399")}
        </td>
      </tr>
      <tr>
        <td align="center" style="background:#{@terminal_bg};border-radius:0 0 12px 12px;padding:22px 20px 26px;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,'Liberation Mono',monospace;">
          <div style="font-size:13px;color:#{@terminal_dim};margin:0 0 12px;">$ #{escape(command)}</div>
          <div style="font-size:16px;font-weight:700;letter-spacing:1px;color:#{@terminal_text};">#{escape(output)}<span style="color:#{@terminal_dim};font-weight:400;letter-spacing:0;">&#9612;</span></div>
        </td>
      </tr>
    </table>
    """

    {html, "$ #{command}\n#{output}"}
  end

  # Caixa simples com o código de acesso: só a fonte lembra a de terminal.
  defp code_box(code) do
    html = """
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:8px 0 24px;border-collapse:separate;">
      <tr>
        <td align="center" style="background:#F4F4F5;border:1px solid #{@line};border-radius:12px;padding:24px 20px;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,'Liberation Mono',monospace;font-size:34px;font-weight:700;letter-spacing:10px;color:#{@ink};">#{escape(code)}</td>
      </tr>
    </table>
    """

    {html, code}
  end

  defp button(url, label) do
    html = """
    <table role="presentation" cellpadding="0" cellspacing="0" style="margin:8px 0 20px;">
      <tr>
        <td style="background:#{@ink};border-radius:10px;">
          <a href="#{url}" target="_blank" style="display:inline-block;padding:14px 28px;font-size:15px;font-weight:600;color:#FFFFFF;text-decoration:none;">#{escape(label)}</a>
        </td>
      </tr>
    </table>
    <p style="margin:0 0 16px;font-size:12px;line-height:1.6;color:#{@muted};">Se o botão não abrir, copie e cole este endereço no navegador:<br><a href="#{url}" style="color:#{@ink};word-break:break-all;">#{escape(url)}</a></p>
    """

    {html, "#{label}: #{url}"}
  end

  defp alert_list(alerts) do
    rows =
      Enum.map_join(alerts, "", fn alert ->
        """
        <tr>
          <td style="padding:12px 14px;border:1px solid #{@line};border-radius:10px;background:#FAFAFA;font-size:14px;line-height:1.5;color:#{@body_text};">
            <span style="display:inline-block;width:8px;height:8px;border-radius:4px;background:#F59E0B;margin-right:10px;"></span>#{escape(alert)}
          </td>
        </tr>
        <tr><td style="height:8px;line-height:8px;font-size:0;">&nbsp;</td></tr>
        """
      end)

    {~s(<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 16px;border-collapse:separate;">#{rows}</table>),
     Enum.map_join(alerts, "\n", &"• #{&1}")}
  end

  defp escape(text), do: text |> to_string() |> Plug.HTML.html_escape()

  # --- Layout ---

  defp layout_html(subject, heading, blocks, note) do
    content = Enum.map_join(blocks, "\n", &elem(&1, 0))

    """
    <!DOCTYPE html>
    <html lang="pt-BR">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <meta name="color-scheme" content="light only">
      <meta name="supported-color-schemes" content="light only">
      <title>#{escape(subject)}</title>
    </head>
    <body style="margin:0;padding:0;background:#F4F4F5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F4F4F5;padding:40px 16px;">
        <tr>
          <td align="center">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;">
              <tr>
                <td align="center" style="padding:0 0 24px;">
                  <img src="cid:#{@logo_cid}" width="209" height="40" alt="grana" style="display:block;border:0;outline:none;height:40px;width:209px;">
                </td>
              </tr>
              <tr>
                <td style="background:#FFFFFF;border:1px solid #{@line};border-radius:16px;padding:40px 36px 28px;">
                  <h1 style="margin:0 0 20px;font-size:24px;line-height:1.3;font-weight:700;color:#{@ink};">#{escape(heading)}</h1>
                  #{content}
                  <div style="border-top:1px solid #{@line};margin:12px 0 0;padding:20px 0 0;font-size:13px;line-height:1.6;color:#{@muted};">#{escape(note)}</div>
                </td>
              </tr>
              <tr>
                <td align="center" style="padding:24px 16px 0;font-size:12px;line-height:1.6;color:#A1A1AA;">
                  Enviado pelo seu Grana, suas finanças no seu servidor.
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

  defp layout_text(heading, blocks, note) do
    body = Enum.map_join(blocks, "\n\n", &elem(&1, 1))

    """
    #{heading}

    #{body}

    #{note}

    Enviado pelo seu Grana, suas finanças no seu servidor.
    """
  end
end
