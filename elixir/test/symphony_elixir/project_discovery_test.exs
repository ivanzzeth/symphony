defmodule SymphonyElixir.ProjectDiscoveryTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.ProjectDiscovery

  test "discovers WORKFLOW.md files in subdirectories" do
    projects_dir = Path.join(System.tmp_dir!(), "test-projects-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(projects_dir, "project-a"))
    File.mkdir_p!(Path.join(projects_dir, "project-b"))
    File.mkdir_p!(Path.join(projects_dir, "empty-project"))
    File.write!(Path.join(projects_dir, "project-a/WORKFLOW.md"), "---\ntracker:\n  kind: memory\n---\nprompt")
    File.write!(Path.join(projects_dir, "project-b/WORKFLOW.md"), "---\ntracker:\n  kind: memory\n---\nprompt")

    on_exit(fn -> File.rm_rf!(projects_dir) end)

    {:ok, projects} = ProjectDiscovery.discover(projects_dir)

    assert length(projects) == 2
    names = Enum.map(projects, & &1.name)
    assert "project-a" in names
    assert "project-b" in names

    project_a = Enum.find(projects, &(&1.name == "project-a"))
    assert String.ends_with?(project_a.path, "project-a")
    assert String.ends_with?(project_a.workflow_path, Path.join("project-a", "WORKFLOW.md"))
  end

  test "returns empty list when no subdir has WORKFLOW.md" do
    projects_dir = Path.join(System.tmp_dir!(), "empty-projects-#{System.unique_integer([:positive])}")
    File.mkdir_p!(projects_dir)

    on_exit(fn -> File.rm_rf!(projects_dir) end)

    assert {:ok, []} = ProjectDiscovery.discover(projects_dir)
  end

  test "ignores WORKFLOW.md files that are not regular files" do
    projects_dir = Path.join(System.tmp_dir!(), "bad-projects-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(projects_dir, "bad-project"))
    # no WORKFLOW.md file written

    on_exit(fn -> File.rm_rf!(projects_dir) end)

    assert {:ok, []} = ProjectDiscovery.discover(projects_dir)
  end

  test "returns error for non-existent dir" do
    assert {:error, {:invalid_projects_dir, _, _}} = ProjectDiscovery.discover("/nonexistent/path")
  end
end
