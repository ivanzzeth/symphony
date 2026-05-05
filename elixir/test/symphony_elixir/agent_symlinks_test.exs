defmodule SymphonyElixir.AgentSymlinksTest do
  use SymphonyElixir.TestSupport
  alias SymphonyElixir.AgentSymlinks
  alias SymphonyElixir.Workspace

  test "creates .claude/ and .cursor/ symlinks to .agents/ in fresh workspace" do
    workspace_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-symlinks-fresh-#{System.unique_integer([:positive])}"
      )

    try do
      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        hook_after_create: "echo first > README.md"
      )

      assert {:ok, workspace} = Workspace.create_for_issue("MT-SYMLINKS")

      claude_link = Path.join(workspace, ".claude")
      cursor_link = Path.join(workspace, ".cursor")
      codex_link = Path.join(workspace, ".codex")
      agents_dir = Path.join(workspace, ".agents")

      assert File.dir?(agents_dir)
      assert {:ok, %File.Stat{type: :symlink}} = File.lstat(claude_link)
      assert {:ok, ".agents"} == File.read_link(claude_link)
      assert {:ok, %File.Stat{type: :symlink}} = File.lstat(cursor_link)
      assert {:ok, ".agents"} == File.read_link(cursor_link)
      assert {:ok, %File.Stat{type: :symlink}} = File.lstat(codex_link)
      assert {:ok, ".agents"} == File.read_link(codex_link)
    after
      File.rm_rf(workspace_root)
    end
  end

  test "symlinks are idempotent on re-use" do
    workspace_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-symlinks-idempotent-#{System.unique_integer([:positive])}"
      )

    try do
      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        hook_after_create: "echo first > README.md"
      )

      assert {:ok, workspace} = Workspace.create_for_issue("MT-IDEMPOTENT")

      claude_link = Path.join(workspace, ".claude")

      assert {:ok, %File.Stat{type: :symlink}} = File.lstat(claude_link)
      assert {:ok, ".agents"} == File.read_link(claude_link)

      assert {:ok, ^workspace} = Workspace.create_for_issue("MT-IDEMPOTENT")
      assert {:ok, %File.Stat{type: :symlink}} = File.lstat(claude_link)
      assert {:ok, ".agents"} == File.read_link(claude_link)
    after
      File.rm_rf(workspace_root)
    end
  end

  test "repairs broken symlinks on re-use" do
    workspace_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-symlinks-repair-#{System.unique_integer([:positive])}"
      )

    try do
      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        hook_after_create: "echo first > README.md"
      )

      assert {:ok, workspace} = Workspace.create_for_issue("MT-REPAIR")

      claude_link = Path.join(workspace, ".claude")
      assert {:ok, %File.Stat{type: :symlink}} = File.lstat(claude_link)

      File.rm!(claude_link)
      File.ln_s!(".nowhere", claude_link)

      assert {:ok, ".nowhere"} == File.read_link(claude_link)

      assert {:ok, ^workspace} = Workspace.create_for_issue("MT-REPAIR")
      assert {:ok, %File.Stat{type: :symlink}} = File.lstat(claude_link)
      assert {:ok, ".agents"} == File.read_link(claude_link)
    after
      File.rm_rf(workspace_root)
    end
  end

  test "warns and skips when real directory exists at symlink path" do
    workspace_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-symlinks-real-dir-#{System.unique_integer([:positive])}"
      )

    try do
      workspace = Path.join(workspace_root, "MT-REALDIR")
      File.mkdir_p!(workspace)
      File.mkdir_p!(Path.join(workspace, ".agents"))
      File.mkdir_p!(Path.join(workspace, ".claude"))
      File.write!(Path.join([workspace, ".claude", "settings.json"]), "{}")
      File.mkdir_p!(Path.join(workspace, ".cursor"))

      write_workflow_file!(Workflow.workflow_file_path(), workspace_root: workspace_root)

      log =
        capture_log(fn ->
          AgentSymlinks.manage(workspace)
        end)

      assert log =~ "Real directory exists"
    after
      File.rm_rf(workspace_root)
    end
  end

  test "reconcile_all repairs broken symlinks in existing workspaces" do
    workspace_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-symlinks-reconcile-#{System.unique_integer([:positive])}"
      )

    try do
      File.mkdir_p!(workspace_root)

      ws1 = Path.join(workspace_root, "MT-A")
      File.mkdir_p!(Path.join(ws1, ".agents"))

      File.ln_s!(".agents", Path.join(ws1, ".claude"))

      File.rm!(Path.join(ws1, ".claude"))
      File.ln_s!(".nowhere", Path.join(ws1, ".claude"))

      ws2 = Path.join(workspace_root, "MT-B")
      File.mkdir_p!(ws2)

      ws3 = Path.join(workspace_root, "MT-C")
      File.mkdir_p!(Path.join(ws3, ".agents"))
      File.ln_s!(".agents", Path.join(ws3, ".claude"))
      File.ln_s!(".agents", Path.join(ws3, ".cursor"))

      AgentSymlinks.reconcile_all(workspace_root)

      assert {:ok, %File.Stat{type: :symlink}} = File.lstat(Path.join(ws1, ".claude"))
      assert {:ok, ".agents"} == File.read_link(Path.join(ws1, ".claude"))
      assert {:ok, %File.Stat{type: :symlink}} = File.lstat(Path.join(ws1, ".cursor"))

      assert {:ok, %File.Stat{type: :symlink}} = File.lstat(Path.join(ws2, ".claude"))
      assert {:ok, ".agents"} == File.read_link(Path.join(ws2, ".claude"))
      assert {:ok, %File.Stat{type: :symlink}} = File.lstat(Path.join(ws2, ".cursor"))

      assert {:ok, %File.Stat{type: :symlink}} = File.lstat(Path.join(ws3, ".claude"))
      assert {:ok, ".agents"} == File.read_link(Path.join(ws3, ".claude"))
    after
      File.rm_rf(workspace_root)
    end
  end

  test "reconcile_all handles missing workspace root gracefully" do
    root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-symlinks-no-root-#{System.unique_integer([:positive])}"
      )

    assert :ok = AgentSymlinks.reconcile_all(root)
  end

  test "manage_project_root creates .claude/ .codex/ .cursor/ symlinks to .agents/" do
    project_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-project-symlinks-#{System.unique_integer([:positive])}"
      )

    try do
      File.mkdir_p!(project_root <> "/.agents/skills/harness")

      assert :ok = AgentSymlinks.manage_project_root(project_root)

      for name <- [".claude", ".codex", ".cursor"] do
        link_path = Path.join(project_root, name)
        assert {:ok, %File.Stat{type: :symlink}} = File.lstat(link_path)
        assert {:ok, ".agents"} == File.read_link(link_path)
      end
    after
      File.rm_rf(project_root)
    end
  end

  test "manage_project_root repairs broken symlink" do
    project_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-project-repair-#{System.unique_integer([:positive])}"
      )

    try do
      File.mkdir_p!(Path.join(project_root, ".agents"))
      File.ln_s!(".nowhere", Path.join(project_root, ".claude"))

      assert :ok = AgentSymlinks.manage_project_root(project_root)

      assert {:ok, %File.Stat{type: :symlink}} = File.lstat(Path.join(project_root, ".claude"))
      assert {:ok, ".agents"} == File.read_link(Path.join(project_root, ".claude"))
      assert {:ok, %File.Stat{type: :symlink}} = File.lstat(Path.join(project_root, ".codex"))
    after
      File.rm_rf(project_root)
    end
  end
end
