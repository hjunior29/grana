defmodule Grana.Banking.TransferIdentity do
  @moduledoc """
  Heurísticas para reconhecer transferências entre contas do próprio titular e
  extrair a contraparte de uma descrição de transferência (PIX/TED/DOC).

  Formatos reais observados:

      "Transferência enviada pelo Pix - <NOME> - •••.022.012-•• - <BANCO> (0260) Agência: 1 Conta: ..."
      "Transferência Recebida - <NOME> - •••.022.012-•• - ..."
      "TRANSFERENCIA PIX - <NOME>"            (Bradesco, sem CPF)
      "Transferência enviada pelo Pix - ICATU SEGUROS"   (empresa, sem CPF)

  O CPF vem **mascarado**: só os 6 dígitos do meio aparecem (`•••.022.012-••`),
  que correspondem às posições 4–9 do CPF completo.
  """

  @transfer_words ~w(pix transferencia ted doc)

  @doc "Minúsculas, sem acento, espaços colapsados."
  def normalize(nil), do: ""

  def normalize(text) do
    text
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[\x{0300}-\x{036f}]/u, "")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  @doc "A descrição é de uma transferência (PIX/TED/DOC/transferência)?"
  def transfer?(description) do
    n = normalize(description)
    Enum.any?(@transfer_words, &String.contains?(n, &1))
  end

  @doc "Os 6 dígitos visíveis do CPF mascarado na descrição, ou nil."
  def cpf6(description) do
    case Regex.run(~r/\.(\d{3})\.(\d{3})-/, description || "") do
      [_, a, b] -> a <> b
      _ -> nil
    end
  end

  @doc "Os 6 dígitos do meio (posições 4–9) de um CPF completo, ou nil."
  def cpf_middle(cpf) when is_binary(cpf) do
    digits = String.replace(cpf, ~r/\D/, "")
    if String.length(digits) == 11, do: String.slice(digits, 3, 6)
  end

  def cpf_middle(_), do: nil

  @doc "Nome da contraparte extraído da descrição (normalizado), ou nil."
  def counterparty_name(description) do
    (description || "")
    |> String.split(" - ")
    |> Enum.map(&String.trim/1)
    |> name_after_transfer_segment()
  end

  @doc """
  A descrição se refere ao próprio titular? Verdadeiro se o CPF do meio bate ou
  se o nome completo do titular (≥ 2 tokens) aparece como sequência na descrição.
  """
  def own_identity?(description, user_name, user_cpf) do
    cpf_match?(description, user_cpf) or name_match?(description, user_name)
  end

  @doc """
  Chave única (mais específica) para aprender/casar uma regra desta descrição:
  `cpf:<6 dígitos>` quando há CPF, senão `name:<nome>`, senão nil.
  """
  def rule_key(description) do
    cond do
      cpf6(description) -> "cpf:" <> cpf6(description)
      counterparty_name(description) -> "name:" <> counterparty_name(description)
      true -> nil
    end
  end

  @doc "Todas as chaves candidatas desta descrição (cpf e nome), para casar regras."
  def rule_keys(description) do
    [
      cpf6(description) && "cpf:" <> cpf6(description),
      counterparty_name(description) && "name:" <> counterparty_name(description)
    ]
    |> Enum.reject(&is_nil/1)
  end

  # ── internals ──

  defp name_after_transfer_segment(segments) do
    idx =
      Enum.find_index(segments, fn seg ->
        n = normalize(seg)
        Enum.any?(@transfer_words, &String.contains?(n, &1))
      end)

    with i when is_integer(i) <- idx,
         seg when is_binary(seg) <- Enum.at(segments, i + 1),
         false <- seg == "" or String.contains?(seg, "•") do
      normalize(seg)
    else
      _ -> nil
    end
  end

  defp cpf_match?(_description, cpf) when cpf in [nil, ""], do: false

  defp cpf_match?(description, cpf) do
    mid = cpf_middle(cpf)
    mid != nil and cpf6(description) == mid
  end

  defp name_match?(_description, name) when name in [nil, ""], do: false

  defp name_match?(description, name) do
    name_tokens = name |> normalize() |> String.split(" ", trim: true)
    length(name_tokens) >= 2 and sublist?(tokens(description), name_tokens)
  end

  defp tokens(description), do: description |> normalize() |> String.split(" ", trim: true)

  # `sub` aparece como sequência contígua em `list`?
  defp sublist?(list, sub) do
    len = length(sub)

    list
    |> Enum.chunk_every(len, 1, :discard)
    |> Enum.any?(&(&1 == sub))
  end
end
