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

    case check(action, conn_ip(conn)) do
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
  Extracts the client IP do socket LiveView. Atrás do proxy do Fly, usa o último
  IP de X-Forwarded-For (o que o proxy anexa = cliente real) via connect_info
  :x_headers; cai para peer_data quando não há proxy (dev/local).
  """
  @spec get_ip(Phoenix.LiveView.Socket.t()) :: String.t()
  def get_ip(socket) do
    headers = Phoenix.LiveView.get_connect_info(socket, :x_headers) || []
    xff = for {"x-forwarded-for", v} <- headers, do: v

    case xff_last(xff) do
      nil ->
        case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
          %{address: ip} -> ip |> :inet.ntoa() |> to_string()
          _ -> "unknown"
        end

      ip ->
        ip
    end
  end

  # IP do cliente para requests de controller. Prefere Fly-Client-IP (setado e
  # não-spoofável atrás do proxy do Fly); senão o último IP de X-Forwarded-For;
  # senão o remote_ip (dev/local).
  defp conn_ip(conn) do
    case get_req_header(conn, "fly-client-ip") do
      [ip | _] when is_binary(ip) and ip != "" ->
        ip

      _ ->
        xff_last(get_req_header(conn, "x-forwarded-for")) ||
          conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  # Último IP de uma lista X-Forwarded-For (o appendado pelo proxy de borda).
  defp xff_last([value | _]) when is_binary(value) do
    value |> String.split(",") |> List.last() |> to_string() |> String.trim() |> presence()
  end

  defp xff_last(_), do: nil

  defp presence(""), do: nil
  defp presence(s), do: s

  defp redirect_path(:login), do: "/users/log-in"
  defp redirect_path(:magic_link), do: "/users/log-in"
  defp redirect_path(:registration), do: "/users/register"
end
