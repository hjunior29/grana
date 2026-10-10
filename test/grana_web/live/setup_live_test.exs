defmodule GranaWeb.SetupLiveTest do
  use GranaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Grana.{Accounts, Setup}

  setup do
    on_exit(&Setup.clear_code/0)
    %{code: Setup.generate_code()}
  end

  defp to_account_step(conn, code) do
    {:ok, lv, _html} = live(conn, ~p"/setup")

    lv |> form("#setup-code-form", setup: %{code: code}) |> render_submit()
    lv |> element("#setup-continue") |> render_click()
    lv |> element("#setup-new-install") |> render_click()
    lv
  end

  test "começa pelo código e não avança com código errado", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/setup")
    assert has_element?(lv, "#setup-code-form")

    html = lv |> form("#setup-code-form", setup: %{code: "ZZZZ-ZZZZ"}) |> render_submit()

    assert html =~ "Código inválido"
    assert has_element?(lv, "#setup-code-form")
    refute has_element?(lv, "#setup-welcome-step")
  end

  test "código certo mostra as boas-vindas e depois o formulário da conta", %{
    conn: conn,
    code: code
  } do
    {:ok, lv, _html} = live(conn, ~p"/setup")

    lv |> form("#setup-code-form", setup: %{code: code}) |> render_submit()
    assert has_element?(lv, "#setup-welcome-step")

    lv |> element("#setup-continue") |> render_click()
    assert has_element?(lv, "#setup-choice-step")

    lv |> element("#setup-new-install") |> render_click()
    assert has_element?(lv, "#setup-account-form")
  end

  test "valida a conta e cria o dono, disparando o login", %{conn: conn, code: code} do
    lv = to_account_step(conn, code)

    html =
      lv
      |> form("#setup-account-form",
        user: %{
          name: "Ana",
          email: "ana@example.com",
          password: "curta",
          password_confirmation: "x"
        }
      )
      |> render_change()

    assert html =~ "should be at least 12 character"
    assert Accounts.setup_required?()

    form =
      form(lv, "#setup-account-form",
        user: %{
          name: "Ana",
          email: "ana@example.com",
          password: "uma senha longa",
          password_confirmation: "uma senha longa"
        }
      )

    render_submit(form)
    refute Accounts.setup_required?()

    owner = Accounts.get_user_by_email("ana@example.com")
    assert owner.confirmed_at
    assert owner.name == "Ana"
    assert Accounts.get_user_by_email_and_password("ana@example.com", "uma senha longa")
    refute Setup.verify_code(code)

    conn = submit_form(form, conn)
    assert redirected_to(conn) == "/onboarding"
  end

  test "register_owner recusa um segundo usuário" do
    attrs = %{
      name: "Ana",
      email: "ana@example.com",
      password: "uma senha longa",
      password_confirmation: "uma senha longa"
    }

    assert {:ok, _} = Accounts.register_owner(attrs)
    assert {:error, :already_set_up} = Accounts.register_owner(%{attrs | email: "b@example.com"})
  end

  test "register_owner exige confirmação da senha" do
    assert {:error, changeset} =
             Accounts.register_owner(%{
               name: "Ana",
               email: "a@example.com",
               password: "uma senha longa"
             })

    assert %{password_confirmation: ["does not match password"]} =
             Grana.DataCase.errors_on(changeset)
  end
end
