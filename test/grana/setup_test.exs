defmodule Grana.SetupTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Grana.Setup

  setup do
    on_exit(&Setup.clear_code/0)
  end

  test "sem código gerado, nada é aceito" do
    Setup.clear_code()
    refute Setup.verify_code("ABCD-EFGH")
  end

  test "gera código XXXX-XXXX legível e o imprime no log" do
    level = Logger.level()
    Logger.configure(level: :notice)
    on_exit(fn -> Logger.configure(level: level) end)

    log = capture_log(fn -> send(self(), {:code, Setup.generate_code()}) end)

    assert_received {:code, code}
    assert code =~ ~r/^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/
    assert log =~ code
    assert log =~ "/setup"
  end

  test "verify_code aceita o código sem hífen e em minúsculas, recusa outros" do
    code = Setup.generate_code()

    assert Setup.verify_code(code)
    assert Setup.verify_code(code |> String.replace("-", "") |> String.downcase())
    refute Setup.verify_code("AAAA-AAAA")
    refute Setup.verify_code(nil)
  end

  test "um novo código invalida o anterior e clear_code invalida tudo" do
    old = Setup.generate_code()
    new = Setup.generate_code()

    assert Setup.verify_code(new)
    assert old == new or not Setup.verify_code(old)

    Setup.clear_code()
    refute Setup.verify_code(new)
  end
end
