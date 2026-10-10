defmodule Grana.Mailer do
  @moduledoc """
  Envio de emails. A configuração de SMTP (ambiente ou salva pela tela) é
  resolvida a cada envio por `Grana.Accounts.smtp_config/0`.

  Sem SMTP, prod não envia (`{:error, :smtp_not_configured}`; quem chama deve
  checar `Accounts.smtp_configured?/0`) e dev cai no adapter Local, visível em
  `/dev/mailbox`.
  """

  use Swoosh.Mailer, otp_app: :grana

  alias Swoosh.Email

  @doc "Envia o email pelo SMTP efetivo, ou por `smtp` quando informado (teste antes de salvar)."
  def send_email(%Email{} = email, smtp \\ nil) do
    case smtp || Grana.Accounts.smtp_config() do
      nil ->
        if Application.get_env(:grana, :mailer_local_fallback, false) do
          email |> Email.from({"Grana", "noreply@localhost"}) |> deliver()
        else
          {:error, :smtp_not_configured}
        end

      smtp ->
        email
        |> Email.from({smtp.from_name, smtp.from_address})
        |> deliver(swoosh_config(smtp))
    end
  end

  defp swoosh_config(smtp) do
    # Porta 465 é TLS implícito (ssl); as demais negociam STARTTLS conforme `tls`.
    implicit_tls? = smtp.port == 465
    tls_options = tls_options(smtp.host)

    [
      adapter: Application.get_env(:grana, :smtp_adapter, Swoosh.Adapters.SMTP),
      relay: smtp.host,
      port: smtp.port,
      username: smtp.username,
      password: smtp.password,
      ssl: implicit_tls?,
      tls: if(implicit_tls?, do: :never, else: smtp.tls),
      tls_options: tls_options,
      sockopts: if(implicit_tls?, do: tls_options, else: []),
      auth: if(smtp.username in [nil, ""], do: :never, else: :always),
      retries: 1
    ]
  end

  defp tls_options(host) do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(host),
      depth: 3,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end
end
