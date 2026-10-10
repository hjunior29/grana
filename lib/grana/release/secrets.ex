defmodule Grana.Release.Secrets do
  @moduledoc """
  Segredos de boot (`SECRET_KEY_BASE`, `CLOAK_KEY`) gerados no primeiro boot e
  guardados em `<dir>/<nome>` com permissão 600. O ambiente sobrescreve.
  """

  require Logger

  @sizes %{secret_key_base: 64, cloak_key: 32}

  @spec load_or_generate(Path.t(), :secret_key_base | :cloak_key) :: String.t()
  def load_or_generate(dir, name) when is_map_key(@sizes, name) do
    path = Path.join(dir, Atom.to_string(name))

    case File.read(path) do
      {:ok, content} when content != "" ->
        String.trim(content)

      _ ->
        File.mkdir_p!(dir)
        File.chmod!(dir, 0o700)
        secret = @sizes[name] |> :crypto.strong_rand_bytes() |> Base.encode64()
        File.write!(path, secret)
        File.chmod!(path, 0o600)
        Logger.info("Segredo #{name} gerado e salvo em #{path}")
        secret
    end
  end
end
