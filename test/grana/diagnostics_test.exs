defmodule Grana.DiagnosticsTest do
  use Grana.DataCase, async: true

  import Grana.AccountsFixtures

  alias Grana.Diagnostics

  test "summary traz versão, pasta, tamanho e a origem de cada credencial" do
    summary = Diagnostics.summary(user_fixture())

    assert summary.version =~ ~r/^\d+\.\d+\.\d+/
    assert summary.data_dir == Application.fetch_env!(:grana, :data_dir)
    assert is_integer(summary.database_size)

    assert [{"Chave do Gemini", nil}, {"Pluggy (Open Finance)", nil}, {"Email (SMTP)", nil}] =
             summary.credentials
  end

  test "reconhece credenciais salvas no banco" do
    user = user_fixture() |> smtp_fixture()
    user = user |> Ecto.Changeset.change(ai_api_key: "k") |> Grana.Repo.update!()

    credentials = Map.new(Diagnostics.summary(user).credentials)
    assert credentials["Chave do Gemini"] == :database
    assert credentials["Email (SMTP)"] == :database
  end

  test "format_bytes" do
    assert Diagnostics.format_bytes(nil) == "—"
    assert Diagnostics.format_bytes(512) == "512 B"
    assert Diagnostics.format_bytes(2048) == "2,0 KB"
    assert Diagnostics.format_bytes(3 * 1024 * 1024) == "3,0 MB"
    assert Diagnostics.format_bytes(2 * 1024 * 1024 * 1024) == "2,0 GB"
  end
end
