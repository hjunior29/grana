defmodule Grana.Banking.SearchTest do
  use ExUnit.Case, async: true

  alias Grana.Banking.{BankStatement, Category, Search, Transaction}

  defp txn(attrs) do
    %Transaction{
      id: Keyword.get(attrs, :id, System.unique_integer([:positive])),
      description: Keyword.get(attrs, :description, "COMPRA"),
      original_description: Keyword.get(attrs, :original_description),
      amount: Decimal.new(Keyword.get(attrs, :amount, "-10.00")),
      type: Keyword.get(attrs, :type, "debit"),
      date: Keyword.get(attrs, :date, ~D[2026-03-15]),
      is_internal_transfer: Keyword.get(attrs, :internal, false),
      installment_total: Keyword.get(attrs, :installment_total),
      category: Keyword.get(attrs, :category, %Category{name: "Sem Categoria", kind: "expense"}),
      bank_statement: %BankStatement{
        bank: Keyword.get(attrs, :bank, "nubank"),
        statement_type: Keyword.get(attrs, :statement_type, "extrato"),
        source: Keyword.get(attrs, :source, "upload")
      }
    }
  end

  defp matches(query, txns, recurring \\ %{}) do
    assert {:ok, search} = Search.parse(query)
    search |> Search.filter(txns, recurring) |> Enum.map(& &1.description)
  end

  defp canonical(query) do
    assert {:ok, search} = Search.parse(query)
    search.canonical
  end

  defp error(query) do
    assert {:error, message} = Search.parse(query)
    message
  end

  defp category(name, kind \\ "expense"), do: %Category{name: name, kind: kind}

  describe "texto sem campo" do
    test "busca vazia casa com tudo" do
      txns = [txn(description: "A"), txn(description: "B")]

      assert matches("", txns) == ["A", "B"]
      assert matches("   ", txns) == ["A", "B"]
      assert {:ok, %Search{ast: nil}} = Search.parse(nil)
    end

    test "contém, sem diferenciar maiúsculas e acentos" do
      txns = [txn(description: "TRANSFERêNCIA ENVIADA"), txn(description: "PADARIA")]

      assert matches("transferencia", txns) == ["TRANSFERêNCIA ENVIADA"]
      assert matches("TRANSFERÊNCIA", txns) == ["TRANSFERêNCIA ENVIADA"]
    end

    test "procura também na descrição original" do
      txns = [txn(description: "Netflix", original_description: "PAGSEGURO*NETFLIX")]

      assert matches("pagseguro", txns) == ["Netflix"]
    end

    test "casa com o nome exato da categoria" do
      txns = [
        txn(description: "MERCADO X", category: category("Alimentação")),
        txn(description: "POSTO", category: category("Alimentação extra"))
      ]

      assert matches("alimentacao", txns) == ["MERCADO X"]
    end
  end

  describe "operadores" do
    setup do
      %{
        txns: [
          txn(description: "UBER TRIP"),
          txn(description: "99 TAXI"),
          txn(description: "UBER EATS"),
          txn(description: "PADARIA")
        ]
      }
    end

    test "AND, OR e NOT", %{txns: txns} do
      assert matches("uber AND trip", txns) == ["UBER TRIP"]
      assert matches("uber OR 99", txns) == ["UBER TRIP", "99 TAXI", "UBER EATS"]
      assert matches("uber NOT eats", txns) == ["UBER TRIP"]
      assert matches("NOT uber", txns) == ["99 TAXI", "PADARIA"]
    end

    test "termos lado a lado valem AND", %{txns: txns} do
      assert matches("uber eats", txns) == ["UBER EATS"]
    end

    test "só AND, OR e NOT em maiúsculas são operadores", %{txns: txns} do
      assert matches("uber or padaria", txns) == []
      assert canonical("uber or padaria") == "uber AND or AND padaria"
      assert canonical("uber OU 99") == "uber AND OU AND 99"
    end

    test "NOT antes de AND, AND antes de OR", %{txns: txns} do
      assert matches("padaria OR uber eats", txns) == ["UBER EATS", "PADARIA"]
      assert matches("(padaria OR uber) eats", txns) == ["UBER EATS"]
      assert canonical("padaria OR uber eats") == "padaria OR (uber AND eats)"
      assert canonical("NOT (a OR b) c") == "NOT (a OR b) AND c"
    end
  end

  describe "aspas, truncamento e expressão regular" do
    setup do
      %{
        txns: [
          txn(description: "99 TAXI"),
          txn(description: "COMPRA 1990"),
          txn(description: "PIX ENVIADO"),
          txn(description: "COMPRA PIX"),
          txn(description: "POSTO SHELL")
        ]
      }
    end

    test "aspas pedem palavra ou frase inteira", %{txns: txns} do
      assert matches("99", txns) == ["99 TAXI", "COMPRA 1990"]
      assert matches(~s("99"), txns) == ["99 TAXI"]
      assert matches(~s("posto shell"), txns) == ["POSTO SHELL"]
      assert matches(~s("posto shel"), txns) == []
    end

    test "* e ? casam com o valor inteiro", %{txns: txns} do
      assert matches("description:pix*", txns) == ["PIX ENVIADO"]
      assert matches("description:*pix", txns) == ["COMPRA PIX"]
      assert matches("description:9?_taxi", txns) == []
      assert matches("description:9?*", txns) == ["99 TAXI"]
    end

    test "expressão regular", %{txns: txns} do
      assert matches("/^compra \\d+$/", txns) == ["COMPRA 1990"]
      assert matches("description:/pix$/", txns) == ["COMPRA PIX"]
    end

    test "expressão regular com barra escapada" do
      assert matches("/a\\/b/", [txn(description: "A/B"), txn(description: "AB")]) == ["A/B"]
    end
  end

  describe "campos de texto" do
    test "categoria compara o nome inteiro, com curinga se quiser" do
      txns = [
        txn(description: "A", category: category("Alimentação")),
        txn(description: "B", category: category("Transporte")),
        txn(description: "C", category: nil)
      ]

      assert matches("category:alim", txns) == []
      assert matches("category:alim*", txns) == ["A"]
      assert matches("cat:transporte", txns) == ["B"]
      assert matches(~s(category:"sem categoria"), txns) == ["C"]
      assert matches("category:(transporte OR alimentacao)", txns) == ["A", "B"]
    end

    test "bank e nome de campo em maiúsculas" do
      txns = [txn(description: "A", bank: "nubank"), txn(description: "B", bank: "bradesco")]

      assert matches("bank:bradesco", txns) == ["B"]
      assert matches("DESCRIPTION:a", txns) == ["A"]
    end
  end

  describe "campos de escolha" do
    test "type: a coluna (credit, debit) e os totais (income, expense, investment)" do
      investimento = category("Investimentos", "investment")

      txns = [
        txn(description: "SALARIO", type: "credit", amount: "5000"),
        txn(description: "MERCADO", type: "debit"),
        txn(description: "CDB", type: "debit", category: investimento),
        txn(description: "RESGATE", type: "credit", category: investimento)
      ]

      assert matches("type:credit", txns) == ["SALARIO", "RESGATE"]
      assert matches("type:income", txns) == ["SALARIO", "RESGATE"]
      assert matches("type:debit", txns) == ["MERCADO", "CDB"]
      assert matches("type:expense", txns) == ["MERCADO"]
      assert matches("type:investment", txns) == ["CDB", "RESGATE"]
    end

    test "statement_type e source do extrato" do
      txns = [
        txn(description: "A", statement_type: "fatura"),
        txn(description: "B", source: "open_finance")
      ]

      assert matches("statement_type:fatura", txns) == ["A"]
      assert matches("statement_type:extrato", txns) == ["B"]
      assert matches("source:open_finance", txns) == ["B"]
      assert matches("source:upload", txns) == ["A"]
    end

    test "internal e installments" do
      txns = [
        txn(description: "A", internal: true),
        txn(description: "B", installment_total: 3),
        txn(description: "C", installment_total: 1)
      ]

      assert matches("internal:true", txns) == ["A"]
      assert matches("is_internal_transfer:false", txns) == ["B", "C"]
      assert matches("installments>1", txns) == ["B"]
      assert matches("installment_total:1", txns) == ["A", "C"]
    end

    test "recurrence lê o estado de cada transação" do
      fixa = txn(id: 1, description: "ALUGUEL")
      variavel = txn(id: 2, description: "MERCADO")
      recurring = %{1 => %{status: "fixed"}, 2 => %{status: "variable"}}

      assert matches("recurrence:fixed", [fixa, variavel], recurring) == ["ALUGUEL"]
      assert matches("recurrence:variable", [fixa, variavel], recurring) == ["MERCADO"]
      assert matches("recurrence:fixed", [fixa, variavel]) == []
    end

    test "uses_recurrence? só quando a busca usa recurrence" do
      {:ok, with_field} = Search.parse("uber OR NOT recurrence:fixed")
      {:ok, without} = Search.parse("uber type:expense")
      {:ok, empty} = Search.parse("")

      assert Search.uses_recurrence?(with_field)
      refute Search.uses_recurrence?(without)
      refute Search.uses_recurrence?(empty)
    end
  end

  describe "amount" do
    setup do
      %{
        txns: [
          txn(description: "5", amount: "-5.00"),
          txn(description: "49,90", amount: "-49.90", type: "debit"),
          txn(description: "100", amount: "100.00", type: "credit"),
          txn(description: "1500", amount: "-1500.00")
        ]
      }
    end

    test "compara o valor sem sinal", %{txns: txns} do
      assert matches("amount>100", txns) == ["1500"]
      assert matches("amount>=100", txns) == ["100", "1500"]
      assert matches("amount<49,90", txns) == ["5"]
      assert matches("amount<=49.90", txns) == ["5", "49,90"]
      assert matches("amount:100", txns) == ["100"]
      assert matches("amount=R$100", txns) == ["100"]
      assert matches("amount:>1000", txns) == ["1500"]
    end

    test "intervalos e grupos", %{txns: txns} do
      assert matches("amount:40..100", txns) == ["49,90", "100"]
      assert matches("amount:..10", txns) == ["5"]
      assert matches("amount:1.000,00..", txns) == ["1500"]
      assert matches("amount:(<10 OR >1000)", txns) == ["5", "1500"]
      assert matches(~s(amount:"40 .. 100"), txns) == ["49,90", "100"]
    end
  end

  describe "date" do
    setup do
      %{
        txns: [
          txn(description: "fev", date: ~D[2026-02-28]),
          txn(description: "mar", date: ~D[2026-03-10]),
          txn(description: "dez", date: ~D[2025-12-24])
        ]
      }
    end

    test "dia, mês e ano nos formatos ISO e brasileiro", %{txns: txns} do
      assert matches("date:2026-03-10", txns) == ["mar"]
      assert matches("date:10/03/2026", txns) == ["mar"]
      assert matches("date:2026-03", txns) == ["mar"]
      assert matches("date:02/2026", txns) == ["fev"]
      assert matches("date:2025", txns) == ["dez"]
    end

    test "comparações usam o começo ou o fim do período", %{txns: txns} do
      assert matches("date>2026-02", txns) == ["mar"]
      assert matches("date>=2026-02", txns) == ["fev", "mar"]
      assert matches("date<2026", txns) == ["dez"]
      assert matches("date<=2026-02", txns) == ["fev", "dez"]
      assert matches("date:2025-12..2026-02", txns) == ["fev", "dez"]
    end

    test "datas relativas a hoje" do
      today = Date.utc_today()

      txns = [
        txn(description: "hoje", date: today),
        txn(description: "ontem", date: Date.add(today, -1)),
        txn(description: "antigo", date: Date.shift(today, year: -2))
      ]

      assert matches("date:today", txns) == ["hoje"]
      assert matches("date:yesterday", txns) == ["ontem"]
      assert matches("date>=today-7d", txns) == ["hoje", "ontem"]
      assert matches("date>=today-1w", txns) == ["hoje", "ontem"]
      assert matches("date<today-1y", txns) == ["antigo"]
      assert matches("date:today-3m..today", txns) == ["hoje", "ontem"]
    end

    test "year, month (com nome e volta no ano) e day", %{txns: txns} do
      assert matches("year:2025", txns) == ["dez"]
      assert matches("month:3", txns) == ["mar"]
      assert matches("month:december", txns) == ["dez"]
      assert matches("month:dec..feb", txns) == ["fev", "dez"]
      assert matches("month:dez..fev", txns) == ["fev", "dez"]
      assert matches("day:20..5", txns) == ["fev", "dez"]
      assert matches("day>=10 day<=24", txns) == ["mar", "dez"]
    end
  end

  describe "forma canônica" do
    test "explicita AND, campos e grupos" do
      assert canonical("uber 99") == "uber AND 99"

      assert canonical("desc:uber OR cat:(lazer OR \"sem categoria\")") ==
               ~s(description:uber OR category:lazer OR category:"sem categoria")

      assert canonical("amount >= 10") == "amount>=10"
      assert canonical("uber NOT /pix$/") == "uber AND NOT /pix$/"
    end
  end

  describe "erros" do
    test "estrutura" do
      assert error("(uber") =~ "Faltou fechar um parêntese"
      assert error("uber)") =~ ~s[")" sem parêntese aberto]
      assert error("()") =~ "parênteses vazios"
      assert error(~s("posto)) =~ "aspas"
      assert error("/pix") =~ "expressão regular"
      assert error("AND uber") =~ "Faltou um termo antes de AND"
      assert error("uber OR") =~ "termina sem um termo"
      assert error("uber NOT") =~ "termina sem um termo"
      assert error("amount>") =~ ~s(Faltou o valor depois de "amount>")
      assert error(~s("")) =~ "aspas vazias"
      assert error(String.duplicate("a", 2001)) =~ "2000 caracteres"
    end

    test "campos e valores" do
      assert error("categry:x") =~ ~s(Campo desconhecido "categry")
      assert error("categoria:x") =~ ~s(Campo desconhecido "categoria")
      assert error("category>3") =~ ~s("category" só aceita ":")
      assert error("type>credit") =~ ~s("type" só aceita ":")
      assert error("amount>(1 OR 2)") =~ "antes do parêntese"
      assert error("amount:/1/") =~ "não aceita expressão regular"
      assert error("description:/(/") =~ "Expressão regular inválida"
      assert error("amount:abc") =~ "amount"
      assert error("amount:-5") =~ "sem sinal"
      assert error("amount>10..20") =~ "Intervalo"
      assert error("amount:..") =~ "Intervalo vazio"
      assert error("amount:200..50") =~ "começo do intervalo"
      assert error("date:31/02/2026") =~ "Data"
      assert error("date:2026-13") =~ "Data"
      assert error("date:hoje") =~ "Data"
      assert error("year:26") =~ "year"
      assert error("month:13") =~ "month"
      assert error("day:32") =~ "day"
      assert error("installments:0") =~ "installments"
      assert error("type:despesa") =~ "type aceita"
      assert error("statement_type:xyz") =~ "statement_type aceita"
      assert error("source:of") =~ "source aceita"
      assert error("internal:sim") =~ "internal aceita"
      assert error("recurrence:fixa") =~ "recurrence aceita"
    end

    test "texto com dois-pontos vai entre aspas" do
      assert matches(~s("pix:joao"), [txn(description: "PIX:JOAO")]) == ["PIX:JOAO"]
    end
  end

  test "fold/1 tira acentos, maiúsculas e espaços" do
    assert Search.fold("  Alimentação ") == "alimentacao"
    assert Search.fold(nil) == ""
  end
end
