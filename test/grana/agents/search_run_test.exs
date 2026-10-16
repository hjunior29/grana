defmodule Grana.Agents.SearchRunTest do
  use Grana.DataCase, async: false
  use Mimic

  setup :set_mimic_global

  import Grana.AccountsFixtures

  alias Grana.Agents.SearchRun
  alias Grana.LLMStub

  setup do
    user = user_fixture() |> ai_fixture()
    on_exit(fn -> SearchRun.clear(user.id) end)
    SearchRun.subscribe(user.id)
    %{user: user}
  end

  defp blocking_script(test_pid) do
    LLMStub.script([
      fn _messages ->
        send(test_pid, {:waiting, self()})

        receive do
          :go -> "Só monto buscas."
        end
      end
    ])
  end

  test "builds in the background and keeps the outcome until cleared", %{user: user} do
    LLMStub.script([
      {:tool, "submit_query", %{"query" => "uber", "explanation" => "Corridas."}}
    ])

    assert {:ok, _pid} = SearchRun.start(user.id, "gastos com uber", nil)
    assert_receive {:search_build, {:done, %{kind: :query, query: "uber"}}}, 5_000

    assert %{request: "gastos com uber", outcome: {:ok, %{query: "uber"}}} =
             SearchRun.current(user.id)

    assert :ok = SearchRun.clear(user.id)
    assert SearchRun.current(user.id) == nil
  end

  test "one build at a time per user, replaced once it is finished", %{user: user} do
    blocking_script(self())

    assert {:ok, pid} = SearchRun.start(user.id, "uber", nil)
    assert_receive {:waiting, task}, 5_000
    assert %{request: "uber", outcome: nil} = SearchRun.current(user.id)
    assert {:error, :busy} = SearchRun.start(user.id, "ifood", nil)

    send(task, :go)
    assert_receive {:search_build, {:done, %{kind: :text}}}, 5_000

    LLMStub.script(["Outra."])
    ref = Process.monitor(pid)
    assert {:ok, _pid} = SearchRun.start(user.id, "ifood", nil)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    assert_receive {:search_build, {:done, %{text: "Outra."}}}, 5_000
    assert %{request: "ifood"} = SearchRun.current(user.id)
  end

  test "errors are kept and broadcast too", %{user: user} do
    LLMStub.script([{:error, "boom"}])

    assert {:ok, _pid} = SearchRun.start(user.id, "uber", nil)
    assert_receive {:search_build, {:error, "A IA respondeu com erro: boom"}}, 5_000
    assert %{outcome: {:error, "A IA respondeu com erro: boom"}} = SearchRun.current(user.id)
  end

  @tag :capture_log
  test "a crash while building ends as an error", %{user: user} do
    LLMStub.script([fn _messages -> exit(:boom) end])

    assert {:ok, _pid} = SearchRun.start(user.id, "uber", nil)
    assert_receive {:search_build, {:error, :crashed}}, 5_000
    assert %{outcome: {:error, :crashed}} = SearchRun.current(user.id)
  end
end
