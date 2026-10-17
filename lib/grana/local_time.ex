defmodule Grana.LocalTime do
  @moduledoc """
  Fornece a data/hora local de Brasília (UTC-3, sem horário de verão).
  """

  @brt_offset_hours -3

  @doc "Data de hoje no fuso horário local (Brasília, UTC-3)."
  def today do
    DateTime.utc_now()
    |> DateTime.add(@brt_offset_hours, :hour)
    |> DateTime.to_date()
  end
end
