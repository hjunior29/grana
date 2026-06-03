defmodule Grana.Banking.RecurringExpensesTest do
  use ExUnit.Case, async: true

  alias Grana.Banking.RecurringExpenses

  # Helper: cria uma transação de despesa (mapa com os campos que analyze/1 usa).
  defp txn(date, description, amount, opts \\ []) do
    %{
      id: System.unique_integer([:positive]),
      date: date,
      description: description,
      amount: Decimal.new(amount),
      category: Keyword.get(opts, :category),
      installment_total: nil
    }
  end

  # 6 meses consecutivos terminando em 05/2026.
  defp six_months, do: [{2025, 12}, {2026, 1}, {2026, 2}, {2026, 3}, {2026, 4}, {2026, 5}]

  describe "normalize/1" do
    test "pega a contraparte após ' - ' e limpa pontuação/acentos" do
      assert RecurringExpenses.normalize("PIX QR CODE DINAMICO - 99 FOOD") == "99 food"

      assert RecurringExpenses.normalize("TRANSFERENCIA PIX - IMOBILIÁRIA SANTOS") ==
               "imobiliaria santos"
    end

    test "remove sufixos de empresa e números soltos" do
      assert RecurringExpenses.normalize("FLAMBRA LTDA") == "flambra"
      assert RecurringExpenses.normalize("NETFLIX.COM 12345") == "netflix com"
    end
  end

  describe "analyze/1 - classificação de fixas" do
    test "agrupa variações de nome e valor numa única despesa fixa" do
      # Netflix com nome e valor variando, 1x/mês nos 6 meses.
      descs = [
        "NETFLIX.COM",
        "NETFLIX *NETFLIX.COM",
        "NETFLIX.COM SAO PAULO",
        "NETFLIX",
        "NETFLIX.COM",
        "NETFLIX.COM"
      ]

      values = ["-39.90", "-39.90", "-44.90", "-44.90", "-44.90", "-44.90"]
      days = [5, 5, 6, 5, 7, 5]

      txns =
        Enum.zip([six_months(), descs, values, days])
        |> Enum.map(fn {{y, m}, d, v, day} -> txn(Date.new!(y, m, day), d, v) end)

      %{fixed: fixed} = RecurringExpenses.analyze(txns)

      assert [netflix] = fixed
      assert netflix.months_present == 6
      assert netflix.occurrences == 6
      assert String.contains?(String.upcase(netflix.name), "NETFLIX")
      # média de [39.90, 39.90, 44.90, 44.90, 44.90, 44.90] = 43.23
      assert Decimal.equal?(netflix.avg_amount, Decimal.new("43.23"))
      # dia típico ~ mediana dos dias
      assert netflix.typical_day in 5..7
    end

    test "tolera variação no dia de débito (não separa por dia)" do
      txns =
        Enum.map(six_months(), fn {y, m} ->
          # dias bem diferentes a cada mês
          day = Enum.random([3, 8, 12, 1, 15, 6])
          txn(Date.new!(y, m, day), "ACADEMIA SMARTFIT", "-99.90")
        end)

      assert %{fixed: [item]} = RecurringExpenses.analyze(txns)
      assert item.months_present == 6
    end

    test "classifica consumo de alta frequência (muitas vezes/mês) como variável" do
      # iFood 4x por mês nos 6 meses -> NÃO é fixa.
      txns =
        for {y, m} <- six_months(), day <- [3, 11, 19, 27] do
          txn(Date.new!(y, m, day), "PIX QR CODE DINAMICO - IFOOD", "-35.00")
        end

      %{fixed: fixed} = RecurringExpenses.analyze(txns)
      refute Enum.any?(fixed, &String.contains?(String.upcase(&1.name), "IFOOD"))
    end

    test "não classifica como fixa o que aparece na minoria dos meses" do
      # presente em só 2 dos 6 meses
      txns = [
        txn(~D[2026-04-10], "SEGURO PET", "-50.00"),
        txn(~D[2026-05-10], "SEGURO PET", "-50.00"),
        # ruído pra estabelecer 6 meses de janela
        txn(~D[2025-12-01], "COMPRA LOJA A", "-10.00"),
        txn(~D[2026-01-01], "COMPRA LOJA B", "-10.00"),
        txn(~D[2026-02-01], "COMPRA LOJA C", "-10.00"),
        txn(~D[2026-03-01], "COMPRA LOJA D", "-10.00")
      ]

      %{fixed: fixed, total_months: total} = RecurringExpenses.analyze(txns)
      assert total == 6
      refute Enum.any?(fixed, &String.contains?(String.upcase(&1.name), "SEGURO PET"))
    end
  end

  describe "analyze/1 - quebra mensal" do
    test "soma fixas e variáveis por mês sem dupla contagem" do
      # Uma despesa fixa (aluguel) + uma variável distinta por mês (comerciantes
      # diferentes, sem token em comum → não agrupam → variável).
      variaveis = [
        "PADARIA DOCE",
        "POSTO IPIRANGA",
        "FARMACIA SP",
        "LIVRARIA CULTURA",
        "BAR ZECA",
        "PET SHOP AU"
      ]

      txns =
        Enum.flat_map(Enum.zip(six_months(), variaveis), fn {{y, m}, loja} ->
          [
            txn(Date.new!(y, m, 10), "TRANSFERENCIA PIX - IMOBILIARIA SANTOS", "-1500.00"),
            txn(Date.new!(y, m, 20), "PIX QR CODE - #{loja}", "-200.00")
          ]
        end)

      %{monthly: monthly, avg_fixed: avg_fixed, fixed: fixed} = RecurringExpenses.analyze(txns)

      # aluguel é fixa; mercado (nomes diferentes a cada mês) é variável
      assert Enum.any?(fixed, &String.contains?(String.upcase(&1.name), "IMOBILIARIA"))
      assert Enum.all?(monthly, &Decimal.equal?(&1.fixed, Decimal.new("1500.00")))
      assert Enum.all?(monthly, &Decimal.equal?(&1.variable, Decimal.new("200.00")))
      assert Decimal.equal?(avg_fixed, Decimal.new("1500.00"))
    end

    test "lista vazia devolve análise zerada" do
      assert %{total_months: 0, fixed: [], monthly: [], variable_candidates: []} =
               RecurringExpenses.analyze([])
    end
  end

  # Comerciantes distintos por mês (não agrupam) -> estabelecem 6 meses de
  # janela e caem em variável (1 mês cada).
  defp distinct_filler do
    names = [
      "PADARIA DOCE",
      "POSTO IPIRANGA",
      "FARMACIA SP",
      "LIVRARIA CULTURA",
      "BAR ZECA",
      "PET AU"
    ]

    Enum.zip(six_months(), names)
    |> Enum.map(fn {{y, m}, n} -> txn(Date.new!(y, m, 3), "PIX - #{n}", "-15.00") end)
  end

  describe "analyze/1 - regras de recorrência" do
    test "regra 'fixed' promove comerciante que a inferência não pegou" do
      # Spotify só em 2/6 meses; regra força como fixa.
      spotify = [
        txn(~D[2026-04-09], "SPOTIFY", "-21.90"),
        txn(~D[2026-05-09], "SPOTIFY", "-21.90")
      ]

      txns = spotify ++ distinct_filler()

      assert %{fixed: []} = RecurringExpenses.analyze(txns)

      %{fixed: fixed} = RecurringExpenses.analyze(txns, rules: %{"spotify" => "fixed"})
      assert [item] = fixed
      assert item.name == "SPOTIFY"
      assert item.pattern == "spotify"
      assert item.status == "fixed"
    end

    test "regra 'variable' remove comerciante da lista de fixas" do
      txns =
        Enum.map(six_months(), fn {y, m} -> txn(Date.new!(y, m, 5), "NETFLIX.COM", "-44.90") end)

      assert %{fixed: [_netflix]} = RecurringExpenses.analyze(txns)

      assert %{fixed: []} =
               RecurringExpenses.analyze(txns, rules: %{"netflix com" => "variable"})
    end

    test "regra vale para variações do mesmo comerciante no cluster" do
      txns =
        Enum.zip([
          six_months(),
          ["NETFLIX", "NETFLIX.COM", "NETFLIX *BR", "NETFLIX.COM", "NETFLIX", "NETFLIX"]
        ])
        |> Enum.map(fn {{y, m}, description} ->
          txn(Date.new!(y, m, 5), description, "-44.90")
        end)

      assert %{fixed: []} =
               RecurringExpenses.analyze(txns, rules: %{"netflix" => "variable"})
    end

    test "variable_candidates traz recorrentes (≥2 meses) não-fixos, com pattern" do
      spotify = [
        txn(~D[2026-04-09], "SPOTIFY", "-21.90"),
        txn(~D[2026-05-09], "SPOTIFY", "-21.90")
      ]

      txns = spotify ++ distinct_filler()

      %{variable_candidates: cands} = RecurringExpenses.analyze(txns)
      patterns = Enum.map(cands, & &1.pattern)
      assert "spotify" in patterns
      # itens de 1 mês só (o filler) não são candidatos
      refute "padaria doce" in patterns
    end
  end
end
