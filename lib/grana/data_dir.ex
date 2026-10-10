defmodule Grana.DataDir do
  @moduledoc "Diretório de dados da instância (`DATA_DIR`) e seu subdiretório de temporários."

  def path, do: Application.fetch_env!(:grana, :data_dir)

  @doc "Temporários de backup/restauração. Criado sob demanda."
  def tmp_dir do
    dir = Path.join(path(), "tmp")
    File.mkdir_p!(dir)
    dir
  end
end
