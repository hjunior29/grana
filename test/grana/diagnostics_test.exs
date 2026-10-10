defmodule Grana.DiagnosticsTest do
  use Grana.DataCase, async: false

  import Grana.AccountsFixtures

  alias Grana.Diagnostics

  test "summary traz pasta, tamanho e a origem de cada credencial" do
    summary = Diagnostics.summary(user_fixture())

    refute Map.has_key?(summary, :version)
    assert summary.data_dir == Application.fetch_env!(:grana, :data_dir)
    assert is_integer(summary.database_size)

    assert [{"Chave do Gemini", nil}, {"Pluggy (Open Finance)", nil}, {"Email (SMTP)", nil}] =
             summary.credentials
  end

  test "summary traz dados, jobs, erros e ambiente" do
    user = user_fixture()
    Grana.BankingFixtures.transaction_fixture(user)
    Repo.insert!(Oban.Job.new(%{}, worker: "X"))

    summary = Diagnostics.summary(user)

    assert %{transactions: 1, statements: 1} = summary.data
    assert summary.data.categories > 0
    assert summary.data.last_upload
    assert summary.jobs.pending == 1
    assert summary.jobs.failed == 0
    assert summary.unresolved_errors == 0
    assert summary.uptime_seconds >= 0
    assert summary.public_url =~ "http"
    assert %{elixir: _, otp: _, sqlite: _} = summary.runtime
    assert summary.open_finance_connections == 0
  end

  test "format_uptime" do
    assert Diagnostics.format_uptime(5) == "5 s"
    assert Diagnostics.format_uptime(300) == "5 min"
    assert Diagnostics.format_uptime(3 * 3600 + 120) == "3 h 2 min"
    assert Diagnostics.format_uptime(2 * 86_400 + 3 * 3600) == "2 d 3 h"
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
