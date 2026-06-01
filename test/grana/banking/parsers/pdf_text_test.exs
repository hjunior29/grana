defmodule Grana.Banking.Parsers.PdfTextTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Grana.Banking.Parsers.PdfText

  @example_pdf "priv/examples/extrato-bradesco.pdf"

  describe "extract/1" do
    test "extrai a camada de texto de um PDF real preservando o layout" do
      if System.find_executable("pdftotext") do
        assert {:ok, text} = PdfText.extract(File.read!(@example_pdf))
        # Conteúdo determinístico esperado do extrato.
        assert String.contains?(text, "Histórico")
        assert String.contains?(text, "PIX QR CODE DINAMICO")
        assert String.contains?(text, "Saldo (R$)")
      else
        assert {:error, :pdftotext_unavailable} = PdfText.extract(File.read!(@example_pdf))
      end
    end

    test "bytes que não são PDF resultam em erro (sem texto), não em crash" do
      if System.find_executable("pdftotext") do
        capture_log(fn ->
          assert {:error, reason} = PdfText.extract("isto não é um PDF")
          assert reason in [:no_text_layer, :pdftotext_failed]
        end)
      else
        assert {:error, :pdftotext_unavailable} = PdfText.extract("isto não é um PDF")
      end
    end
  end
end
