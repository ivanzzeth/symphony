defmodule SymphonyElixir.CursorAdapterTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias SymphonyElixir.Cursor.Adapter, as: CursorAdapter

  import SymphonyElixir.TestSupport, only: [write_workflow_file!: 2, restore_env: 2]
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

  test "Turn 1 — completes successfully with --workspace flag, no --resume, resumes with real session_id" do
    %{binary: bin, trace: trace, workspace: ws, test_root: root} = setup_cursor_env("OK")

    session = %{session_id: "cs1", workspace: ws, resume_id: nil}
    test_pid = self()
    on_msg = fn m -> send(test_pid, {:m, m}) end

    write_cursor_config(bin, root)

    assert {:ok, result} = CursorAdapter.run_turn(session, "Fix bug", issue(), on_message: on_msg)

    assert result.input_tokens == 42
    assert result.output_tokens == 17
    # resume_id comes from real Cursor CLI session_id, not adapter-generated
    assert result.resume_id == "ok"

    assert_received {:m, %{event: :session_started, session_id: "ok"}}
    assert_received {:m, %{event: :notification}}
    assert_received {:m, %{event: :turn_completed}}

    args = File.read!(trace)
    assert args =~ "--workspace"
    assert args =~ "--force"
    assert args =~ "--trust"
    refute args =~ "--resume"
  end

  test "Turn 2 — uses --resume flag with real session_id" do
    %{binary: bin, trace: trace, workspace: ws, test_root: root} = setup_cursor_env("OK")
    write_cursor_config(bin, root)

    test_pid = self()
    on_msg = fn m -> send(test_pid, {:m, m}) end

    assert {:ok, result} =
             CursorAdapter.run_turn(
               %{session_id: "cs2", workspace: ws, resume_id: "ok"},
               "Continue",
               issue(),
               on_message: on_msg
             )

    assert_received {:m, %{event: :turn_completed}}
    assert result.resume_id == "ok"
    assert File.read!(trace) =~ "--resume ok"
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

  test "emits turn_timeout via on_message before returning error when stream stalls" do
    %{binary: bin, workspace: ws, test_root: root} = setup_cursor_env("STALL")
    write_cursor_config_stall(bin, root, codex_stream_timeout_ms: 120)

    test_pid = self()
    on_msg = fn m -> send(test_pid, {:m, m}) end

    assert {:error, :turn_timeout} =
             CursorAdapter.run_turn(
               %{session_id: "st", workspace: ws, resume_id: nil},
               "x",
               issue(),
               on_message: on_msg
             )

    assert_received {:m, %{event: :turn_timeout, timeout_ms: 120, adapter: :cursor}}
  end

  test "short line split across noeol emits buffer_exceeded, logs warning, and completes without crash" do
    prev = Application.get_env(:symphony_elixir, :coding_agent_port_line_bytes)
    Application.put_env(:symphony_elixir, :coding_agent_port_line_bytes, 64)

    on_exit(fn ->
      if prev == nil,
        do: Application.delete_env(:symphony_elixir, :coding_agent_port_line_bytes),
        else: Application.put_env(:symphony_elixir, :coding_agent_port_line_bytes, prev)
    end)

    %{binary: bin, workspace: ws, test_root: root} = setup_cursor_env("NOEOL")
    write_cursor_config(bin, root)

    test_pid = self()
    on_msg = fn m -> send(test_pid, {:m, m}) end

    log =
      capture_log(fn ->
        assert {:ok, _} =
                 CursorAdapter.run_turn(
                   %{session_id: "no", workspace: ws, resume_id: nil},
                   "x",
                   issue(),
                   on_message: on_msg
                 )
      end)

    assert log =~ "port line buffer"
    assert_received {:m, %{event: :buffer_exceeded, adapter: :cursor, chunk_bytes: 64}}
    assert_received {:m, %{event: :malformed}}
    assert_received {:m, %{event: :turn_completed}}
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

  test "remote SSH uses SSH.start_port for worker_host with Cursor CLI in remote command" do
    test_root = Path.join(System.tmp_dir!(), "symphony-elixir-cursor-ssh-#{System.unique_integer([:positive])}")
    File.mkdir_p!(test_root)

    prev_path = System.get_env("PATH")
    prev_ssh = System.get_env("SYMP_TEST_SSH_TRACE")

    on_exit(fn ->
      restore_env("PATH", prev_path)
      restore_env("SYMP_TEST_SSH_TRACE", prev_ssh)
      File.rm_rf(test_root)
    end)

    ssh_trace = Path.join(test_root, "ssh.trace")
    fake_ssh = Path.join(test_root, "ssh")
    fake_cursor = Path.join(test_root, "cursor")
    System.put_env("SYMP_TEST_SSH_TRACE", ssh_trace)
    System.put_env("PATH", test_root <> ":" <> (prev_path || ""))

    File.write!(fake_ssh, """
    #!/bin/sh
    printf 'ARGS:%s\\n' "$*" >> "#{ssh_trace}"
    printf '%s\\n' '{"type":"system","subtype":"init","session_id":"ssh-c"}'
    printf '%s\\n' '{"type":"result","subtype":"success","is_error":false,"result":"ok","usage":{"inputTokens":1,"outputTokens":1}}'
    exit 0
    """)

    File.chmod!(fake_ssh, 0o755)

    File.write!(fake_cursor, fake_cursor_script("OK", Path.join(test_root, "cursor.trace")))
    File.chmod!(fake_cursor, 0o755)

    remote = "/remote/workspace/issue-1"
    write_cursor_config("cursor", "/remote/workspaces")

    assert {:ok, _} =
             CursorAdapter.run_turn(
               %{session_id: "ssh", workspace: remote, resume_id: nil},
               "Fix bug",
               issue(),
               worker_host: "worker-01:2200"
             )

    trace = File.read!(ssh_trace)
    assert trace =~ "-T -p 2200 worker-01 bash -lc"
    assert trace =~ "cd "
    assert trace =~ remote
    assert trace =~ "cursor"
    assert trace =~ "agent"
    assert trace =~ "--print"
    assert trace =~ "--output-format"
    assert trace =~ "stream-json"
    assert trace =~ "--force"
    assert trace =~ "--trust"
    assert trace =~ "--workspace"
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

  defp write_cursor_config(binary, workspace_root, extra \\ []) do
    write_workflow_file!(
      Workflow.workflow_file_path(),
      Keyword.merge(
        [
          agent_kind: "cursor",
          workspace_root: workspace_root,
          agent_command: binary
        ],
        extra
      )
    )
  end

  defp write_cursor_config_stall(binary, workspace_root, opts) do
    write_workflow_file!(
      Workflow.workflow_file_path(),
      Keyword.merge(
        [agent_kind: "cursor", workspace_root: workspace_root, agent_command: binary],
        Keyword.take(opts, [:codex_stream_timeout_ms])
      )
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
printf '%s\\n' '{"type":"system","subtype":"init","session_id":"f","tools":["bash"]}'
printf '%s\\n' '{"type":"assistant","message":{"model":"gpt-5","usage":{"inputTokens":5,"outputTokens":3}}}'
printf '%s\\n' '{"type":"result","subtype":"error_during_execution","is_error":true,"errors":["boom"]}'
exit 0
)
  end

  defp fake_cursor_script("EXIT", trace) do
    ~s(#!/bin/sh
printf 'ARGS:%s\\n' "$*" >> "#{trace}"
printf '%s\\n' '{"type":"system","subtype":"init","session_id":"e"}'
exit 1
)
  end

  defp fake_cursor_script("STALL", trace) do
    ~s(#!/bin/sh
printf 'ARGS:%s\\n' "$*" >> "#{trace}"
printf '%s\\n' '{"type":"system","subtype":"init","session_id":"st"}'
sleep 3
printf '%s\\n' '{"type":"result","subtype":"success","is_error":false,"result":"late","usage":{"inputTokens":1,"outputTokens":1}}'
exit 0
)
  end

  defp fake_cursor_script("NOEOL", trace) do
    ~s(#!/bin/sh
printf 'ARGS:%s\\n' "$*" >> "#{trace}"
printf '%s\\n' '{"type":"system","subtype":"init","session_id":"noe","tools":["bash"]}'
awk 'BEGIN{for(i=0;i<100;i++)printf "x";print ""}'
printf '%s\\n' '{"type":"result","subtype":"success","is_error":false,"result":"ok","usage":{"inputTokens":1,"outputTokens":1}}'
exit 0
)
  end

  defp fake_cursor_script("MALFORMED", trace) do
    ~s(#!/bin/sh
printf 'ARGS:%s\\n' "$*" >> "#{trace}"
printf '%s\\n' '{"type":"system","subtype":"init","session_id":"m"}'
printf '%s\\n' 'not json at all'
printf '%s\\n' '{"type":"result","subtype":"success","is_error":false,"result":"ok","usage":{"inputTokens":1,"outputTokens":1}}'
exit 0
)
  end

  defp fake_cursor_script(_ok, trace) do
    ~s(#!/bin/sh
printf 'ARGS:%s\\n' "$*" >> "#{trace}"
printf '%s\\n' '{"type":"system","subtype":"init","session_id":"ok","tools":["bash","read","write"]}'
printf '%s\\n' '{"type":"assistant","message":{"model":"gpt-5","content":[{"type":"text","text":"fixed"}],"usage":{"inputTokens":42,"outputTokens":17}}}'
printf '%s\\n' '{"type":"result","subtype":"success","is_error":false,"result":"done","usage":{"inputTokens":42,"outputTokens":17}}'
exit 0
)
  end
end
