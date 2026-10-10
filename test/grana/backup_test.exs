defmodule Grana.BackupTest do
  use Grana.BackupCase

  import ExUnit.CaptureLog
  import Grana.AccountsFixtures
  import Grana.BackupFixtures
  import Grana.BankingFixtures

  alias Grana.{Accounts, Backup}
  alias Grana.Accounts.User

  @moduletag :tmp_dir

  @other_key "3yD9bfC5ZkE1w0o2cQXn8uG6hVtqPzRa7sLmJ4iKxNU="

  defp backup_path(tmp_dir),
    do: Path.join(tmp_dir, "backup-#{System.unique_integer([:positive])}.db")

  # Backup com 2 usuários: o primeiro com 3 transações e senha, o segundo vazio.
  defp two_user_backup(tmp_dir, opts \\ []) do
    path = backup_path(tmp_dir)

    ids =
      build_backup(path, fn ->
        owner = user_fixture(%{email: "dono@gmail.com"})
        other = user_fixture(%{email: "outro@example.com"})
        for n <- 1..3, do: transaction_fixture(owner, %{description: "Compra #{n}"})
        if opts[:secrets], do: opts[:secrets].(owner)
        {owner.id, other.id}
      end)

    {path, ids}
  end

  describe "create/1" do
    test "grava uma cópia consistente do banco", %{tmp_dir: tmp} do
      user_fixture() |> then(&transaction_fixture(&1))
      dest = Path.join(tmp, "copy.db")

      assert :ok = Backup.create(dest)

      assert {:ok, %{users: [%{transactions: 1}]} = analysis} = Backup.analyze(dest)
      Backup.discard(analysis.path)
    end

    test "falha com erro legível quando o destino não existe", %{tmp_dir: tmp} do
      assert {:error, message} = Backup.create(Path.join(tmp, "nao/existe/copy.db"))
      assert is_binary(message)
    end
  end

  describe "analyze/1" do
    test "valida, prepara e lista os usuários (o com mais dados primeiro)", %{tmp_dir: tmp} do
      {path, {owner_id, other_id}} = two_user_backup(tmp)

      assert {:ok, %{path: work, users: [first, second]}} = Backup.analyze(path)

      assert first == %{
               id: owner_id,
               email: "d•••@gmail.com",
               transactions: 3,
               has_password?: true
             }

      assert %{id: ^other_id, transactions: 0} = second
      assert File.exists?(work)
      assert work != path

      Backup.discard(work)
      refute File.exists?(work)
    end

    test "backup de versão anterior é migrado na cópia", %{tmp_dir: tmp} do
      path = backup_path(tmp)

      build_old_backup(path, fn -> user_fixture() end)

      assert {:ok, %{path: work, users: [_]}} = Backup.analyze(path)
      Backup.discard(work)
    end

    test "recusa arquivo que não é SQLite", %{tmp_dir: tmp} do
      path = Path.join(tmp, "texto.db")
      File.write!(path, "isso não é um banco")

      assert Backup.analyze(path) == {:error, :not_sqlite}
    end

    test "recusa arquivo corrompido", %{tmp_dir: tmp} do
      {path, _} = two_user_backup(tmp)
      content = File.read!(path)
      File.write!(path, binary_part(content, 0, 4096) <> :binary.copy(<<0>>, 8192))

      {result, _log} = with_log(fn -> Backup.analyze(path) end)
      assert {:error, reason} = result
      assert reason in [:corrupted, :invalid_file]
    end

    test "recusa SQLite que não é do Grana", %{tmp_dir: tmp} do
      path = backup_path(tmp)
      build_backup(path, fn -> Repo.query!("DROP TABLE schema_migrations") end)

      assert Backup.analyze(path) == {:error, :not_grana_backup}
    end

    test "recusa backup mais novo que o app", %{tmp_dir: tmp} do
      path = backup_path(tmp)

      build_backup(path, fn ->
        user_fixture()
        Repo.query!("INSERT INTO schema_migrations (version) VALUES (29991231235959)")
      end)

      assert Backup.analyze(path) == {:error, :newer_backup}
    end

    test "recusa backup sem usuários", %{tmp_dir: tmp} do
      path = backup_path(tmp)
      build_backup(path, fn -> :ok end)

      assert Backup.analyze(path) == {:error, :no_users}
    end

    test "o arquivo enviado não é alterado", %{tmp_dir: tmp} do
      {path, _} = two_user_backup(tmp)
      before = File.read!(path)

      {:ok, %{path: work}} = Backup.analyze(path)
      Backup.discard(work)

      assert File.read!(path) == before
    end
  end

  describe "restore/3" do
    test "troca os dados vivos pelos do backup, só com o usuário escolhido", %{tmp_dir: tmp} do
      live_user = user_fixture(%{email: "vivo@example.com"})
      transaction_fixture(live_user)
      session = Accounts.generate_user_session_token(live_user)

      {path, {owner_id, _other_id}} = two_user_backup(tmp)
      {:ok, analysis} = Backup.analyze(path)

      assert {:ok, %{cleared: []}} = Backup.restore(analysis, owner_id)

      assert [%User{id: ^owner_id, email: "dono@gmail.com"} = restored] = Repo.all(User)
      assert restored.confirmed_at
      assert restored.onboarded_at
      assert Accounts.get_user_by_email_and_password("dono@gmail.com", valid_user_password())
      assert count("transactions") == 3
      assert Repo.aggregate(from(t in "transactions", where: t.user_id == ^owner_id), :count) == 3
      assert Repo.all(from(c in "categories", select: c.user_id, distinct: true)) == [owner_id]
      refute Accounts.get_user_by_session_token(session)
      refute Accounts.setup_required?()
      refute File.exists?(analysis.path)
    end

    test "escolher outro usuário descarta o resto", %{tmp_dir: tmp} do
      {path, {_owner_id, other_id}} = two_user_backup(tmp)
      {:ok, analysis} = Backup.analyze(path)

      assert {:ok, _} = Backup.restore(analysis, other_id)
      assert [%User{id: ^other_id}] = Repo.all(User)
      assert count("transactions") == 0
    end

    test "usuário sem senha exige uma nova; senha curta é recusada", %{tmp_dir: tmp} do
      path = backup_path(tmp)

      build_backup(path, fn ->
        user = user_fixture()
        user |> Ecto.Changeset.change(hashed_password: nil) |> Repo.update!()
        user.id
      end)

      {:ok, analysis} = Backup.analyze(path)
      [%{id: id, has_password?: false}] = analysis.users

      # Erros corrigíveis na tela mantêm o temporário: o mesmo `analysis` serve de novo.
      assert Backup.restore(analysis, id) == {:error, :password_required}
      assert File.exists?(analysis.path)
      assert Backup.restore(analysis, id, new_password: "curta") == {:error, :password_invalid}
      assert File.exists?(analysis.path)

      assert {:ok, _} = Backup.restore(analysis, id, new_password: "uma senha bem longa")
      refute File.exists?(analysis.path)
      assert [%User{email: email}] = Repo.all(User)
      assert Accounts.get_user_by_email_and_password(email, "uma senha bem longa")
    end

    test "grava a origem (base_url) quando informada", %{tmp_dir: tmp} do
      {path, {owner_id, _}} = two_user_backup(tmp)
      {:ok, analysis} = Backup.analyze(path)

      {:ok, _} = Backup.restore(analysis, owner_id, base_url: "http://192.168.0.9:4000")
      assert [%User{base_url: "http://192.168.0.9:4000"}] = Repo.all(User)
    end

    test "sem a chave antiga, zera os segredos cifrados e avisa quais", %{tmp_dir: tmp} do
      {path, {owner_id, _}} =
        two_user_backup(tmp,
          secrets: fn owner ->
            owner
            |> Ecto.Changeset.change(ai_api_key: "gemini-key", cpf: "12345678901")
            |> Repo.update!()
          end
        )

      {:ok, analysis} = Backup.analyze(path)
      assert {:ok, %{cleared: cleared}} = Backup.restore(analysis, owner_id)

      assert Enum.sort(cleared) == ["ai_api_key", "cpf"]
      restored = Repo.one!(User)
      assert restored.ai_api_key == nil
      assert restored.cpf == nil
    end

    test "com a chave antiga certa, leva as credenciais para a chave atual", %{tmp_dir: tmp} do
      current = Application.fetch_env!(:grana, :cloak_key)
      Application.put_env(:grana, :cloak_key, @other_key)

      {path, {owner_id, _}} =
        try do
          two_user_backup(tmp,
            secrets: fn owner ->
              owner
              |> Ecto.Changeset.change(ai_api_key: "gemini-key", smtp_password: "smtp-pass")
              |> Repo.update!()
            end
          )
        after
          Application.put_env(:grana, :cloak_key, current)
        end

      {:ok, analysis} = Backup.analyze(path)
      assert {:ok, %{cleared: []}} = Backup.restore(analysis, owner_id, old_cloak_key: @other_key)

      restored = Repo.one!(User)
      assert restored.ai_api_key == "gemini-key"
      assert restored.smtp_password == "smtp-pass"
    end

    test "chave antiga errada recusa e não mexe nos dados vivos", %{tmp_dir: tmp} do
      live_user = user_fixture(%{email: "vivo@example.com"})

      current = Application.fetch_env!(:grana, :cloak_key)
      Application.put_env(:grana, :cloak_key, @other_key)

      {path, {owner_id, _}} =
        try do
          two_user_backup(tmp,
            secrets: fn owner ->
              owner |> Ecto.Changeset.change(ai_api_key: "k") |> Repo.update!()
            end
          )
        after
          Application.put_env(:grana, :cloak_key, current)
        end

      {:ok, analysis} = Backup.analyze(path)

      wrong = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

      assert Backup.restore(analysis, owner_id, old_cloak_key: wrong) ==
               {:error, :wrong_cloak_key}

      assert Backup.restore(analysis, owner_id, old_cloak_key: "lixo") ==
               {:error, :wrong_cloak_key}

      assert [%User{id: id}] = Repo.all(User)
      assert id == live_user.id
    end
  end

  describe "reset_all/0" do
    test "apaga usuário, dados, jobs e erros, e volta ao setup" do
      user = user_fixture()
      transaction_fixture(user)
      Accounts.generate_user_session_token(user)
      Repo.insert!(Oban.Job.new(%{}, worker: "Grana.Workers.FinancialAlertsWorker"))

      assert :ok = Backup.reset_all()

      assert count("users") == 0
      assert count("transactions") == 0
      assert count("categories") == 0
      assert count("users_tokens") == 0
      assert count("oban_jobs") == 0
      assert Accounts.setup_required?()
    end
  end
end
