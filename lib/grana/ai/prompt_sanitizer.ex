defmodule Grana.AI.PromptSanitizer do
  @moduledoc """
  Sanitizes user-provided inputs before interpolation into AI prompts
  to mitigate prompt injection attacks.
  """

  @max_description_length 200
  @max_prompt_length 1000

  @xml_tags ~r{</?\s*(user_transactions|user_prompt|consulted_data)\s*>}i

  @doc """
  Sanitizes a transaction description: strips control characters, XML delimiters, and newlines,
  truncates to a safe length.
  """
  def sanitize_description(nil), do: ""

  def sanitize_description(desc) when is_binary(desc) do
    desc
    |> strip_control_characters()
    |> neutralize_xml_delimiters()
    |> String.replace(~r/[\r\n]+/, " ")
    |> String.trim()
    |> String.slice(0, @max_description_length)
  end

  @doc """
  Wraps a custom user prompt in XML delimiters to clearly separate it
  from system instructions.
  """
  def wrap_custom_prompt(nil), do: ""
  def wrap_custom_prompt(""), do: ""

  def wrap_custom_prompt(prompt) when is_binary(prompt) do
    sanitized =
      prompt
      |> strip_control_characters()
      |> neutralize_xml_delimiters()
      |> String.trim()
      |> String.slice(0, @max_prompt_length)

    """
    PERGUNTA/INSTRUÇÃO DO USUÁRIO (responda no campo "resposta" do JSON):
    <user_prompt>
    #{sanitized}
    </user_prompt>
    """
  end

  @doc """
  Neutralizes XML delimiters by replacing reserved tag names and converting `<>` to angle quotes.
  """
  def neutralize_xml_delimiters(text) when is_binary(text) do
    text
    |> String.replace(@xml_tags, " ")
    |> String.replace("<", "‹")
    |> String.replace(">", "›")
  end

  @doc """
  Wraps a block of transaction descriptions in XML delimiters.
  """
  def wrap_transactions(text) when is_binary(text) do
    "<user_transactions>\n#{text}\n</user_transactions>"
  end

  @doc """
  Strips control characters (except standard whitespace) from a string.
  """
  def strip_control_characters(text) when is_binary(text) do
    String.replace(text, ~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, "")
  end
end
