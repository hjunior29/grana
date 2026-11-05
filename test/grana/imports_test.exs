defmodule Grana.ImportsTest do
  use Grana.DataCase, async: false
  use Mimic

  import Grana.AccountsFixtures

  alias Grana.Imports
  alias Grana.Workers.PlatformImportWorker
  alias Grana.Workers.StatementUploadWorker

  @moduletag :tmp_dir

  setup do
    user = user_fixture()
    Grana.Banking.ensure_default_categories(user.id)
    Imports.subscribe(user.id)
    %{user: user}
  end

  defp stored(tmp_dir, filename, content) do
    path = Path.join(tmp_dir, filename)
    File.write!(path, content)
    %{filename: filename, path: Imports.store!(path)}
  end

  defp nubank_csv, do: File.read!("test/support/fixtures/examples/extrato-nubank.csv")

  defp enqueue_statements(user, files) do
    Imports.enqueue(
      user.id,
      StatementUploadWorker,
      %{"bank" => "nubank", "statement_type" => "extrato"},
      files
    )
  end

  defp drain, do: Oban.drain_queue(queue: :uploads)

  test "um job por arquivo, na fila até rodar", %{user: user, tmp_dir: tmp_dir} do
    enqueue_statements(user, [
      stored(tmp_dir, "jan.csv", nubank_csv()),
      stored(tmp_dir, "fev.csv", "lixo")
    ])

    assert_receive :imports_changed

    queue = Imports.queue(user.id)
    assert %{total: 2, finished: 0, failed: 0, active?: true} = queue

    assert [%{filename: "jan.csv", status: :pending}, %{filename: "fev.csv", status: :pending}] =
             queue.files
  end

  test "processa cada arquivo, guarda o resultado no job e apaga o arquivo", %{
    user: user,
    tmp_dir: tmp_dir
  } do
    good = stored(tmp_dir, "jan.csv", nubank_csv())
    bad = stored(tmp_dir, "fev.csv", "lixo")
    enqueue_statements(user, [good, bad])

    assert %{success: 2} = drain()

    queue = Imports.queue(user.id)
    assert %{total: 2, finished: 2, failed: 1, active?: false} = queue

    assert [%{status: :ok, count: count, bank: "nubank"}, %{status: :error, error: error}] =
             queue.files

    assert count > 0 and queue.transactions == count
    assert is_binary(error)
    assert [%{filename: "jan.csv"}] = Grana.Banking.list_statements(user.id)

    refute File.exists?(good.path)
    refute File.exists?(bad.path)
  end

  @tag :capture_log
  test "um arquivo que derruba o processador vira erro, sem expor detalhes", %{
    user: user,
    tmp_dir: tmp_dir
  } do
    stub(Grana.PlatformImport, :process, fn _content, _user_id, _filename -> raise "boom" end)

    Imports.enqueue(user.id, PlatformImportWorker, %{}, [stored(tmp_dir, "export.csv", "x")])
    drain()

    assert [%{status: :error, error: "Não foi possível processar este arquivo"}] =
             Imports.queue(user.id).files
  end

  test "erros em atom (ex.: sem chave de IA) viram texto", %{user: user, tmp_dir: tmp_dir} do
    stub(Grana.PlatformImport, :process, fn _content, _user_id, _filename ->
      {:error, :no_api_key}
    end)

    Imports.enqueue(user.id, PlatformImportWorker, %{}, [stored(tmp_dir, "export.csv", "x")])
    drain()

    assert [%{status: :error, error: "no_api_key", bank: nil}] = Imports.queue(user.id).files
  end

  test "importa o CSV da plataforma com o conteúdo do arquivo", %{user: user, tmp_dir: tmp_dir} do
    test_pid = self()

    stub(Grana.PlatformImport, :process, fn content, user_id, filename ->
      send(test_pid, {:processed, content, user_id, filename})
      {:ok, %{transaction_count: 7}}
    end)

    Imports.enqueue(user.id, PlatformImportWorker, %{}, [
      stored(tmp_dir, "export.csv", "conteúdo")
    ])

    drain()

    user_id = user.id
    assert_received {:processed, "conteúdo", ^user_id, "export.csv"}
    assert %{transactions: 7, failed: 0} = Imports.queue(user.id)
  end

  test "com a anterior terminada, a nova importação começa do zero", %{
    user: user,
    tmp_dir: tmp_dir
  } do
    enqueue_statements(user, [stored(tmp_dir, "jan.csv", nubank_csv())])
    drain()

    enqueue_statements(user, [stored(tmp_dir, "fev.csv", nubank_csv())])

    assert [%{filename: "fev.csv", status: :pending}] = Imports.queue(user.id).files
  end

  test "com a anterior rodando, os arquivos novos entram no fim dela", %{
    user: user,
    tmp_dir: tmp_dir
  } do
    enqueue_statements(user, [stored(tmp_dir, "jan.csv", nubank_csv())])
    enqueue_statements(user, [stored(tmp_dir, "fev.csv", nubank_csv())])

    assert [%{filename: "jan.csv"}, %{filename: "fev.csv"}] = Imports.queue(user.id).files
  end

  test "clear tira só o que terminou e apaga arquivos que sobraram", %{
    user: user,
    tmp_dir: tmp_dir
  } do
    orphan = stored(tmp_dir, "fev.csv", nubank_csv())
    pending = stored(tmp_dir, "mar.csv", nubank_csv())
    enqueue_statements(user, [stored(tmp_dir, "jan.csv", nubank_csv()), orphan, pending])

    set_job = fn filename, changes ->
      Repo.update_all(where(Oban.Job, [j], j.args["filename"] == ^filename), set: changes)
    end

    set_job.("jan.csv", state: "completed", meta: %{"status" => "ok", "count" => 3})
    # Job interrompido no meio (servidor caiu): descartado, com o arquivo ainda em disco.
    set_job.("fev.csv", state: "discarded")

    assert [%{status: :ok}, %{status: :error, error: nil}, %{status: :pending}] =
             Imports.queue(user.id).files

    Imports.clear(user.id)

    assert [%{filename: "mar.csv", status: :pending}] = Imports.queue(user.id).files
    refute File.exists?(orphan.path)
    assert File.exists?(pending.path)
  end

  test "job em execução aparece como processando", %{user: user, tmp_dir: tmp_dir} do
    enqueue_statements(user, [stored(tmp_dir, "jan.csv", nubank_csv())])
    Repo.update_all(Oban.Job, set: [state: "executing"])

    assert %{active?: true, files: [%{status: :processing}]} = Imports.queue(user.id)
  end

  test "jobs do formato antigo e de outros usuários ficam de fora", %{user: user} do
    %{
      "files" => [],
      "bank" => "nubank",
      "statement_type" => "extrato",
      "user_id" => user.id,
      "topic" => "t"
    }
    |> StatementUploadWorker.new()
    |> Oban.insert!()

    other = user_fixture()
    Imports.enqueue(other.id, PlatformImportWorker, %{}, [%{filename: "x.csv", path: "/nada"}])

    assert %{total: 0, active?: false} = Imports.queue(user.id)
  end
end
