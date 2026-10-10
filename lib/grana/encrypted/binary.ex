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

  def load(encoded) when is_binary(encoded) do
    key = get_key!()

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

  def load(_), do: :error

  def equal?(a, b), do: a == b

  @doc """
  Verdadeiro quando a chave vem de `CLOAK_KEY`. Sem ela, dev/test usam a chave
  fixa de `config/*.exs` — pública no repositório, então não protege nada.
  """
  def private_key?, do: System.get_env("CLOAK_KEY") not in [nil, ""]

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
