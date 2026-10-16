defmodule GranaWeb.RateLimit do
  @moduledoc """
  Rate limiting for auth endpoints using Hammer.

  Provides both a Plug for controller routes and a helper function
  for LiveView handle_event callbacks.

  Rate limits:
  - `:login` - 5 requests per minute per IP
  - `:setup_code` - 5 requests per minute per IP
  - `:two_factor` - 10 requests per minute per IP
  - `:password_reset` - 3 requests per minute per IP
  """

  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]

  @rate_limits %{
    login: {5, 60_000},
    setup_code: {5, 60_000},
    two_factor: {10, 60_000},
    password_reset: {3, 60_000}
  }

  # --- Plug interface (for controller routes) ---

  def init(opts), do: opts

  def call(conn, opts) do
    action = Keyword.fetch!(opts, :action)

    case check(action, client_ip(conn)) do
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

      case GranaWeb.RateLimit.check(:setup_code, ip) do
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
  Direct rate check against an arbitrary bucket key with window in milliseconds and limit.
  """
  @spec check_rate(String.t(), pos_integer(), pos_integer()) :: :allow | :deny
  def check_rate(bucket_key, window_ms, limit) do
    if @skip_rate_limit do
      :allow
    else
      case Hammer.check_rate(bucket_key, window_ms, limit) do
        {:allow, _count} -> :allow
        {:deny, _limit} -> :deny
        {:error, _reason} -> :allow
      end
    end
  end

  @doc """
  IP do cliente do socket LiveView: `peer_data`, ou o último IP de
  X-Forwarded-For quando `TRUST_PROXY_HEADERS=true` (instância atrás de proxy).
  """
  @spec get_ip(Phoenix.LiveView.Socket.t()) :: String.t()
  def get_ip(socket) do
    headers = Phoenix.LiveView.get_connect_info(socket, :x_headers) || []
    xff = for {"x-forwarded-for", v} <- headers, do: v

    forwarded_ip(xff) ||
      case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
        %{address: ip} -> ip |> :inet.ntoa() |> to_string()
        _ -> "unknown"
      end
  end

  @doc """
  IP do cliente para requests de controller: `remote_ip`, ou o último IP de
  X-Forwarded-For quando `TRUST_PROXY_HEADERS=true`.
  """
  def client_ip(conn) do
    forwarded_ip(get_req_header(conn, "x-forwarded-for")) ||
      conn.remote_ip |> :inet.ntoa() |> to_string()
  end

  defp forwarded_ip(values) do
    if Application.get_env(:grana, :trust_proxy_headers, false), do: xff_last(values)
  end

  # Último IP de uma lista X-Forwarded-For (o appendado pelo proxy).
  defp xff_last([_ | _] = values) do
    values
    |> List.last()
    |> String.split(",")
    |> List.last()
    |> to_string()
    |> String.trim()
    |> presence()
  end

  defp xff_last(_), do: nil

  defp presence(""), do: nil
  defp presence(s), do: s

  defp redirect_path(:login), do: "/users/log-in"
  defp redirect_path(:setup_code), do: "/setup"
  defp redirect_path(:two_factor), do: "/users/log-in/code"
end
