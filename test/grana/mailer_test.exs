defmodule Grana.MailerTest do
  use ExUnit.Case, async: true

  alias Grana.Mailer

  describe "smtp_config/0" do
    test "returns empty list when smtp_available is false (default)" do
      Application.delete_env(:grana, :smtp_available)
      assert Mailer.smtp_config() == []
    end

    test "returns smtp adapter config when smtp_available is true" do
      Application.put_env(:grana, :smtp_available, true)
      Application.put_env(:grana, :smtp_config, server: "smtp.example.com")

      config = Mailer.smtp_config()

      assert {:adapter, Swoosh.Adapters.SMTP} in config

      Application.delete_env(:grana, :smtp_available)
      Application.delete_env(:grana, :smtp_config)
    end
  end
end
