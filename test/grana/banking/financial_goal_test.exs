defmodule Grana.Banking.FinancialGoalTest do
  use ExUnit.Case, async: true

  alias Grana.Banking.FinancialGoal

  describe "changeset/2" do
    test "valid attrs produce a valid changeset" do
      attrs = %{type: "expense_limit", target_value: "500.00", user_id: 1}
      cs = FinancialGoal.changeset(%FinancialGoal{}, attrs)
      assert cs.valid?
    end

    test "requires type, target_value, user_id" do
      cs = FinancialGoal.changeset(%FinancialGoal{}, %{})
      errors = Enum.map(cs.errors, &elem(&1, 0))
      assert :type in errors
      assert :target_value in errors
      assert :user_id in errors
    end

    test "rejects unknown type" do
      attrs = %{type: "invalid_type", target_value: "100.00", user_id: 1}
      cs = FinancialGoal.changeset(%FinancialGoal{}, attrs)
      refute cs.valid?
      assert {:type, {"tipo inválido", _}} = List.keyfind(cs.errors, :type, 0)
    end

    test "rejects target_value <= 0" do
      attrs = %{type: "expense_limit", target_value: "0", user_id: 1}
      cs = FinancialGoal.changeset(%FinancialGoal{}, attrs)
      refute cs.valid?
    end

    test "category_limit type requires category_id" do
      attrs = %{type: "category_limit", target_value: "500.00", user_id: 1}
      cs = FinancialGoal.changeset(%FinancialGoal{}, attrs)
      refute cs.valid?
      assert Keyword.has_key?(cs.errors, :category_id)
    end

    test "non-category_limit type clears category_id" do
      attrs = %{type: "expense_limit", target_value: "500.00", user_id: 1, category_id: 99}
      cs = FinancialGoal.changeset(%FinancialGoal{}, attrs)
      assert cs.valid?
      assert Ecto.Changeset.get_change(cs, :category_id) == nil
    end

    test "accepts all valid types" do
      for type <- FinancialGoal.types() do
        base_attrs = %{type: type, target_value: "100.00", user_id: 1}

        attrs =
          if type == "category_limit",
            do: Map.put(base_attrs, :category_id, 1),
            else: base_attrs

        cs = FinancialGoal.changeset(%FinancialGoal{}, attrs)
        assert cs.valid?, "type #{type} should be valid"
      end
    end
  end

  describe "type_label/1" do
    test "returns label for known types" do
      assert FinancialGoal.type_label("expense_limit") == "Limite de Gastos"
      assert FinancialGoal.type_label("income_goal") == "Meta de Receita"
      assert FinancialGoal.type_label("investment_goal") == "Meta de Investimento"
      assert FinancialGoal.type_label("category_limit") == "Limite por Categoria"
    end

    test "returns fallback for unknown type" do
      assert FinancialGoal.type_label("unknown") == "Meta"
    end
  end

  describe "type_icon/1" do
    test "returns icon for known types" do
      assert FinancialGoal.type_icon("expense_limit") =~ "hero-"
      assert FinancialGoal.type_icon("income_goal") =~ "hero-"
      assert FinancialGoal.type_icon("investment_goal") =~ "hero-"
      assert FinancialGoal.type_icon("category_limit") =~ "hero-"
    end

    test "returns fallback icon for unknown type" do
      assert FinancialGoal.type_icon("unknown") == "hero-flag"
    end
  end

  describe "types/0" do
    test "returns list of valid types" do
      types = FinancialGoal.types()
      assert is_list(types)
      assert "expense_limit" in types
      assert "category_limit" in types
    end
  end
end
