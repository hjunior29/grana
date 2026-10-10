defmodule GranaWeb.UserSessionController do
  use GranaWeb, :controller

  alias Grana.Accounts
  alias GranaWeb.UserAuth

  plug GranaWeb.RateLimit, [action: :login] when action in [:create]
  plug GranaWeb.RateLimit, [action: :two_factor] when action in [:verify_code]

  def create(conn, params), do: create(conn, params, "Bem vindo de volta!")

  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    user = Accounts.get_user_by_email_and_password(email, password)

    cond do
      user && Accounts.smtp_configured?() ->
        start_two_factor(conn, user, user_params)

      user ->
        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)

      true ->
        # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
        conn
        |> put_flash(:error, "Email ou senha inválidos")
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/users/log-in")
    end
  end

  # Senha certa com SMTP efetivo: ainda não loga. O usuário pendente fica na sessão
  # assinada até o código ser confirmado em verify_code/2.
  defp start_two_factor(conn, user, user_params) do
    case Accounts.deliver_two_factor_code(user) do
      result when result == {:error, :cooldown} or elem(result, 0) == :ok ->
        conn
        |> put_session(:pending_2fa_user_id, user.id)
        |> put_session(:pending_2fa_remember_me, user_params["remember_me"] == "true")
        |> redirect(to: ~p"/users/log-in/code")

      {:error, _reason} ->
        conn
        |> put_flash(
          :error,
          "Não foi possível enviar o código por email. Verifique o SMTP; no servidor, `grana-disable-smtp` desliga o 2FA."
        )
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def verify_code(conn, %{"code" => code}) do
    user_id = get_session(conn, :pending_2fa_user_id)
    remember_me = get_session(conn, :pending_2fa_remember_me)

    case user_id && Accounts.get_user(user_id) do
      nil ->
        conn
        |> put_flash(:error, "Sua tentativa de login expirou. Entre novamente.")
        |> redirect(to: ~p"/users/log-in")

      user ->
        case Accounts.verify_two_factor_code(user, code) do
          :ok ->
            conn
            |> delete_session(:pending_2fa_user_id)
            |> delete_session(:pending_2fa_remember_me)
            |> put_flash(:info, "Bem vindo de volta!")
            |> UserAuth.log_in_user(user, %{"remember_me" => to_string(remember_me)})

          {:error, :invalid} ->
            conn
            |> put_flash(:error, "Código incorreto.")
            |> redirect(to: ~p"/users/log-in/code")

          {:error, reason} when reason in [:expired, :too_many_attempts] ->
            message =
              if reason == :expired,
                do: "O código expirou. Entre novamente para receber outro.",
                else: "Muitas tentativas erradas. Entre novamente para receber outro código."

            conn
            |> delete_session(:pending_2fa_user_id)
            |> delete_session(:pending_2fa_remember_me)
            |> put_flash(:error, message)
            |> redirect(to: ~p"/users/log-in")
        end
    end
  end

  def update_password(conn, %{"user" => user_params}) do
    user = conn.assigns.current_scope.user

    cond do
      not Accounts.sudo_mode?(user) ->
        conn
        |> put_flash(:error, "Sua sessão expirou. Faça login novamente para alterar a senha.")
        |> redirect(to: ~p"/users/settings")

      true ->
        case Accounts.update_user_password(user, user_params) do
          {:ok, {user, expired_tokens}} ->
            # disconnect all existing LiveViews with old sessions
            UserAuth.disconnect_sessions(expired_tokens)

            conn
            |> put_session(:user_return_to, ~p"/users/settings")
            |> put_flash(:info, "Senha atualizada com sucesso!")
            |> UserAuth.log_in_user(user, user_params)

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
