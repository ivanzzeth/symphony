defmodule SymphonyElixir.CursorAdapterTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Cursor.Adapter, as: CursorAdapter

  import SymphonyElixir.TestSupport, only: [write_workflow_file!: 2]
  alias SymphonyElixir.Workflow

  setup do
    workflow_root = Path.join(System.tmp_dir!(), "symphony-elixir-cursor-adapter-#{System.unique_integer([:positive])}")

    File.mkdir_p!(workflow_root)
    workflow_file = Path.join(workflow_root, "WORKFLOW.md")
    write_workflow_file!(workflow_file, agent_kind: "cursor")
    Workflow.set_workflow_file_path(workflow_file)

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :workflow_file_path)
      File.rm_rf(workflow_root)
    end)

    :ok
  end

  test "start_session returns session map with session_id and workspace" do
    workspace = System.tmp_dir!()
    assert {:ok, session} = CursorAdapter.start_session(workspace, [])
    assert is_binary(session.session_id)
    assert session.workspace == workspace
    assert session.resume_id == nil
  end

  test "stop_session is a no-op" do
    assert CursorAdapter.stop_session(%{}) == :ok
  end

  test "Turn 1 — completes successfully with --workspace flag, no --resume" do
    %{binary: bin, trace: trace, workspace: ws, test_root: root} = setup_cursor_env("OK")

    session = %{session_id: "cs1", workspace: ws, resume_id: nil}
    test_pid = self()
    on_msg = fn m -> send(test_pid, {:m, m}) end

    write_cursor_config(bin, root)

    assert {:ok, result} = CursorAdapter.run_turn(session, "Fix bug", issue(), on_message: on_msg)

    assert result.input_tokens == 42
    assert result.output_tokens == 17
    assert result.resume_id == "cs1"
    assert_received {:m, %{event: :session_started}}
    assert_received {:m, %{event: :notification}}
    assert_received {:m, %{event: :turn_completed}}

    args = File.read!(trace)
    assert args =~ "--workspace"
    assert args =~ "--force"
    assert args =~ "--trust"
    refute args =~ "--resume"
  end

  test "Turn 2 — uses --resume flag with chatId" do
    %{binary: bin, trace: trace, workspace: ws, test_root: root} = setup_cursor_env("OK")

    session = %{session_id: "cs2", workspace: ws, resume_id: "cs2"}
    test_pid = self()
    on_msg = fn m -> send(test_pid, {:m, m}) end

    write_cursor_config(bin, root)

    assert {:ok, _} = CursorAdapter.run_turn(session, "Continue", issue(), on_message: on_msg)
    assert_received {:m, %{event: :turn_completed}}
    assert File.read!(trace) =~ "--resume cs2"
  end

  test "returns error on turn failure" do
    %{binary: bin, workspace: ws, test_root: root} = setup_cursor_env("FAIL")
    write_cursor_config(bin, root)

    test_pid = self()
    on_msg = fn m -> send(test_pid, {:m, m}) end

    assert {:error, _} =
             CursorAdapter.run_turn(
               %{session_id: "sf", workspace: ws, resume_id: nil},
               "x",
               issue(),
               on_message: on_msg
             )

    assert_received {:m, %{event: :turn_failed}}
  end

  test "returns error on process exit without completion" do
    %{binary: bin, workspace: ws, test_root: root} = setup_cursor_env("EXIT")
    write_cursor_config(bin, root)

    assert {:error, {:port_exit, 1}} =
             CursorAdapter.run_turn(
               %{session_id: "sx", workspace: ws, resume_id: nil},
               "x",
               issue()
             )
  end

  test "emits malformed event for non-JSON lines without crashing" do
    %{binary: bin, workspace: ws, test_root: root} = setup_cursor_env("MALFORMED")
    write_cursor_config(bin, root)

    test_pid = self()
    on_msg = fn m -> send(test_pid, {:m, m}) end

    assert {:ok, _} =
             CursorAdapter.run_turn(
               %{session_id: "sm", workspace: ws, resume_id: nil},
               "x",
               issue(),
               on_message: on_msg
             )

    assert_received {:m, %{event: :turn_completed}}
    assert_received {:m, %{event: :malformed}}
  end

  # --- helpers ---

  defp issue do
    %SymphonyElixir.Linear.Issue{
      id: "issue-1",
      identifier: "MT-1",
      title: "Bug",
      description: "Fix it",
      state: "In Progress",
      url: "https://example.org/issues/MT-1",
      labels: ["backend"]
    }
  end

  defp write_cursor_config(binary, workspace_root) do
    write_workflow_file!(Workflow.workflow_file_path(),
      agent_kind: "cursor",
      workspace_root: workspace_root,
      agent_command: binary
    )
  end

  defp setup_cursor_env(scenario) do
    root = Path.join(System.tmp_dir!(), "symphony-elixir-cursor-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)

    ws = Path.join(root, "workspace")
    File.mkdir_p!(ws)

    binary = Path.join(root, "cursor")
    trace = Path.join(root, "trace")

    File.write!(binary, fake_cursor_script(scenario, trace))
    File.chmod!(binary, 0o755)

    on_exit(fn -> File.rm_rf(root) end)

    %{binary: binary, trace: trace, workspace: ws, test_root: root}
  end

  defp fake_cursor_script("FAIL", trace) do
    ~s(#!/bin/sh
printf 'ARGS:%s\\n' "$*" >> "#{trace}"
printf '%s\\n' '{"type":"system","subtype":"init","chatId":"f","tools":["bash"]}'
printf '%s\\n' '{"type":"assistant","message":{"model":"gpt-5","usage":{"input_tokens":5,"output_tokens":3}}}'
printf '%s\\n' '{"type":"result","subtype":"error_during_execution","is_error":true,"errors":["boom"]}'
exit 0
)
  end

  defp fake_cursor_script("EXIT", trace) do
    ~s(#!/bin/sh
printf 'ARGS:%s\\n' "$*" >> "#{trace}"
printf '%s\\n' '{"type":"system","subtype":"init","chatId":"e"}'
exit 1
)
  end

  defp fake_cursor_script("MALFORMED", trace) do
    ~s(#!/bin/sh
printf 'ARGS:%s\\n' "$*" >> "#{trace}"
printf '%s\\n' '{"type":"system","subtype":"init","chatId":"m"}'
printf '%s\\n' 'not json at all'
printf '%s\\n' '{"type":"result","subtype":"success","is_error":false,"result":"ok","usage":{"input_tokens":1,"output_tokens":1}}'
exit 0
)
  end

  defp fake_cursor_script(_ok, trace) do
    ~s(#!/bin/sh
printf 'ARGS:%s\\n' "$*" >> "#{trace}"
printf '%s\\n' '{"type":"system","subtype":"init","chatId":"ok","tools":["bash","read","write"]}'
printf '%s\\n' '{"type":"assistant","message":{"model":"gpt-5","content":[{"type":"text","text":"fixed"}],"usage":{"input_tokens":42,"output_tokens":17}}}'
printf '%s\\n' '{"type":"result","subtype":"success","is_error":false,"result":"done","usage":{"input_tokens":42,"output_tokens":17}}'
exit 0
)
  end
end
