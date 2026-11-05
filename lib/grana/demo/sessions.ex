defmodule Grana.Demo.Sessions do
  @moduledoc """
  Dona da tabela ETS com as preferências de cada visitante da demonstração
  (`Grana.Demo.put_session_preferences/3`). Some com o processo, como a conta, a cada boot.
  """

  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    :ets.new(__MODULE__, [:named_table, :public, :set, read_concurrency: true])
    {:ok, nil}
  end
end
