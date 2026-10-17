defmodule GranaWeb.UploadQueueTest do
  use GranaWeb.ConnCase, async: false
  use Mimic

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Grana.Imports
  alias Grana.Workers.PlatformImportWorker

  setup :register_and_log_in_user

  setup do
    on_exit(fn -> File.rm_rf!(Path.join(Grana.DataDir.tmp_dir(), "imports")) end)
  end

  defp nubank_csv, do: File.read!("test/support/fixtures/examples/extrato-nubank.csv")

  defp open_nubank_extrato(conn) do
    {:ok, view, _html} = live(conn, ~p"/upload")
    render_click(view, "select_upload_category", %{"category" => "banking"})
    render_click(view, "select-bank", %{"bank" => "nubank"})
    render_click(view, "select-type", %{"type" => "extrato"})
    view
  end

  # Um `file_input` por arquivo: no LiveViewTest, as entradas de um mesmo input dividem um
  # cliente de upload, e consumir a primeira derruba o canal das outras (no navegador, não).
  defp upload(view, form_id, files) do
    Enum.each(files, fn {name, content} ->
      view
      |> file_input(form_id, :statements, [%{name: name, content: content, type: "text/csv"}])
      |> render_upload(name)
    end)

    view |> form(form_id) |> render_submit()
  end

  defp enqueue_platform(user, filenames) do
    files =
      Enum.map(filenames, fn filename ->
        path = Path.join(System.tmp_dir!(), "#{System.unique_integer([:positive])}-#{filename}")
        File.write!(path, "conteúdo")
        %{filename: filename, path: Imports.store!(path)}
      end)

    Imports.enqueue(user.id, PlatformImportWorker, %{}, files)
  end

  defp drain, do: Oban.drain_queue(queue: :uploads)

  test "aceita mais de 12 arquivos de uma vez, cada um vira um job", %{conn: conn, user: user} do
    view = open_nubank_extrato(conn)
    files = for n <- 1..13, do: {"extrato-#{n}.csv", nubank_csv()}

    input =
      file_input(
        view,
        "#upload-form",
        :statements,
        Enum.map(files, fn {name, content} ->
          %{name: name, content: content, type: "text/csv"}
        end)
      )

    render_upload(input, "extrato-1.csv")

    assert has_element?(view, "#upload-form button", "Processar 13 arquivos")
    refute render(view) =~ "Muitos arquivos"

    view = open_nubank_extrato(conn)
    upload(view, "#upload-form", files)

    assert has_element?(view, "#import-queue", "0 de 13 arquivos")
    assert %{total: 13, active?: true} = Imports.queue(user.id)
    refute has_element?(view, "#upload-form-entries")
  end

  test "processa em segundo plano e a tela acompanha", %{conn: conn, user: user} do
    view = open_nubank_extrato(conn)
    upload(view, "#upload-form", [{"extrato-jan.csv", nubank_csv()}])

    assert has_element?(view, "#import-queue h2", "Importando arquivos")
    assert has_element?(view, "#import-queue-files .ui-private-name", "extrato-jan.csv")
    assert has_element?(view, "#import-queue-files", "Na fila")
    refute has_element?(view, "#import-toast")
    refute has_element?(view, "button[phx-value-tab=historico]")

    drain()

    assert has_element?(view, "#import-queue h2", "Importação concluída")
    assert has_element?(view, "button[phx-value-tab=calendario]")
    assert has_element?(view, "#import-queue-files .ui-tag-ativo", "transações")
    assert [%{status: :ok}] = Imports.queue(user.id).files

    render_click(view, "switch_tab", %{"tab" => "historico"})
    assert has_element?(view, "#statements-table", "extrato-jan.csv")
  end

  test "erros aparecem em cada arquivo, em texto para o usuário", %{conn: conn, user: user} do
    stub(Grana.PlatformImport, :process, fn _content, _user_id, filename ->
      case filename do
        "vazio.csv" -> {:error, "No transactions found in file"}
        _ -> {:error, "formato inválido"}
      end
    end)

    enqueue_platform(user, ["vazio.csv", "outro.csv"])
    drain()

    {:ok, view, _html} = live(conn, ~p"/upload")

    assert has_element?(view, "#import-queue", "Nenhum arquivo importado: 2 erros.")
    assert has_element?(view, "#import-queue-files", "Nenhuma transação encontrada no arquivo.")
    assert has_element?(view, "#import-queue-files", "formato inválido")
  end

  test "voltar à tela de importação mostra a fila no mesmo estado", %{conn: conn, user: user} do
    enqueue_platform(user, ["a.csv", "b.csv"])

    Grana.Repo.update_all(where(Oban.Job, [j], j.args["filename"] == "a.csv"),
      set: [state: "executing"]
    )

    {:ok, view, _html} = live(conn, ~p"/upload")

    assert has_element?(view, "#import-queue", "0 de 2 arquivos")
    assert has_element?(view, "#import-queue-files", "Processando…")
    assert has_element?(view, "#import-queue-files", "Na fila")
  end

  test "fora da tela de importação, um aviso mostra o andamento", %{conn: conn, user: user} do
    stub(Grana.PlatformImport, :process, fn _content, _user_id, _filename ->
      {:ok, %{transaction_count: 4}}
    end)

    enqueue_platform(user, ["a.csv", "b.csv"])
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    assert has_element?(view, "#import-toast", "Importando arquivos")
    assert has_element?(view, "#import-toast", "0 de 2 arquivos")
    refute has_element?(view, "#import-toast-close")

    drain()

    assert has_element?(view, "#import-toast", "Importação concluída")
    assert has_element?(view, "#import-toast", "2 arquivos importados, 8 transações")

    view |> element("#import-toast-details") |> render_click()
    assert_redirect(view, ~p"/upload")
  end

  test "fechar o aviso limpa o resumo em todas as telas", %{conn: conn, user: user} do
    stub(Grana.PlatformImport, :process, fn _content, _user_id, _filename ->
      {:ok, %{transaction_count: 1}}
    end)

    enqueue_platform(user, ["a.csv"])
    drain()

    {:ok, upload, _html} = live(conn, ~p"/upload")
    {:ok, view, _html} = live(conn, ~p"/transactions")

    view |> element("#import-toast-close") |> render_click()

    refute has_element?(view, "#import-toast")
    refute has_element?(upload, "#import-queue")
    assert %{total: 0} = Imports.queue(user.id)
  end

  test "Limpar tira o resumo da tela de importação", %{conn: conn, user: user} do
    stub(Grana.PlatformImport, :process, fn _content, _user_id, _filename ->
      {:ok, %{transaction_count: 1}}
    end)

    enqueue_platform(user, ["a.csv"])
    drain()

    {:ok, view, _html} = live(conn, ~p"/upload")
    view |> element("#import-queue-clear") |> render_click()

    refute has_element?(view, "#import-queue")
  end

  test "o nome dos arquivos escolhidos fica marcado para o modo privacidade", %{conn: conn} do
    view = open_nubank_extrato(conn)

    input =
      file_input(view, "#upload-form", :statements, [
        %{name: "extrato-joao.csv", content: String.duplicate("x", 1_000), type: "text/csv"}
      ])

    render_upload(input, "extrato-joao.csv", 50)

    assert has_element?(view, "#upload-form-entries .ui-private-name", "extrato-joao.csv")
    assert has_element?(view, "#upload-form-entries", "enviando 50%")
  end
end
