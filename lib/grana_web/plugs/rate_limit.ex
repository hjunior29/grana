defmodule GranaWeb.RateLimit do
  @moduledoc """
  Rate limiting for auth endpoints using Hammer.

  Provides both a Plug for controller routes and a helper function
  for LiveView handle_event callbacks.

  Rate limits:
  - `:login` - 5 requests per minute per IP
  - `:magic_link` - 3 requests per minute per IP
  - `:registration` - 3 requests per minute per IP
  """

  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]

  @rate_limits %{
    login: {5, 60_000},
    magic_link: {3, 60_000},
    registration: {3, 60_000}
  }

  # --- Plug interface (for controller routes) ---

  def init(opts), do: opts

  def call(conn, opts) do
    action = Keyword.fetch!(opts, :action)

    remote_ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    case check(action, remote_ip) do
      :allow ->
        conn

      :deny ->
        conn
        |> put_flash(:error, "Muitas tentativas. Aguarde um momento antes de tentar novamente.")
        |> redirect(to: redirect_path(action))
        |> halt()
    end
  end

  # --- LiveView helper ---

  @doc """
  Checks the rate limit for a LiveView action.

  Returns `:allow` or `:deny`.

  The IP is extracted from `socket.assigns` peer data via `get_connect_info`.
  Pass the IP as a string.

  ## Example

      case GranaWeb.RateLimit.check(:magic_link, ip) do
        :allow -> # proceed
        :deny -> {:noreply, put_flash(socket, :error, "Too many attempts.")}
      end
  """
  @skip_rate_limit Application.compile_env(:grana, :skip_rate_limit, false)

  @spec check(atom(), String.t()) :: :allow | :deny
  def check(action, ip) do
    if @skip_rate_limit do
      :allow
    else
      {limit, window_ms} = Map.fetch!(@rate_limits, action)
      bucket_key = "#{action}:#{ip}"

      case Hammer.check_rate(bucket_key, window_ms, limit) do
        {:allow, _count} -> :allow
        {:deny, _limit} -> :deny
        {:error, _reason} -> :allow
      end
    end
  end

  @doc """
  Extracts the client IP from a LiveView socket as a string.

  Requires `connect_info: [:peer_data]` in the socket configuration,
  or falls back to "unknown".
  """
  @spec get_ip(Phoenix.LiveView.Socket.t()) :: String.t()
  def get_ip(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
      %{address: ip} -> ip |> :inet.ntoa() |> to_string()
      _ -> "unknown"
    end
  end

  defp redirect_path(:login), do: "/users/log-in"
  defp redirect_path(:magic_link), do: "/users/log-in"
  defp redirect_path(:registration), do: "/users/register"
end
