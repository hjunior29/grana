defmodule Grana.Cache do
  @moduledoc """
  Cache em memória de leituras pesadas (agregações de dashboard/análise/investimentos e
  listas paginadas) backed por Cachex (ETS).

  ## Como funciona ("cache inteligente")

    * `get_or_store/4` cacheia o resultado de uma leitura por **(usuário, namespace,
      filtros)**. Os filtros viram um hash SHA-256 determinístico, então cada
      combinação de filtro tem sua própria entrada.
    * O valor é armazenado diretamente como termo Elixir na memória (ETS), preservando
      `Decimal`, `Date` e structs do Ecto com latência em sub-milissegundos.
    * Cada chave é registrada num índice por usuário (um MapSet armazenado no Cachex),
      de modo que `invalidate_user/1` apaga todas as entradas daquele usuário de uma vez.
    * `invalidate_user/1` é chamado em qualquer escrita/upload que afete os dados
      cacheados (ver `Grana.Banking`). É a garantia de
      frescor; o TTL é só um teto de validade.

  ## TTL

  Default 300s (`:ttl_seconds`). Ajustável por `CACHE_TTL_SECONDS`.

  ## Degradação graciosa

  Se o cache estiver desligado (ex.: ambiente de test) ou ocorrer qualquer erro inesperado,
  `get_or_store/4` executa a função de consulta e devolve o resultado diretamente, e
  `invalidate_user/1` é no-op.
  """

  require Logger

  @cache_name __MODULE__

  @doc """
  Child spec do Cachex para a árvore de supervisão, ou `nil` quando o
  cache está desligado.
  """
  def child_spec_or_nil do
    if enabled?() do
      Cachex.child_spec(name: @cache_name)
    end
  end

  @doc "Nome do cache no Cachex."
  def cache_name, do: @cache_name

  @doc "Verdadeiro quando o cache está habilitado."
  def enabled? do
    config()[:enabled] == true
  end

  @doc """
  Devolve o valor cacheado para `(namespace, user_id, filters)` ou computa com
  `fun`, guarda e devolve. Cai no `fun.()` direto se o cache estiver desligado.

  Opções:

    * `:ttl_seconds` - validade desta entrada (padrão: a configurada).
    * `:cache_if` - função que decide se o resultado entra no cache (padrão: sempre);
      útil para não guardar erros.
  """
  @spec get_or_store(String.t(), integer(), term(), (-> result), keyword()) :: result
        when result: var
  def get_or_store(namespace, user_id, filters, fun, opts \\ [])
      when is_binary(namespace) and is_function(fun, 0) do
    if enabled?() do
      key = build_key(namespace, user_id, filters)

      case do_get(key) do
        {:ok, value} ->
          value

        :miss ->
          value = fun.()
          if cache?(value, opts), do: do_put(key, user_id, value, opts[:ttl_seconds])
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
  afete os dados cacheados.
  """
  @spec invalidate_user(integer() | nil) :: :ok
  def invalidate_user(user_id) when is_integer(user_id) do
    if enabled?() do
      idx = index_key(user_id)

      safe(fn ->
        case Cachex.take(@cache_name, idx) do
          {:ok, keys} when is_struct(keys, MapSet) ->
            Enum.each(keys, &Cachex.del(@cache_name, &1))

          _ ->
            :ok
        end
      end)
    end

    :ok
  end

  def invalidate_user(_), do: :ok

  @doc "Esvazia o cache inteiro (restaurar backup, apagar tudo)."
  @spec clear_all() :: :ok
  def clear_all do
    if enabled?(), do: safe(fn -> Cachex.clear(@cache_name) end)
    :ok
  end

  # ── internals ──────────────────────────────────────────────────────────────

  defp do_get(key) do
    safe_result(fn ->
      case Cachex.get(@cache_name, key) do
        {:ok, {:cached, value}} ->
          {:ok, value}

        {:ok, nil} ->
          :miss

        {:error, _} ->
          :error
      end
    end)
  end

  defp cache?(value, opts), do: Keyword.get(opts, :cache_if, fn _ -> true end).(value)

  defp do_put(key, user_id, value, ttl) do
    ttl_ms = (ttl || ttl_seconds()) * 1000
    idx = index_key(user_id)

    safe(fn ->
      Cachex.put(@cache_name, key, {:cached, value}, expire: ttl_ms)

      # Registra a chave no índice do usuário de forma atômica
      Cachex.get_and_update(@cache_name, idx, fn
        nil ->
          {:commit, MapSet.new([key]), expire: ttl_ms + 120_000}

        %MapSet{} = set ->
          {:commit, MapSet.put(set, key), expire: ttl_ms + 120_000}

        _other ->
          {:commit, MapSet.new([key]), expire: ttl_ms + 120_000}
      end)
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

  defp safe_result(fun) do
    fun.()
  rescue
    _ -> :error
  catch
    _kind, _reason -> :error
  end
end
