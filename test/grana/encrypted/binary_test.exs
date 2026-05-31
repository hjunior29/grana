defmodule Grana.Encrypted.BinaryTest do
  use ExUnit.Case, async: true

  alias Grana.Encrypted.Binary

  describe "cast/1" do
    test "passa binários e nil adiante, rejeita o resto" do
      assert Binary.cast("abc") == {:ok, "abc"}
      assert Binary.cast(nil) == {:ok, nil}
      assert Binary.cast(123) == :error
    end
  end

  describe "dump/1 + load/1 (roundtrip AES-256-GCM)" do
    test "cifra e decifra de volta o texto original" do
      assert {:ok, ciphertext} = Binary.dump("minha-api-key-secreta")
      assert is_binary(ciphertext)
      refute ciphertext == "minha-api-key-secreta"
      assert {:ok, "minha-api-key-secreta"} == Binary.load(ciphertext)
    end

    test "nil e string vazia viram nil" do
      assert Binary.dump(nil) == {:ok, nil}
      assert Binary.dump("") == {:ok, nil}
      assert Binary.load(nil) == {:ok, nil}
    end

    test "IV aleatório: dois dumps diferem, mas ambos decifram igual" do
      assert {:ok, c1} = Binary.dump("x")
      assert {:ok, c2} = Binary.dump("x")
      refute c1 == c2
      assert Binary.load(c1) == {:ok, "x"}
      assert Binary.load(c2) == {:ok, "x"}
    end
  end

  describe "load/1 falha com entrada inválida/adulterada" do
    test "base64 inválido ou curto demais" do
      assert Binary.load("não é base64 @@@") == :error
      assert Binary.load(Base.encode64("curto")) == :error
    end

    test "ciphertext adulterado falha na verificação GCM" do
      assert {:ok, c} = Binary.dump("segredo")
      raw = Base.decode64!(c)
      last = :binary.last(raw)
      tampered = binary_part(raw, 0, byte_size(raw) - 1) <> <<rem(last + 1, 256)>>
      assert Binary.load(Base.encode64(tampered)) == :error
    end
  end
end
