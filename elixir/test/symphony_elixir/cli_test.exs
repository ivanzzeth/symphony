defmodule SymphonyElixir.CLITest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.CLI

  @ack_flag "--i-understand-that-this-will-be-running-without-the-usual-guardrails"

  defp base_deps(overrides \\ []) do
    defaults = [
      file_regular?: fn _path -> true end,
      set_workflow_file_path: fn _path -> :ok end,
      set_logs_root: fn _path -> :ok end,
      set_server_port_override: fn _port -> :ok end,
      set_projects: fn _projects -> :ok end,
      discover_projects: fn _path -> {:ok, []} end,
      ensure_all_started: fn -> {:ok, [:symphony_elixir]} end
    ]
    defaults
    |> Keyword.merge(overrides)
    |> Enum.into(%{})
  end

  test "returns the guardrails acknowledgement banner when the flag is missing" do
    parent = self()

    deps = base_deps(
      file_regular?: fn _path ->
        send(parent, :file_checked)
        true
      end,
      set_workflow_file_path: fn _path ->
        send(parent, :workflow_set)
        :ok
      end
    )

    assert {:error, banner} = CLI.evaluate(["WORKFLOW.md"], deps)
    assert banner =~ "This Symphony implementation is a low key engineering preview."
    assert banner =~ "Codex will run without any guardrails."
    assert banner =~ "SymphonyElixir is not a supported product and is presented as-is."
    assert banner =~ @ack_flag
    refute_received :file_checked
    refute_received :workflow_set
  end

  test "defaults to WORKFLOW.md when workflow path is missing" do
    deps = base_deps(
      file_regular?: fn path -> Path.basename(path) == "WORKFLOW.md" end
    )

    assert :ok = CLI.evaluate([@ack_flag], deps)
  end

  test "uses an explicit workflow path override when provided" do
    parent = self()
    workflow_path = "tmp/custom/WORKFLOW.md"
    expanded_path = Path.expand(workflow_path)

    deps = base_deps(
      file_regular?: fn path ->
        send(parent, {:workflow_checked, path})
        path == expanded_path
      end,
      set_workflow_file_path: fn path ->
        send(parent, {:workflow_set, path})
        :ok
      end
    )

    assert :ok = CLI.evaluate([@ack_flag, workflow_path], deps)
    assert_received {:workflow_checked, ^expanded_path}
    assert_received {:workflow_set, ^expanded_path}
  end

  test "accepts --logs-root and passes an expanded root to runtime deps" do
    parent = self()

    deps = base_deps(
      set_logs_root: fn path ->
        send(parent, {:logs_root, path})
        :ok
      end
    )

    assert :ok = CLI.evaluate([@ack_flag, "--logs-root", "tmp/custom-logs", "WORKFLOW.md"], deps)
    assert_received {:logs_root, expanded_path}
    assert expanded_path == Path.expand("tmp/custom-logs")
  end

  test "returns not found when workflow file does not exist" do
    deps = base_deps(file_regular?: fn _path -> false end)

    assert {:error, message} = CLI.evaluate([@ack_flag, "WORKFLOW.md"], deps)
    assert message =~ "Workflow file not found:"
  end

  test "returns startup error when app cannot start" do
    deps = base_deps(ensure_all_started: fn -> {:error, :boom} end)

    assert {:error, message} = CLI.evaluate([@ack_flag, "WORKFLOW.md"], deps)
    assert message =~ "Failed to start Symphony with workflow"
    assert message =~ ":boom"
  end

  test "returns ok when workflow exists and app starts" do
    deps = base_deps()

    assert :ok = CLI.evaluate([@ack_flag, "WORKFLOW.md"], deps)
  end

  # -- Multi-project tests --

  test "--projects-dir discovers projects and calls set_projects" do
    parent = self()
    projects_dir = "/tmp/test-projects"

    deps = base_deps(
      discover_projects: fn path ->
        send(parent, {:discovered, path})
        {:ok, [
          %{name: "project-a", path: Path.join(path, "project-a"), workflow_path: Path.join(path, "project-a/WORKFLOW.md")},
          %{name: "project-b", path: Path.join(path, "project-b"), workflow_path: Path.join(path, "project-b/WORKFLOW.md")}
        ]}
      end,
      set_projects: fn projects ->
        send(parent, {:projects_set, projects})
        :ok
      end
    )

    assert :ok = CLI.evaluate([@ack_flag, "--projects-dir", projects_dir, "WORKFLOW.md"], deps)
    assert_received {:discovered, ^projects_dir}
    assert_received {:projects_set, projects}
    assert length(projects) == 2
    assert Enum.map(projects, & &1.name) == ["project-a", "project-b"]
  end

  test "--projects-dir returns error when directory does not exist" do
    deps = base_deps(
      discover_projects: fn path ->
        {:error, {:invalid_projects_dir, path, :enoent}}
      end
    )

    assert {:error, message} = CLI.evaluate([@ack_flag, "--projects-dir", "/nonexistent", "WORKFLOW.md"], deps)
    assert message =~ "Failed to read projects dir"
    assert message =~ "/nonexistent"
  end

  test "--projects-dir returns error when no valid projects discovered" do
    deps = base_deps(
      discover_projects: fn _path -> {:ok, []} end
    )

    assert {:error, message} = CLI.evaluate([@ack_flag, "--projects-dir", "/empty", "WORKFLOW.md"], deps)
    assert message =~ "No valid projects found"
  end

  test "--projects-dir with empty value returns usage" do
    deps = base_deps()

    assert {:error, message} = CLI.evaluate([@ack_flag, "--projects-dir", "", "WORKFLOW.md"], deps)
    assert message =~ "Usage:"
  end

  test "--projects-dir works without explicit workflow path (defaults to WORKFLOW.md)" do
    parent = self()

    deps = base_deps(
      file_regular?: fn path -> Path.basename(path) == "WORKFLOW.md" end,
      discover_projects: fn _path ->
        {:ok, [%{name: "proj", path: "/tmp/test-projects/proj", workflow_path: "/tmp/test-projects/proj/WORKFLOW.md"}]}
      end,
      set_projects: fn _projects ->
        send(parent, :projects_set)
        :ok
      end
    )

    assert :ok = CLI.evaluate([@ack_flag, "--projects-dir", "/tmp/test-projects"], deps)
    assert_received :projects_set
  end
end
