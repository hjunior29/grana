defmodule Grana.Demo.Boot do
  @moduledoc """
  Recria a demonstração no boot (`Grana.Demo.reset!/0`), antes do endpoint: a primeira
  requisição já encontra a conta com os dados de base. Não deixa processo vivo.
  """

  def child_spec(_opts),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, []}, restart: :temporary}

  def start_link do
    Grana.Demo.reset!()
    :ignore
  end
end
