defmodule Granai.Mailer do
  use Swoosh.Mailer, otp_app: :granai

  @doc """
  Returns SMTP config override when :smtp_available is true (dev with SMTP_IN_DEV=true).
  In production, the adapter is already configured as SMTP via runtime.exs.
  """
  def smtp_config do
    if Application.get_env(:granai, :smtp_available, false) do
      smtp = Application.get_env(:granai, :smtp_config, [])
      [{:adapter, Swoosh.Adapters.SMTP} | smtp]
    else
      []
    end
  end
end
