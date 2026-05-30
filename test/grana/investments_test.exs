defmodule Grana.InvestmentsTest do
  use Grana.DataCase

  alias Grana.Investments

  import Grana.AccountsFixtures

  setup do
    user = user_fixture()
    institution = ensure_test_institution(user.id)
    %{user: user, institution: institution}
  end

  defp ensure_test_institution(user_id) do
    Investments.ensure_b3_institution(user_id)
  end

  describe "delete_statements/2 authorization" do
    test "delete_statements with correct user_id deletes the statements", %{
      user: user,
      institution: institution
    } do
      {:ok, stmt} =
        Investments.create_statement(%{
          filename: "test.csv",
          user_id: user.id,
          institution_id: institution.id
        })

      assert {1, _} = Investments.delete_statements([stmt.id], user.id)
      assert Investments.list_statements(user.id) == []
    end

    test "delete_statements with wrong user_id does not delete the statements", %{
      user: user,
      institution: institution
    } do
      other_user = user_fixture()

      {:ok, stmt} =
        Investments.create_statement(%{
          filename: "test.csv",
          user_id: user.id,
          institution_id: institution.id
        })

      assert {0, _} = Investments.delete_statements([stmt.id], other_user.id)
      assert length(Investments.list_statements(user.id)) == 1
    end

    test "get_statement! with wrong user_id raises", %{user: user, institution: institution} do
      other_user = user_fixture()

      {:ok, stmt} =
        Investments.create_statement(%{
          filename: "test.csv",
          user_id: user.id,
          institution_id: institution.id
        })

      assert_raise Ecto.NoResultsError, fn ->
        Investments.get_statement!(stmt.id, other_user.id)
      end
    end

    test "get_statement! with correct user_id returns the statement", %{
      user: user,
      institution: institution
    } do
      {:ok, stmt} =
        Investments.create_statement(%{
          filename: "test.csv",
          user_id: user.id,
          institution_id: institution.id
        })

      found = Investments.get_statement!(stmt.id, user.id)
      assert found.id == stmt.id
    end
  end
end
