defmodule Grana.Banking.Parsers.PdfText do
  @moduledoc """
  Extrai a camada de texto de um PDF de forma **determinística**, usando o
  `pdftotext` (poppler) com a flag `-layout`, que preserva o alinhamento das
  colunas — essencial para parsear extratos em formato de tabela.

  Não envolve IA: o texto extraído é exatamente o que está embutido no PDF.

  Retorna:
    * `{:ok, texto}` quando o PDF tem camada de texto;
    * `{:error, :no_text_layer}` para PDFs escaneados (imagem, sem texto);
    * `{:error, :pdftotext_unavailable}` quando o binário não está instalado;
    * `{:error, :pdftotext_failed}` para qualquer outra falha do `pdftotext`.

  Esses erros permitem que o chamador faça fallback para a extração via IA.
  """

  require Logger

  alias Grana.DataDir

  @timeout_ms 60_000

  @doc """
  Recebe os bytes brutos do PDF e devolve `{:ok, texto}` ou `{:error, motivo}`.
  """
  def extract(pdf_bytes) when is_binary(pdf_bytes) do
    case System.find_executable("pdftotext") do
      nil ->
        {:error, :pdftotext_unavailable}

      exe ->
        with {:ok, path} <- write_temp(pdf_bytes) do
          try do
            task =
              Task.Supervisor.async_nolink(Grana.TaskSupervisor, fn ->
                run(exe, path)
              end)

            case Task.yield(task, @timeout_ms) || Task.shutdown(task, :brutal_kill) do
              {:ok, result} ->
                result

              nil ->
                Logger.warning("pdftotext excedeu o tempo limite de #{@timeout_ms}ms")
                {:error, :pdftotext_failed}
            end
          after
            File.rm(path)
          end
        end
    end
  end

  defp write_temp(bytes) do
    path = Path.join(DataDir.tmp_dir(), "grana_pdf_#{Ecto.UUID.generate()}.pdf")

    case File.write(path, bytes) do
      :ok ->
        File.chmod(path, 0o600)
        {:ok, path}

      {:error, reason} ->
        {:error, {:tmp_write_failed, reason}}
    end
  end

  defp run(exe, path) do
    case System.cmd(exe, ["-layout", "-enc", "UTF-8", "-nopgbrk", path, "-"],
           stderr_to_stdout: false
         ) do
      {output, 0} ->
        if String.trim(output) == "" do
          {:error, :no_text_layer}
        else
          {:ok, output}
        end

      {_output, code} ->
        Logger.warning("pdftotext falhou (status #{code})")
        {:error, :pdftotext_failed}
    end
  end
end
