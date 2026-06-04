defmodule Grana.Cache do
  @moduledoc """
  Cache de leituras pesadas (agregações de dashboard/análise/investimentos e
  listas paginadas) com Redis via Redix — Upstash gerenciado do Fly em produção,
  container local em dev (`make redis.up`).

  ## Como funciona ("cache inteligente")

    * `get_or_store/4` cacheia o resultado de uma leitura por **(usuário, namespace,
      filtros)**. Os filtros viram um hash SHA-256 determinístico, então cada
      combinação de filtro tem sua própria entrada — é o "salve o hash e o valor".
    * O valor é serializado com `:erlang.term_to_binary/1`, preservando `Decimal`,
      `Date` e structs do Ecto (JSON perderia precisão e tipos).
    * Cada chave é registrada num **índice por usuário** (um Set Redis), de modo
      que `invalidate_user/1` apaga TODAS as entradas daquele usuário de uma vez.
    * `invalidate_user/1` é chamado em QUALQUER escrita/upload que afete os dados
      cacheados (ver `Grana.Banking` e `Grana.Investments`). É a garantia de
      frescor; o TTL é só um teto de validade.

  ## TTL

  Default 300s (`:ttl_seconds`), a janela de ociosidade após a qual o Fly derruba
  a máquina (`auto_stop_machines`). Ajustável por `CACHE_TTL_SECONDS`.

  ## Degradação graciosa

  Se o cache estiver desligado (test, ou sem `REDIS_URL`) ou o Redis indisponível,
  `get_or_store/4` simplesmente executa a função e devolve o resultado, e
  `invalidate_user/1` é no-op. Nenhum erro de Redis jamais quebra o caller —
  a aplicação funciona normalmente sem Redis, apenas sem cache.
  """

  require Logger

  @conn __MODULE__.Redix

  @doc """
  Child spec da conexão Redix para a árvore de supervisão, ou `nil` quando o
  cache está desligado/sem URL (nesse caso nada é iniciado).
  """
  def child_spec_or_nil do
    cfg = config()

    if cfg[:enabled] && cfg[:url] do
      %{
        id: @conn,
        start: {Redix, :start_link, [cfg[:url], [name: @conn, sync_connect: false]]}
      }
    end
  end

  @doc "Verdadeiro quando o cache está habilitado e configurado com uma URL."
  def enabled? do
    cfg = config()
    cfg[:enabled] == true and not is_nil(cfg[:url])
  end

  @doc """
  Devolve o valor cacheado para `(namespace, user_id, filters)` ou computa com
  `fun`, guarda e devolve. Cai no `fun.()` direto se o cache estiver desligado ou
  o Redis indisponível.
  """
  @spec get_or_store(String.t(), integer(), term(), (-> result)) :: result when result: var
  def get_or_store(namespace, user_id, filters, fun)
      when is_binary(namespace) and is_function(fun, 0) do
    if enabled?() do
      key = build_key(namespace, user_id, filters)

      case do_get(key) do
        {:ok, value} ->
          value

        :miss ->
          value = fun.()
          do_put(key, user_id, value)
          value

        :error ->
          fun.()
      end
    else
      fun.()
    end
  end

  @doc """
  Apaga todas as entradas de cache do usuário. Chamado em toda escrita/upload que
  afete os dados cacheados. Nunca levanta erro (falha de Redis vira no-op + log).
  """
  @spec invalidate_user(integer() | nil) :: :ok
  def invalidate_user(user_id) when is_integer(user_id) do
    if enabled?() do
      idx = index_key(user_id)

      safe(fn ->
        case Redix.command(@conn, ["SMEMBERS", idx]) do
          {:ok, []} ->
            Redix.command(@conn, ["DEL", idx])

          {:ok, keys} when is_list(keys) ->
            Redix.pipeline(@conn, [["DEL" | keys], ["DEL", idx]])

          _ ->
            :ok
        end
      end)
    end

    :ok
  end

  def invalidate_user(_), do: :ok

  # ── internals ──────────────────────────────────────────────────────────────

  defp do_get(key) do
    safe_result(fn ->
      case Redix.command(@conn, ["GET", key]) do
        {:ok, nil} ->
          :miss

        {:ok, bin} when is_binary(bin) ->
          try do
            {:ok, :erlang.binary_to_term(bin, [:safe])}
          rescue
            # Payload corrompido/incompatível: trata como miss (recomputa).
            _ -> :miss
          end

        {:error, _} ->
          :error
      end
    end)
  end

  defp do_put(key, user_id, value) do
    bin = :erlang.term_to_binary(value)
    ttl = ttl_seconds()
    idx = index_key(user_id)

    safe(fn ->
      Redix.pipeline(@conn, [
        ["SET", key, bin, "EX", Integer.to_string(ttl)],
        ["SADD", idx, key],
        # O índice sobrevive um pouco além das entradas, para invalidação confiável.
        ["EXPIRE", idx, Integer.to_string(ttl + 120)]
      ])
    end)
  end

  # Chave: grana:cache:u<user_id>:<namespace>:<sha256 dos filtros>
  defp build_key(namespace, user_id, filters) do
    hash =
      filters
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    "#{prefix()}:u#{user_id}:#{namespace}:#{hash}"
  end

  defp index_key(user_id), do: "#{prefix()}:idx:u#{user_id}"

  defp config, do: Application.get_env(:grana, __MODULE__, [])
  defp prefix, do: config()[:namespace] || "grana:cache"
  defp ttl_seconds, do: config()[:ttl_seconds] || 300

  # Executa `fun` engolindo qualquer erro de Redis/conexão (inclusive :noproc se a
  # conexão não estiver de pé), garantindo que o cache nunca quebre o caller.
  defp safe(fun) do
    fun.()
    :ok
  rescue
    e ->
      Logger.warning("Grana.Cache: erro ignorado (#{Exception.message(e)})")
      :ok
  catch
    kind, reason ->
      Logger.warning("Grana.Cache: erro ignorado (#{inspect(kind)} #{inspect(reason)})")
      :ok
  end

  # Como `safe/1`, mas devolve o valor de `fun` ou `:error` em caso de falha.
  defp safe_result(fun) do
    fun.()
  rescue
    _ -> :error
  catch
    _kind, _reason -> :error
  end
end
