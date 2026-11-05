defmodule GranaWeb.UserLive.SettingsTest do
  use GranaWeb.ConnCase

  alias Grana.Accounts
  import Phoenix.LiveViewTest
  import Grana.AccountsFixtures
  import Grana.BankingFixtures

  describe "Settings page" do
    test "renders settings page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      assert html =~ "Alterar email"
      assert html =~ "Salvar senha"
    end

    test "renders visual style preferences", %{conn: conn} do
      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      assert has_element?(lv, "#visual-style-toggle")
      assert has_element?(lv, ~s|#visual-style-toggle [data-phx-visual-style="default"]|)
      assert has_element?(lv, ~s|#visual-style-toggle [data-phx-visual-style="signal"]|)
      assert has_element?(lv, ~s|#visual-style-toggle [data-phx-visual-style="bossa"]|)
      assert has_element?(lv, ~s|#visual-style-toggle [data-phx-visual-style="papel"]|)
      assert has_element?(lv, ~s|#visual-style-toggle [data-phx-visual-style="caderneta"]|)
      assert has_element?(lv, ~s|#visual-style-toggle [data-phx-visual-style="planetario"]|)
      assert has_element?(lv, ~s|#visual-style-toggle [data-phx-visual-style="cyber"]|)
      assert has_element?(lv, "#visual-style-toggle .visual-style-description")
      assert has_element?(lv, "#visual-style-toggle .visual-style-preview")
    end

    test "redirects if user is not logged in", %{conn: conn} do
      ensure_owner(%{})
      assert {:error, redirect} = live(conn, ~p"/users/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "Você precisa estar logado para acessar esta página."} = flash
    end

    test "can be viewed without sudo mode, but sensitive actions require re-auth", %{conn: conn} do
      conn =
        log_in_user(conn, user_fixture(),
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -21, :minute)
        )

      # Ver a página não força mais reautenticação (antes parecia um logout).
      {:ok, lv, html} = live(conn, ~p"/users/settings")
      assert html =~ "Alterar email"

      # Mas uma ação sensível (trocar email) sem sudo mode redireciona para reautenticar.
      assert {:error, {:redirect, %{to: path}}} =
               lv
               |> form("#email_form", %{"user" => %{"email" => unique_user_email()}})
               |> render_submit()

      assert path == ~p"/users/log-in"
    end
  end

  describe "update email form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "sem SMTP troca o email direto", %{conn: conn, user: user} do
      new_email = unique_user_email()

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email_form", %{"user" => %{"email" => new_email}})
        |> render_submit()

      assert result =~ "Email alterado."
      assert Accounts.get_user_by_email(new_email)
      refute Accounts.get_user_by_email(user.email)
    end

    test "com SMTP envia o link de confirmação", %{conn: conn, user: user} do
      smtp_fixture(user)
      new_email = unique_user_email()

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email_form", %{"user" => %{"email" => new_email}})
        |> render_submit()

      assert result =~ "Link de confirmação enviado"
      assert Accounts.get_user_by_email(user.email)
    end

    test "updates the user email", %{conn: conn, user: user} do
      smtp_fixture(user)
      new_email = unique_user_email()

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email_form", %{
          "user" => %{"email" => new_email}
        })
        |> render_submit()

      assert result =~ "Link de confirmação enviado"
      assert Accounts.get_user_by_email(user.email)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> element("#email_form")
        |> render_change(%{
          "action" => "update_email",
          "user" => %{"email" => "with spaces"}
        })

      assert result =~ "Alterar email"
      assert result =~ "deve ter um @ e não pode ter espaços"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email_form", %{
          "user" => %{"email" => user.email}
        })
        |> render_submit()

      assert result =~ "Alterar email"
      assert result =~ "did not change"
    end
  end

  describe "update password form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the user password", %{conn: conn, user: user} do
      new_password = valid_user_password()

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      form =
        form(lv, "#password_form", %{
          "current_password" => valid_user_password(),
          "user" => %{
            "email" => user.email,
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      render_submit(form)

      new_password_conn = follow_trigger_action(form, conn)

      assert redirected_to(new_password_conn) == ~p"/users/settings"

      assert get_session(new_password_conn, :user_token) != get_session(conn, :user_token)

      assert Phoenix.Flash.get(new_password_conn.assigns.flash, :info) =~
               "Senha atualizada com sucesso"

      assert Accounts.get_user_by_email_and_password(user.email, new_password)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> element("#password_form")
        |> render_change(%{
          "user" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })

      assert result =~ "Salvar senha"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#password_form", %{
          "user" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })
        |> render_submit()

      assert result =~ "Salvar senha"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end
  end

  describe "confirm email" do
    setup %{conn: conn} do
      user = user_fixture() |> smtp_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{conn: log_in_user(conn, user), token: token, email: email, user: user}
    end

    test "updates the user email once", %{conn: conn, user: user, token: token, email: email} do
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")

      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"info" => message} = flash
      assert message == "Email alterado."
      refute Accounts.get_user_by_email(user.email)
      assert Accounts.get_user_by_email(email)

      # use confirm token again
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"error" => message} = flash
      assert message == "O link de confirmação é inválido ou expirou."
    end

    test "does not update email with invalid token", %{conn: conn, user: user} do
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/oops")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"error" => message} = flash
      assert message == "O link de confirmação é inválido ou expirou."
      assert Accounts.get_user_by_email(user.email)
    end

    test "redirects if user is not logged in", %{token: token} do
      ensure_owner(%{})
      conn = build_conn()
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")
      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => message} = flash
      assert message == "Você precisa estar logado para acessar esta página."
    end
  end

  describe "identity settings" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "update_identity saves name and CPF", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      render_click(view, "update_identity", %{
        "user" => %{"name" => "João Silva", "cpf" => "12345678901"}
      })

      html = render(view)
      assert html =~ "settings" or html =~ "salva"
    end
  end

  describe "apagar todos os dados" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "abre e fecha a confirmação", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      refute has_element?(lv, "#reset-modal")
      lv |> element("#show-reset-modal") |> render_click()
      assert has_element?(lv, "#reset-form")
      assert has_element?(lv, "#reset-progress", "Apagando todos os dados")
      assert has_element?(lv, "#confirm-reset")

      render_click(lv, "cancel_reset", %{})
      refute has_element?(lv, "#reset-modal")
    end

    test "sem digitar APAGAR nada acontece", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")
      lv |> element("#show-reset-modal") |> render_click()

      html =
        lv
        |> form("#reset-form", reset: %{password: valid_user_password(), confirmation: "apagar"})
        |> render_submit()

      assert html =~ "Digite APAGAR"
      assert has_element?(lv, "#reset-form", "Digite APAGAR para confirmar.")
      refute has_element?(lv, "#flash-error")
      assert Accounts.get_user!(user.id)
    end

    test "senha errada não apaga", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")
      lv |> element("#show-reset-modal") |> render_click()

      html =
        lv
        |> form("#reset-form", reset: %{password: "errada", confirmation: "APAGAR"})
        |> render_submit()

      assert html =~ "Senha incorreta"
      assert has_element?(lv, "#reset-form", "Senha incorreta.")
      refute has_element?(lv, "#flash-error")
      assert Accounts.get_user!(user.id)
    end

    test "com senha e APAGAR, apaga tudo e volta ao setup", %{conn: conn, user: user} do
      transaction_fixture(user)
      {:ok, lv, _html} = live(conn, ~p"/users/settings")
      lv |> element("#show-reset-modal") |> render_click()

      lv
      |> form("#reset-form", reset: %{password: valid_user_password(), confirmation: "APAGAR"})
      |> render_submit()

      assert_redirect(lv, ~p"/setup")
      assert Accounts.setup_required?()
      assert Grana.Repo.aggregate("transactions", :count) == 0
    end
  end

  describe "backup e diagnóstico" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "mostra o card de backup com download e restauração", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      assert has_element?(
               lv,
               ~s|#download-backup[href="/users/settings/backup"]|
             )

      assert has_element?(lv, "#backup-restore #restore-upload-form")
      assert has_element?(lv, "button#restore-verify[disabled]")
    end

    test "escolher o arquivo habilita Verificar", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      file =
        file_input(lv, "#restore-upload-form", :backup, [
          %{name: "meu-backup.db", content: String.duplicate("x", 2048)}
        ])

      render_upload(file, "meu-backup.db")

      refute has_element?(lv, "button#restore-verify[disabled]")
    end

    test "mostra jobs pendentes e com falha no atalho da fila", %{conn: conn} do
      Grana.Repo.insert!(Oban.Job.new(%{}, worker: "X"))
      Grana.Repo.insert!(Oban.Job.new(%{}, worker: "Y", state: "discarded"))

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      assert has_element?(lv, "#diagnostics-jobs-pending", "1")
      assert has_element?(lv, "#diagnostics-jobs-failed", "1 com falha")
    end

    test "mostra o diagnóstico da instância", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      refute has_element?(lv, "#diagnostics-version")
      refute render(lv) =~ "Grana #{Application.spec(:grana, :vsn)}"
      assert has_element?(lv, "#diagnostics-data-dir")
      assert has_element?(lv, "#diagnostics-db-size")
      assert has_element?(lv, "#diagnostics h3", "Sistema")
      assert has_element?(lv, "#diagnostics-uptime")
      assert has_element?(lv, "#diagnostics-transactions")
      assert has_element?(lv, "#diagnostics-integrations li", "Provedores de IA")
      assert has_element?(lv, "#integration-sources-legend .ui-tag-env")
      assert has_element?(lv, "#integration-sources-legend .ui-tag-salvo")
      assert has_element?(lv, "#diagnostics-runtime", "Elixir")
      assert has_element?(lv, "#diagnostics-public-url")
      assert has_element?(lv, "#diagnostics-oban")
      assert has_element?(lv, "#diagnostics-errors")
    end
  end
end
