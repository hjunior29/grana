defmodule Grana.Setup do
  @moduledoc """
  Código de uso único do assistente de setup. Fica só em memória e é impresso no
  log: quem consegue lê-lo tem acesso ao servidor. Um novo boot gera um novo
  código; ele morre quando o dono é criado.
  """

  use Agent

  require Logger

  @alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

  def start_link(_opts) do
    Agent.start_link(fn -> nil end, name: __MODULE__)
  end

  @doc "Gera um código novo e o imprime no log."
  def generate_code do
    code = random_code()
    Agent.update(__MODULE__, fn _ -> code end)
    announce(code)
    code
  end

  @doc "Gera o código se a instância ainda não tem dono."
  def announce_if_setup_required do
    if Grana.Accounts.setup_required?(), do: generate_code()
  end

  def clear_code, do: Agent.update(__MODULE__, fn _ -> nil end)

  def verify_code(input) when is_binary(input) do
    case Agent.get(__MODULE__, & &1) do
      nil -> false
      code -> Plug.Crypto.secure_compare(normalize(input), normalize(code))
    end
  end

  def verify_code(_), do: false

  defp normalize(code), do: code |> String.upcase() |> String.replace(~r/[^A-Z0-9]/, "")

  defp random_code do
    chars =
      for <<byte <- :crypto.strong_rand_bytes(8)>>,
        do: Enum.at(@alphabet, rem(byte, length(@alphabet)))

    {a, b} = Enum.split(chars, 4)
    "#{a}-#{b}"
  end

  defp announce(code) do
    url = Grana.Accounts.public_base_url() <> "/setup"

    Logger.notice("""

    ============================================================
      GRANA — configuração inicial
      Abra:   #{url}
      Código: #{code}
      (uso único; para ver de novo: journalctl -u grana | grep Código
       ou docker logs grana)
    ============================================================
    """)
  end
end
