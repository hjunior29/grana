defmodule Grana.CacheTest do
  use ExUnit.Case, async: false

  alias Grana.Cache

  setup do
    start_supervised!({Cachex, name: Cache.cache_name()})
    Application.put_env(:grana, Cache, enabled: true, ttl_seconds: 300)

    on_exit(fn ->
      Application.put_env(:grana, Cache, enabled: false)
    end)

    :ok
  end

  describe "get_or_store/4" do
    test "computes and caches value on miss, returns cached value on hit" do
      user_id = 1
      test_pid = self()

      compute_fn = fn ->
        send(test_pid, :computed)
        %{total: Decimal.new("150.00")}
      end

      # 1st call: miss -> computes
      val1 = Cache.get_or_store("test:ns", user_id, [a: 1], compute_fn)
      assert val1 == %{total: Decimal.new("150.00")}
      assert_received :computed

      # 2nd call: hit -> returns cached, function not called
      val2 = Cache.get_or_store("test:ns", user_id, [a: 1], compute_fn)
      assert val2 == %{total: Decimal.new("150.00")}
      refute_received :computed
    end

    test "isolates different users and different filter options" do
      compute_1 = fn -> "user1_filterA" end
      compute_2 = fn -> "user1_filterB" end
      compute_3 = fn -> "user2_filterA" end

      assert Cache.get_or_store("ns", 1, %{opt: "A"}, compute_1) == "user1_filterA"
      assert Cache.get_or_store("ns", 1, %{opt: "B"}, compute_2) == "user1_filterB"
      assert Cache.get_or_store("ns", 2, %{opt: "A"}, compute_3) == "user2_filterA"
    end

    test "safely handles nil values" do
      call_count = :atomics.new(1, [])

      compute_nil = fn ->
        :atomics.add(call_count, 1, 1)
        nil
      end

      assert Cache.get_or_store("nil_ns", 10, [], compute_nil) == nil
      assert Cache.get_or_store("nil_ns", 10, [], compute_nil) == nil

      # Valida que o nil foi retornado do cache e não recomputou
      assert :atomics.get(call_count, 1) == 1
    end
  end

  describe "invalidate_user/1" do
    test "invalidates all cache keys for the given user without affecting other users" do
      test_pid = self()

      Cache.get_or_store("ns1", 100, [], fn -> "u100_v1" end)
      Cache.get_or_store("ns2", 100, [filter: :x], fn -> "u100_v2" end)
      Cache.get_or_store("ns1", 200, [], fn -> "u200_v1" end)

      # Invalida apenas o usuário 100
      assert Cache.invalidate_user(100) == :ok

      # Usuário 100 deve recomputar
      new_val =
        Cache.get_or_store("ns1", 100, [], fn ->
          send(test_pid, :recomputed_100)
          "u100_v1_new"
        end)

      assert new_val == "u100_v1_new"
      assert_received :recomputed_100

      # Usuário 200 ainda está em cache (não recomputa)
      cached_200 =
        Cache.get_or_store("ns1", 200, [], fn ->
          send(test_pid, :recomputed_200)
          "u200_v1_new"
        end)

      assert cached_200 == "u200_v1"
      refute_received :recomputed_200
    end

    test "handles nil and non-integer gracefully" do
      assert Cache.invalidate_user(nil) == :ok
      assert Cache.invalidate_user("invalid") == :ok
    end
  end

  describe "graceful degradation when disabled" do
    test "always executes function without caching when disabled" do
      Application.put_env(:grana, Cache, enabled: false)

      test_pid = self()

      fun = fn ->
        send(test_pid, :called)
        "val"
      end

      assert Cache.get_or_store("ns", 1, [], fun) == "val"
      assert_received :called

      assert Cache.get_or_store("ns", 1, [], fun) == "val"
      assert_received :called
    end
  end
end
