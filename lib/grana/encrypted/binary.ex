defmodule Grana.Encrypted.Binary do
  @moduledoc """
  An Ecto type that transparently encrypts/decrypts binary data
  using AES-256-GCM. Stored in the database as base64-encoded ciphertext.

  The encryption key is derived from the `CLOAK_KEY` environment variable,
  which should be a base64-encoded 32-byte key.

  Generate a key with: `:crypto.strong_rand_bytes(32) |> Base.encode64()`
  """

  use Ecto.Type

  @aad "AES256GCM"
  @iv_size 12
  @tag_size 16

  def type, do: :string

  def cast(value) when is_binary(value), do: {:ok, value}
  def cast(nil), do: {:ok, nil}
  def cast(_), do: :error

  def dump(nil), do: {:ok, nil}
  def dump(""), do: {:ok, nil}

  def dump(value) when is_binary(value) do
    key = get_key!()
    iv = :crypto.strong_rand_bytes(@iv_size)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, value, @aad, @tag_size, true)

    encoded = Base.encode64(iv <> tag <> ciphertext)
    {:ok, encoded}
  end

  def dump(_), do: :error

  def load(nil), do: {:ok, nil}

  def load(encoded) when is_binary(encoded), do: decrypt(encoded, get_key!())

  def load(_), do: :error

  defp decrypt(encoded, key) do
    with {:ok, <<iv::binary-size(@iv_size), tag::binary-size(@tag_size), ciphertext::binary>>} <-
           Base.decode64(encoded) do
      case :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, @aad, tag, false) do
        plaintext when is_binary(plaintext) -> {:ok, plaintext}
        :error -> :error
      end
    else
      _ -> :error
    end
  end

  def equal?(a, b), do: a == b

  @dev_key "uAsvYu1DjJFziFfKP1ZJyiinCOYCZD1CFb4QMGMzpZU="

  @doc """
  Verdadeiro quando a chave vem de `CLOAK_KEY` ou do arquivo de segredos gerado no boot
  e não é a chave padrão pública de desenvolvimento (`@dev_key`).
  """
  def private_key? do
    key =
      case System.get_env("CLOAK_KEY") do
        nil -> Application.get_env(:grana, :cloak_key)
        "" -> Application.get_env(:grana, :cloak_key)
        val -> val
      end

    case key do
      nil -> false
      "" -> false
      @dev_key -> false
      _custom_key -> true
    end
  end

  @doc """
  Decifra um valor guardado (base64) com a chave `old_key_b64` e o cifra de novo
  com a chave atual. `:error` se a chave antiga não decifra o valor.
  """
  def reencrypt(encoded, old_key_b64) when is_binary(encoded) and is_binary(old_key_b64) do
    with {:ok, old_key} <- Base.decode64(old_key_b64),
         32 <- byte_size(old_key),
         {:ok, plaintext} <- decrypt(encoded, old_key) do
      dump(plaintext)
    else
      _ -> :error
    end
  end

  def embed_as(_), do: :dump

  defp get_key! do
    case Application.get_env(:grana, :cloak_key) do
      nil ->
        raise """
        Encryption key not configured!
        Set the CLOAK_KEY environment variable to a base64-encoded 32-byte key.
        Generate one with: :crypto.strong_rand_bytes(32) |> Base.encode64()
        """

      key_b64 ->
        Base.decode64!(key_b64)
    end
  end
end
