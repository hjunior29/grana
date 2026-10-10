defmodule Grana.ReleaseCliTest do
  use Grana.DataCase, async: false

  import ExUnit.CaptureIO
  import Grana.AccountsFixtures

  alias Grana.{Accounts, Release}

  describe "reset_password/0" do
    test "sem dono, orienta a abrir o setup" do
      assert capture_io(&Release.reset_password/0) =~ "ainda não tem dono"
    end

    test "imprime um link que de fato redefine a senha do dono" do
      user = user_fixture()

      output = capture_io(&Release.reset_password/0)

      assert [_, token] = Regex.run(~r{/users/reset-password/(\S+)}, output)
      assert Accounts.get_user_by_reset_password_token(token).id == user.id
    end
  end

  describe "disable_smtp/0" do
    test "apaga o SMTP salvo" do
      user_fixture() |> smtp_fixture()

      assert capture_io(&Release.disable_smtp/0) =~ "SMTP salvo no banco removido"
      refute Accounts.smtp_configured?()
    end

    test "avisa quando o SMTP vem do ambiente" do
      user_fixture() |> smtp_fixture()
      Application.put_env(:grana, :smtp_env, %{host: "env.example.com", port: 25, tls: :never})
      on_exit(fn -> Application.delete_env(:grana, :smtp_env) end)

      assert capture_io(&Release.disable_smtp/0) =~ "ainda há SMTP no ambiente"
    end

    test "sem dono não quebra" do
      assert capture_io(&Release.disable_smtp/0) == ""
    end
  end
end
