defmodule SymphonyElixir.ProjectSupervisorTest do
  use ExUnit.Case, async: false

  import SymphonyElixir.TestSupport, only: [write_workflow_file!: 2]

  alias SymphonyElixir.ProjectNaming
  alias SymphonyElixir.ProjectRegistry
  alias SymphonyElixir.ProjectSupervisor
  alias SymphonyElixir.ProjectSupervisor.Meta

  setup do
    Application.put_env(:symphony_elixir, :memory_tracker_issues, [])
    SymphonyElixir.ProjectAliases.clear_aliases()

    dir =
      Path.join(
        System.tmp_dir!(),
        "symphony-project-supervisor-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    wf = Path.join(dir, "WORKFLOW.md")
    base = Path.dirname(wf)

    write_workflow_file!(wf,
      tracker_kind: "memory",
      poll_interval_ms: 3_600_000,
      workspace_root: Path.join(System.tmp_dir!(), "symphony_ws_psup_#{System.unique_integer([:positive])}")
    )

    on_exit(fn ->
      File.rm_rf(dir)
      SymphonyElixir.ProjectAliases.clear_aliases()
    end)

    %{workflow_file: wf, config_base_dir: base}
  end

  test "start_project registers orchestrator and stop_project cleans up", %{
    workflow_file: wf,
    config_base_dir: base
  } do
    id = "proj-#{System.unique_integer([:positive])}"

    assert {:ok, tree_pid} =
             ProjectSupervisor.start_project(%{
               project_id: id,
               workflow_path: wf,
               config_base_dir: base
             })

    assert {:ok, _orch} = ProjectRegistry.lookup(id)

    assert match?([{_pid, _}], Registry.lookup(ProjectNaming.registry(), {id, :orchestrator}))

    running = ProjectSupervisor.list_projects()
    assert Enum.any?(running, &(&1.project_id == id and &1.status == :running))

    assert :ok = ProjectSupervisor.stop_project(id)
    assert :error = ProjectRegistry.lookup(id)
    refute Process.alive?(tree_pid)
  end

  test "startup_failure records error status without affecting another running project", %{
    workflow_file: wf,
    config_base_dir: base
  } do
    id_a = "proj-a-#{System.unique_integer([:positive])}"
    id_b = "proj-b-#{System.unique_integer([:positive])}"

    assert {:ok, _} =
             ProjectSupervisor.start_project(%{
               project_id: id_a,
               workflow_path: wf,
               config_base_dir: base
             })

    assert {:ok, orch_a} = ProjectRegistry.lookup(id_a)
    assert :ok = ProjectSupervisor.startup_failure(id_b)

    assert %{status: :error, project_id: ^id_b} = Meta.fetch(id_b)
    assert Enum.any?(ProjectSupervisor.list_projects(), &(&1.project_id == id_a))
    assert {:ok, ^orch_a} = ProjectRegistry.lookup(id_a)

    assert :ok = ProjectSupervisor.stop_project(id_a)
  end

  test "killing one project tree leaves another project's orchestrator alive", %{
    workflow_file: wf,
    config_base_dir: base
  } do
    id_a = "iso-a-#{System.unique_integer([:positive])}"
    id_b = "iso-b-#{System.unique_integer([:positive])}"

    assert {:ok, tree_a} =
             ProjectSupervisor.start_project(%{
               project_id: id_a,
               workflow_path: wf,
               config_base_dir: base
             })

    assert {:ok, _} =
             ProjectSupervisor.start_project(%{
               project_id: id_b,
               workflow_path: wf,
               config_base_dir: base
             })

    {:ok, orch_b} = ProjectRegistry.lookup(id_b)

    Process.exit(tree_a, :kill)

    assert_until(fn -> match?(%{status: :error}, Meta.fetch(id_a)) end)

    assert Process.alive?(orch_b)
    assert {:ok, _} = ProjectRegistry.lookup(id_b)
    assert :ok = ProjectSupervisor.stop_project(id_b)
  end

  test "failed start on invalid workflow leaves a sibling project running", %{
    workflow_file: wf,
    config_base_dir: base
  } do
    id_ok = "ok-#{System.unique_integer([:positive])}"
    bogus_wf = Path.join(base, "missing-workflow.md")

    assert {:ok, _} =
             ProjectSupervisor.start_project(%{
               project_id: id_ok,
               workflow_path: wf,
               config_base_dir: base
             })

    assert {:error, _} =
             ProjectSupervisor.start_project(%{
               project_id: "bad-#{System.unique_integer([:positive])}",
               workflow_path: bogus_wf,
               config_base_dir: base
             })

    assert {:ok, orch_ok} = ProjectRegistry.lookup(id_ok)
    assert Process.alive?(orch_ok)
    assert :ok = ProjectSupervisor.stop_project(id_ok)
  end

  test "start_project returns :already_started for duplicate id", %{
    workflow_file: wf,
    config_base_dir: base
  } do
    id = "dup-#{System.unique_integer([:positive])}"

    assert {:ok, _} =
             ProjectSupervisor.start_project(%{
               project_id: id,
               workflow_path: wf,
               config_base_dir: base
             })

    assert {:error, :already_started} =
             ProjectSupervisor.start_project(%{
               project_id: id,
               workflow_path: wf,
               config_base_dir: base
             })

    assert :ok = ProjectSupervisor.stop_project(id)
  end

  test "stop_project returns {:error, :not_found} for unknown id" do
    assert {:error, :not_found} =
             ProjectSupervisor.stop_project("missing-#{System.unique_integer([:positive])}")
  end

  defp assert_until(fun, attempts \\ 50)

  defp assert_until(fun, 0), do: flunk("condition not met in time")

  defp assert_until(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(20)
      assert_until(fun, attempts - 1)
    end
  end
end
