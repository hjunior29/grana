defmodule Grana.Diagnostics do
  @moduledoc "Resumo técnico da instância para a seção Diagnóstico de Configurações."

  alias Grana.{Accounts, DataDir, OpenFinance, Repo}
  alias Grana.Accounts.Scope

  def summary(%Accounts.User{} = user) do
    %{
      version: to_string(Application.spec(:grana, :vsn)),
      data_dir: DataDir.path(),
      database_size: database_size(),
      credentials: [
        {"Chave do Gemini", ai_source(user)},
        {"Pluggy (Open Finance)", OpenFinance.credentials_source(Scope.for_user(user))},
        {"Email (SMTP)", Accounts.smtp_source()}
      ]
    }
  end

  defp ai_source(user) do
    cond do
      Accounts.env_ai_api_key() -> :env
      user.ai_api_key -> :database
      true -> nil
    end
  end

  defp database_size do
    path = Repo.config()[:database]

    case File.stat(path) do
      {:ok, %{size: size}} -> size
      {:error, _} -> nil
    end
  end

  @doc "Tamanho legível (`3,4 MB`)."
  def format_bytes(nil), do: "—"
  def format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"

  def format_bytes(bytes) do
    {value, unit} =
      cond do
        bytes < 1024 * 1024 -> {bytes / 1024, "KB"}
        bytes < 1024 * 1024 * 1024 -> {bytes / (1024 * 1024), "MB"}
        true -> {bytes / (1024 * 1024 * 1024), "GB"}
      end

    value |> Float.round(1) |> to_string() |> String.replace(".", ",") |> Kernel.<>(" #{unit}")
  end
end
