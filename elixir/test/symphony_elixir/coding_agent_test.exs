defmodule SymphonyElixir.CodingAgentTest do
  use ExUnit.Case

  alias SymphonyElixir.Claude.Adapter, as: ClaudeAdapter
  alias SymphonyElixir.Codex.AppServer
  alias SymphonyElixir.CodingAgent
  alias SymphonyElixir.Cursor.Adapter, as: CursorAdapter

  import SymphonyElixir.TestSupport, only: [write_workflow_file!: 1, write_workflow_file!: 2]
  alias SymphonyElixir.Workflow

  setup do
    workflow_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-workflow-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(workflow_root)
    workflow_file = Path.join(workflow_root, "WORKFLOW.md")
    write_workflow_file!(workflow_file)
    Workflow.set_workflow_file_path(workflow_file)

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :workflow_file_path)
      File.rm_rf(workflow_root)
    end)

    :ok
  end

  test "AppServer compiles cleanly with @behaviour CodingAgent" do
    # @behaviour is verified at compile time; just check the module exists
    assert {:module, AppServer} == Code.ensure_compiled(AppServer)
    assert :erlang.function_exported(AppServer, :start_session, 2)
    assert :erlang.function_exported(AppServer, :run_turn, 4)
    assert :erlang.function_exported(AppServer, :stop_session, 1)
  end

  test "adapter/0 returns AppServer when kind is codex" do
    write_workflow_file!(Workflow.workflow_file_path(), agent_kind: "codex")
    assert CodingAgent.adapter() == AppServer
  end

  test "adapter/0 returns ClaudeAdapter when kind is claude" do
    write_workflow_file!(Workflow.workflow_file_path(), agent_kind: "claude")
    assert CodingAgent.adapter() == ClaudeAdapter
  end

  test "adapter/0 returns CursorAdapter when kind is cursor" do
    write_workflow_file!(Workflow.workflow_file_path(), agent_kind: "cursor")
    assert CodingAgent.adapter() == CursorAdapter
  end

  test "adapter/0 returns AppServer (default) when kind is omitted" do
    write_workflow_file!(Workflow.workflow_file_path())
    assert CodingAgent.adapter() == AppServer
  end

  test "kind_display_label/1 maps configured kinds to dashboard labels" do
    assert CodingAgent.kind_display_label("codex") == "Codex"
    assert CodingAgent.kind_display_label("claude") == "Claude Code"
    assert CodingAgent.kind_display_label("cursor") == "Cursor"
    assert CodingAgent.kind_display_label("future-kind") == "Future Kind"
  end

  test "ClaudeAdapter implements CodingAgent behaviour" do
    assert {:module, ClaudeAdapter} == Code.ensure_compiled(ClaudeAdapter)
    assert :erlang.function_exported(ClaudeAdapter, :start_session, 2)
    assert :erlang.function_exported(ClaudeAdapter, :run_turn, 4)
    assert :erlang.function_exported(ClaudeAdapter, :stop_session, 1)
  end

  test "CursorAdapter implements CodingAgent behaviour" do
    assert {:module, CursorAdapter} == Code.ensure_compiled(CursorAdapter)
    assert :erlang.function_exported(CursorAdapter, :start_session, 2)
    assert :erlang.function_exported(CursorAdapter, :run_turn, 4)
    assert :erlang.function_exported(CursorAdapter, :stop_session, 1)
  end
end
