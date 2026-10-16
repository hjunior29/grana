defmodule GranaWeb.RestoreFlowTest do
  use Grana.BackupCase
  use GranaWeb, :verified_routes

  import Plug.Conn, only: [get_resp_header: 2]
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Grana.AccountsFixtures
  import Grana.BackupFixtures
  import Grana.BankingFixtures
  import GranaWeb.ConnCase, only: [log_in_user: 2, log_in_user: 3]

  alias Grana.{Accounts, Setup}
  alias Grana.Accounts.User

  @endpoint GranaWeb.Endpoint
  @moduletag :tmp_dir

  defp backup_binary(tmp_dir, fun) do
    path = Path.join(tmp_dir, "b-#{System.unique_integer([:positive])}.db")
    build_backup(path, fun)
    File.read!(path)
  end

  defp upload_backup(lv, binary) do
    file =
      file_input(lv, "#restore-upload-form", :backup, [%{name: "backup.db", content: binary}])

    render_upload(file, "backup.db")
    lv |> form("#restore-upload-form") |> render_submit()
  end

  describe "download" do
    setup do
      user = user_fixture()
      transaction_fixture(user, %{description: "ALMOÇO"})
      %{user: user}
    end

    test "exige login", %{} do
      conn = get(build_conn(), ~p"/users/settings/backup")
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "com sudo baixa um SQLite válido com os dados", %{tmp_dir: tmp, user: user} do
      conn = build_conn() |> log_in_user(user) |> get(~p"/users/settings/backup")

      assert response(conn, 200) |> binary_part(0, 16) == "SQLite format 3\0"
      assert get_resp_header(conn, "content-disposition") |> hd() =~ "grana-backup-"

      file = Path.join(tmp, "downloaded.db")
      File.write!(file, conn.resp_body)
      assert {:ok, %{users: [%{transactions: 1}]} = analysis} = Grana.Backup.analyze(file)
      Grana.Backup.discard(analysis.path)
    end

    test "sem sudo manda reautenticar", %{user: user} do
      stale = DateTime.add(DateTime.utc_now(:second), -21, :minute)
      conn = build_conn() |> log_in_user(user, token_authenticated_at: stale)

      conn = get(conn, ~p"/users/settings/backup")
      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "confirme seu login"
    end

    test "não deixa temporários para trás", %{user: user} do
      before = File.ls!(Grana.DataDir.tmp_dir())
      build_conn() |> log_in_user(user) |> get(~p"/users/settings/backup")
      assert File.ls!(Grana.DataDir.tmp_dir()) == before
    end
  end

  describe "restaurar pelas Configurações" do
    setup %{tmp_dir: tmp} do
      live_user = user_fixture(%{email: "vivo@example.com"})

      binary =
        backup_binary(tmp, fn ->
          owner = user_fixture(%{email: "dono@gmail.com"})
          user_fixture(%{email: "outro@example.com"})
          transaction_fixture(owner)

          Repo.insert!(%Grana.AI.ProviderConfig{
            user_id: owner.id,
            kind: "gemini",
            name: "Google Gemini",
            api_key: "gemini"
          })
        end)

      %{conn: log_in_user(build_conn(), live_user), binary: binary}
    end

    test "envia, restaura e pede novo login, avisando o que foi zerado", %{
      conn: conn,
      binary: binary
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      upload_backup(lv, binary)
      assert has_element?(lv, "#restore-options-form")
      assert render(lv) =~ "d•••@gmail.com"

      lv |> form("#restore-options-form") |> render_submit()

      {path, flash} = assert_redirect(lv)
      assert path == "/users/log-in"
      assert flash["info"] =~ "chaves dos provedores de IA"

      assert [%User{email: "dono@gmail.com"}] = Repo.all(User)
      assert Repo.one!(Grana.AI.ProviderConfig).api_key == nil
      assert Repo.aggregate("transactions", :count) == 1
    end

    test "dá para escolher outro usuário do backup", %{conn: conn, binary: binary} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")
      upload_backup(lv, binary)

      other_id =
        lv
        |> element("#restore-options-form input[type=radio]:not([checked])")
        |> render()
        |> then(&Regex.run(~r/value="(\d+)"/, &1))
        |> List.last()

      lv |> form("#restore-options-form", restore: %{user_id: other_id}) |> render_submit()
      assert_redirect(lv)

      assert [%User{email: "outro@example.com"}] = Repo.all(User)
    end

    test "chave de criptografia errada deixa tentar de novo sem reenviar o arquivo", %{
      conn: conn,
      binary: binary
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")
      upload_backup(lv, binary)

      html =
        lv
        |> form("#restore-options-form",
          restore: %{old_cloak_key: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="}
        )
        |> render_submit()

      assert html =~ "não decifra"
      assert has_element?(lv, "#restore-options-form")
      assert Repo.get_by(User, email: "vivo@example.com")

      lv |> form("#restore-options-form", restore: %{old_cloak_key: ""}) |> render_submit()
      assert_redirect(lv)
      assert [%User{email: "dono@gmail.com"}] = Repo.all(User)
    end

    test "arquivo que não é backup mostra o erro", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      upload_backup(lv, "isso não é um banco")

      assert has_element?(lv, "#flash-error", "não é um banco SQLite")
      assert render(lv) =~ "não é um banco SQLite"
      refute has_element?(lv, "#restore-options-form")
    end

    test "sem arquivo, pede para escolher um", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      html = lv |> form("#restore-upload-form") |> render_submit()
      assert html =~ "Escolha o arquivo"
      assert has_element?(lv, "#restore-upload-error")
      refute has_element?(lv, "#flash-error")
    end

    test "cancelar volta ao envio e apaga o temporário", %{conn: conn, binary: binary} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")
      upload_backup(lv, binary)
      assert [_] = Path.wildcard(Path.join(Grana.DataDir.tmp_dir(), "restore-*.db"))

      lv |> element("#restore-cancel") |> render_click()

      assert has_element?(lv, "#restore-upload-form")
      assert Path.wildcard(Path.join(Grana.DataDir.tmp_dir(), "restore-*.db")) == []
    end

    test "restaurar exige sudo mode", %{binary: binary} do
      user = Repo.get_by!(User, email: "vivo@example.com")
      stale = DateTime.add(DateTime.utc_now(:second), -21, :minute)
      conn = log_in_user(build_conn(), user, token_authenticated_at: stale)

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               upload_backup(lv, binary)

      assert Repo.get_by(User, email: "vivo@example.com")
    end
  end

  describe "restaurar pelo setup" do
    setup %{tmp_dir: tmp} do
      binary =
        backup_binary(tmp, fn ->
          owner = user_fixture(%{email: "dono@gmail.com"})
          transaction_fixture(owner)
        end)

      Accounts.invalidate_setup_cache()
      on_exit(&Setup.clear_code/0)
      %{binary: binary, code: Setup.generate_code()}
    end

    defp to_restore_step(lv, code) do
      lv |> form("#setup-code-form", setup: %{code: code}) |> render_submit()
      lv |> element("#setup-continue") |> render_click()
      lv |> element("#setup-restore") |> render_click()
    end

    test "o código do log libera a restauração", %{binary: binary, code: code} do
      {:ok, lv, _html} = live(build_conn(), ~p"/setup")
      to_restore_step(lv, code)
      assert has_element?(lv, "#setup-restore-step")

      upload_backup(lv, binary)
      lv |> form("#restore-options-form") |> render_submit()

      {path, _flash} = assert_redirect(lv)
      assert path == "/users/log-in"
      assert [%User{email: "dono@gmail.com"}] = Repo.all(User)
      refute Accounts.setup_required?()
    end

    test "voltar leva de novo à escolha", %{code: code} do
      {:ok, lv, _html} = live(build_conn(), ~p"/setup")
      to_restore_step(lv, code)

      lv |> element("#setup-restore-back") |> render_click()
      assert has_element?(lv, "#setup-choice-step")
    end

    test "se o código deixou de valer, não restaura", %{binary: binary, code: code} do
      {:ok, lv, _html} = live(build_conn(), ~p"/setup")
      to_restore_step(lv, code)
      upload_backup(lv, binary)

      Setup.clear_code()
      html = lv |> form("#restore-options-form") |> render_submit()

      assert html =~ "código do setup expirou"
      assert Accounts.setup_required?()
    end
  end
end
