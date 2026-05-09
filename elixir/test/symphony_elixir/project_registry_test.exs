defmodule SymphonyElixir.ProjectRegistryTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.ProjectRegistry

  defp unique_name do
    :"project_registry_test_#{:erlang.unique_integer([:positive])}"
  end

  setup do
    name = unique_name()
    start_supervised!({ProjectRegistry, name: name})
    %{registry: name}
  end

  describe "child_spec/0" do
    test "returns a valid supervisor child spec" do
      spec = ProjectRegistry.child_spec()
      assert spec.id == ProjectRegistry
      assert elem(spec.start, 0) == ProjectRegistry
      assert elem(spec.start, 1) == :start_link
      assert spec.type == :worker
    end
  end

  describe "register/2, lookup/1, unregister/1, list/0" do
    test "stores project_id → pid and returns metadata in list", %{registry: reg} do
      pid = spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Process.exit(pid, :kill) end)

      assert :ok = ProjectRegistry.register("alpha", pid, reg)
      assert {:ok, ^pid} = ProjectRegistry.lookup("alpha", reg)

      [entry] = ProjectRegistry.list(reg)
      assert entry.project_id == "alpha"
      assert entry.pid == pid
      assert %DateTime{} = entry.registered_at

      assert :ok = ProjectRegistry.unregister("alpha", reg)
      assert :error = ProjectRegistry.lookup("alpha", reg)
      assert ProjectRegistry.list(reg) == []
    end

    test "register replaces an existing project_id", %{registry: reg} do
      p1 = spawn(fn -> Process.sleep(:infinity) end)
      p2 = spawn(fn -> Process.sleep(:infinity) end)

      on_exit(fn ->
        Process.exit(p1, :kill)
        Process.exit(p2, :kill)
      end)

      assert :ok = ProjectRegistry.register("same", p1, reg)
      assert {:ok, ^p1} = ProjectRegistry.lookup("same", reg)
      assert :ok = ProjectRegistry.register("same", p2, reg)
      assert {:ok, ^p2} = ProjectRegistry.lookup("same", reg)
      assert length(ProjectRegistry.list(reg)) == 1
    end

    test "list/0 is sorted by project_id", %{registry: reg} do
      pids =
        for _ <- 1..3 do
          p = spawn(fn -> Process.sleep(:infinity) end)
          on_exit(fn -> Process.exit(p, :kill) end)
          p
        end

      assert :ok = ProjectRegistry.register("z", Enum.at(pids, 0), reg)
      assert :ok = ProjectRegistry.register("a", Enum.at(pids, 1), reg)
      assert :ok = ProjectRegistry.register("m", Enum.at(pids, 2), reg)

      ids = ProjectRegistry.list(reg) |> Enum.map(& &1.project_id)
      assert ids == ["a", "m", "z"]
    end
  end

  describe "concurrency" do
    test "concurrent registration and lookup", %{registry: reg} do
      n = 100

      tasks =
        for i <- 1..n do
          Task.async(fn ->
            id = "concurrent-#{i}"
            pid = spawn_link(fn -> Process.sleep(:infinity) end)

            try do
              assert :ok = ProjectRegistry.register(id, pid, reg)
              assert {:ok, ^pid} = ProjectRegistry.lookup(id, reg)
              {id, pid}
            after
              ProjectRegistry.unregister(id, reg)
              Process.exit(pid, :kill)
            end
          end)
        end

      Task.await_many(tasks, 10_000)
      assert ProjectRegistry.list(reg) == []
    end
  end
end
