defmodule GranaWeb.Params do
  @moduledoc """
  Helpers para lidar com parâmetros vindos do cliente (URL / phx-value) de forma
  segura, sem derrubar a LiveView com `String.to_integer/1` em entrada malformada.
  """

  @doc """
  Converte um valor em inteiro; retorna `default` se não for um inteiro válido.

  Para lookups por id, use `default: -1` (ou outro id impossível): um id forjado
  cai no mesmo caminho de "não encontrado" de um id inexistente, em vez de crashar.
  """
  @spec to_int(any(), integer() | nil) :: integer() | nil
  def to_int(value, default \\ nil)
  def to_int(value, _default) when is_integer(value), do: value

  def to_int(value, default) do
    case value |> to_string() |> Integer.parse() do
      {n, _} -> n
      :error -> default
    end
  end
end
