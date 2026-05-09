defmodule SymphonyElixir.ProjectSupervisorTest do
  use SymphonyElixir.TestSupport, async: false

  alias SymphonyElixir.{ProjectNaming, ProjectRegistry, ProjectSupervisor}

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

    entry = SymphonyElixir.ProjectSupervisor.Meta.fetch("ghost-project")
    assert entry.status == :error
    assert {:ok, _} = ProjectRegistry.lookup("default")
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

    File.rm_rf(root)
  end
end
