defmodule GranaWeb.UserSessionController do
  use GranaWeb, :controller

  alias Grana.Accounts
  alias GranaWeb.UserAuth

  plug GranaWeb.RateLimit, [action: :login] when action in [:create]

  def create(conn, params), do: create(conn, params, "Bem vindo de volta!")

  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, user_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Email ou senha inválidos")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/users/log-in")
    end
  end

  def update_password(conn, %{"user" => user_params} = params) do
    user = conn.assigns.current_scope.user

    cond do
      not Accounts.sudo_mode?(user) ->
        conn
        |> put_flash(:error, "Sua sessão expirou. Faça login novamente para alterar a senha.")
        |> redirect(to: ~p"/users/settings")

      true ->
        case Accounts.update_user_password(user, user_params) do
          {:ok, {_user, expired_tokens}} ->
            # disconnect all existing LiveViews with old sessions
            UserAuth.disconnect_sessions(expired_tokens)

            conn
            |> put_session(:user_return_to, ~p"/users/settings")
            |> create(params, "Senha atualizada com sucesso!")

          {:error, _changeset} ->
            conn
            |> put_flash(
              :error,
              "Não foi possível atualizar a senha. Verifique os dados informados."
            )
            |> redirect(to: ~p"/users/settings")
        end
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Saiu com sucesso.")
    |> UserAuth.log_out_user()
  end
end
