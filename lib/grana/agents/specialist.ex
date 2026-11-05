defmodule Grana.Agents.Specialist do
  @moduledoc """
  Contract of an AI specialist: a reasoning engine with its own prompt, tools and default
  model (`Grana.AI.resolve/3` with `key/0`). Screens call a specialist directly with an
  explicit intent; the chat coordinator reaches the ones that implement `tool/1`.
  """

  @callback key() :: String.t()

  @doc "The specialist as a tool for the chat coordinator. `context` carries `:user_id`."
  @callback tool(context :: map()) :: LangChain.Function.t()

  @optional_callbacks tool: 1
end
