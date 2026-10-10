defmodule Grana.Release.SecretsTest do
  use ExUnit.Case, async: true

  alias Grana.Release.Secrets

  @moduletag :tmp_dir

  test "gera, grava com permissão 600 e reaproveita no segundo boot", %{tmp_dir: dir} do
    dir = Path.join(dir, "secrets")

    first = Secrets.load_or_generate(dir, :cloak_key)
    assert {:ok, key} = Base.decode64(first)
    assert byte_size(key) == 32

    path = Path.join(dir, "cloak_key")
    assert File.stat!(path).mode |> Bitwise.band(0o777) == 0o600
    assert Secrets.load_or_generate(dir, :cloak_key) == first
  end

  test "secret_key_base tem 64 bytes e é independente da cloak_key", %{tmp_dir: dir} do
    skb = Secrets.load_or_generate(dir, :secret_key_base)
    assert byte_size(Base.decode64!(skb)) == 64
    refute skb == Secrets.load_or_generate(dir, :cloak_key)
  end

  test "arquivo vazio é regenerado", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "cloak_key"), "")
    assert Secrets.load_or_generate(dir, :cloak_key) != ""
  end
end
