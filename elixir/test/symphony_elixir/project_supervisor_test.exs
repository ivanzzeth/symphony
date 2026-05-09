defmodule SymphonyElixir.ProjectSupervisorTest do
  use SymphonyElixir.TestSupport, async: false

  alias SymphonyElixir.{ProjectNaming, ProjectRegistry, ProjectSupervisor}

  defp wait_until(fun, attempts \\ 80)

  defp wait_until(_fun, 0), do: {:error, :timeout}

  defp wait_until(fun, n) do
    if fun.() do
      :ok
    else
      Process.sleep(25)
      wait_until(fun, n - 1)
    end
  end

  defp isolation_project(label) do
    root =
      Path.join(
        System.tmp_dir!(),
        "symphony-iso-#{label}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    wf = Path.join(root, "WORKFLOW.md")
    SymphonyElixir.TestSupport.write_workflow_file!(wf)
    {root, wf}
  end

  test "start_project registers orchestrator pid in ProjectRegistry" do
    orch_via = ProjectNaming.via("default", :orchestrator)
    {:ok, pid} = ProjectRegistry.lookup("default")
    assert is_pid(pid)
    assert pid == GenServer.whereis(orch_via)
  end

  test "list_projects includes running default project" do
    entries = ProjectSupervisor.list_projects()
    ids = Enum.map(entries, & &1.project_id)
    assert "default" in ids
    running = Enum.find(entries, &(&1.project_id == "default"))
    assert running.status == :running
    assert is_pid(running.tree_pid)
  end

  test "startup_failure marks meta without killing other projects" do
    assert :ok = ProjectSupervisor.startup_failure("ghost-project")

    assert %{status: :error} = SymphonyElixir.ProjectSupervisor.Meta.fetch("ghost-project")
    assert {:ok, _} = ProjectRegistry.lookup("default")
  end

  test "killing one project's orchestrator does not kill another project's orchestrator" do
    {root_a, wf_a} = isolation_project("a")
    {root_b, wf_b} = isolation_project("b")

    on_exit(fn ->
      _ = ProjectSupervisor.stop_project("iso-a")
      _ = ProjectSupervisor.stop_project("iso-b")
      File.rm_rf(root_a)
      File.rm_rf(root_b)
    end)

    assert {:ok, _} =
             ProjectSupervisor.start_project(%{
               project_id: "iso-a",
               workflow_path: wf_a,
               config_base_dir: root_a
             })

    assert {:ok, _} =
             ProjectSupervisor.start_project(%{
               project_id: "iso-b",
               workflow_path: wf_b,
               config_base_dir: root_b
             })

    [{orch_a, _}] =
      Registry.lookup(ProjectNaming.registry(), {"iso-a", :orchestrator})

    {:ok, orch_b} = ProjectRegistry.lookup("iso-b")

    Process.exit(orch_a, :kill)
    Process.sleep(200)

    assert {:ok, orch_b_after} = ProjectRegistry.lookup("iso-b")
    assert orch_b_after == orch_b
    assert Process.alive?(orch_b_after)
  end

  test "stop_project unregisters from ProjectRegistry" do
    root =
      Path.join(
        System.tmp_dir!(),
        "symphony-ps-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    wf = Path.join(root, "WORKFLOW.md")
    SymphonyElixir.TestSupport.write_workflow_file!(wf)

    assert {:ok, _} =
             ProjectSupervisor.start_project(%{
               project_id: "stop-test",
               workflow_path: wf,
               config_base_dir: root
             })

    assert {:ok, _} = ProjectRegistry.lookup("stop-test")
    assert :ok = ProjectSupervisor.stop_project("stop-test")
    assert :error = ProjectRegistry.lookup("stop-test")

    on_exit(fn -> File.rm_rf(root) end)
  end

  test "crashing a peer project tree does not stop the default orchestrator" do
    root =
      Path.join(
        System.tmp_dir!(),
        "symphony-ps-iso-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    wf = Path.join(root, "WORKFLOW.md")
    SymphonyElixir.TestSupport.write_workflow_file!(wf)

    id = "iso-peer-#{System.unique_integer([:positive])}"

    assert {:ok, tree_pid} =
             ProjectSupervisor.start_project(%{
               project_id: id,
               workflow_path: wf,
               config_base_dir: root
             })

    default_orch_before = GenServer.whereis(ProjectNaming.via("default", :orchestrator))
    assert is_pid(default_orch_before)

    Process.exit(tree_pid, :kill)

    assert :ok =
             poll_until(fn ->
               case SymphonyElixir.ProjectSupervisor.Meta.fetch(id) do
                 %{status: s} when s in [:error, :stopped] -> true
                 _ -> false
               end
             end)

    assert Process.alive?(default_orch_before)
    assert {:ok, _} = ProjectRegistry.lookup("default")

    on_exit(fn -> File.rm_rf(root) end)
  end

  defp poll_until(fun), do: poll_until(fun, 50)

  defp poll_until(_fun, 0), do: {:error, :timeout}

  defp poll_until(fun, n) when n > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(20)
      poll_until(fun, n - 1)
    end
  end
end
