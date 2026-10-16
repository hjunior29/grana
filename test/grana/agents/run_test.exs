defmodule Grana.Agents.RunTest do
  use Grana.DataCase, async: false
  use Mimic

  setup :set_mimic_global

  import Grana.AccountsFixtures

  alias Grana.Agents.Run
  alias Grana.Agents.SearchBuilder
  alias Grana.LLMStub

  setup do
    user = user_fixture() |> ai_fixture()
    on_exit(fn -> Run.clear(user.id, :search) end)
    Run.subscribe(user.id)
    %{user: user}
  end

  defp search(user, request), do: fn -> SearchBuilder.run(user.id, request) end

  test "runs in the background and keeps the outcome until cleared", %{user: user} do
    LLMStub.script([
      {:tool, "submit_query", %{"query" => "uber", "explanation" => "Corridas."}}
    ])

    assert {:ok, _pid} = Run.start(user.id, :search, "gastos com uber", search(user, "uber"))
    assert_receive {:agent_run, :search, {:done, %{kind: :query, query: "uber"}}}, 5_000

    assert %{input: "gastos com uber", outcome: {:ok, %{query: "uber"}}} =
             Run.current(user.id, :search)

    assert :ok = Run.clear(user.id, :search)
    assert Run.current(user.id, :search) == nil
  end

  test "one run at a time per name, replaced once it is finished", %{user: user} do
    test_pid = self()

    LLMStub.script([
      fn _messages ->
        send(test_pid, {:waiting, self()})

        receive do
          :go -> "Só monto buscas."
        end
      end
    ])

    assert {:ok, pid} = Run.start(user.id, :search, "uber", search(user, "uber"))
    assert_receive {:waiting, task}, 5_000
    assert %{input: "uber", outcome: nil} = Run.current(user.id, :search)
    assert {:error, :busy} = Run.start(user.id, :search, "ifood", search(user, "ifood"))

    send(task, :go)
    assert_receive {:agent_run, :search, {:done, %{kind: :text}}}, 5_000

    LLMStub.script(["Outra."])
    ref = Process.monitor(pid)
    assert {:ok, _pid} = Run.start(user.id, :search, "ifood", search(user, "ifood"))
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    assert_receive {:agent_run, :search, {:done, %{text: "Outra."}}}, 5_000
    assert %{input: "ifood"} = Run.current(user.id, :search)
  end

  test "names are independent", %{user: user} do
    assert {:ok, _} = Run.start(user.id, {:analysis, 2026, 3}, nil, fn -> {:ok, :march} end)
    assert {:ok, _} = Run.start(user.id, {:analysis, 2026, 0}, nil, fn -> {:ok, :year} end)
    assert_receive {:agent_run, {:analysis, 2026, 3}, {:done, :march}}, 5_000
    assert_receive {:agent_run, {:analysis, 2026, 0}, {:done, :year}}, 5_000

    assert :ok = Run.clear(user.id, {:analysis, 2026, 3})
    assert :ok = Run.clear(user.id, {:analysis, 2026, 0})
  end

  test "errors are kept and broadcast too", %{user: user} do
    LLMStub.script([{:error, "boom"}])

    assert {:ok, _pid} = Run.start(user.id, :search, "uber", search(user, "uber"))
    assert_receive {:agent_run, :search, {:error, "A IA respondeu com erro: boom"}}, 5_000

    assert %{outcome: {:error, "A IA respondeu com erro: boom"}} =
             Run.current(user.id, :search)
  end

  @tag :capture_log
  test "a crash while running ends as an error", %{user: user} do
    assert {:ok, _pid} = Run.start(user.id, :search, "uber", fn -> exit(:boom) end)
    assert_receive {:agent_run, :search, {:error, :crashed}}, 5_000
    assert %{outcome: {:error, :crashed}} = Run.current(user.id, :search)
  end
end
