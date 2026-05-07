defmodule SymphonyElixir.ClaudeAdapterTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias SymphonyElixir.Claude.Adapter, as: ClaudeAdapter

  import SymphonyElixir.TestSupport, only: [write_workflow_file!: 2, restore_env: 2]
  alias SymphonyElixir.Workflow

  setup do
    workflow_root = Path.join(System.tmp_dir!(), "symphony-elixir-claude-adapter-#{System.unique_integer([:positive])}")

    File.mkdir_p!(workflow_root)
    workflow_file = Path.join(workflow_root, "WORKFLOW.md")
    write_workflow_file!(workflow_file, agent_kind: "claude")
    Workflow.set_workflow_file_path(workflow_file)

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :workflow_file_path)
      File.rm_rf(workflow_root)
    end)

    :ok
  end

  test "start_session returns session map with session_id and workspace" do
    workspace = System.tmp_dir!()
    assert {:ok, session} = ClaudeAdapter.start_session(workspace, [])
    assert is_binary(session.session_id)
    assert session.workspace == workspace
    assert session.resume_id == nil
  end

  test "stop_session is a no-op" do
    assert ClaudeAdapter.stop_session(%{}) == :ok
  end

  # --- run_turn tests ---

  test "Turn 1 — completes successfully and emits session_started, notification, turn_completed" do
    %{binary: bin, trace: trace, workspace: ws, test_root: root} = setup_claude_env("OK")

    session = %{session_id: "s1", workspace: ws, resume_id: nil}
    test_pid = self()
    on_msg = fn m -> send(test_pid, {:m, m}) end

    write_claude_config(bin, root)

    assert {:ok, result} = ClaudeAdapter.run_turn(session, "Fix bug", issue(), on_message: on_msg)

    assert result.input_tokens == 42
    assert result.output_tokens == 17
    assert result.resume_id == "s1"
    assert_received {:m, %{event: :session_started}}
    assert_received {:m, %{event: :notification}}
    assert_received {:m, %{event: :turn_completed}}
    assert File.read!(trace) =~ "--session-id s1"
  end

  test "Turn 2 — uses --resume flag" do
    %{binary: bin, trace: trace, workspace: ws, test_root: root} = setup_claude_env("OK")

    session = %{session_id: "s2", workspace: ws, resume_id: "s2"}
    test_pid = self()
    on_msg = fn m -> send(test_pid, {:m, m}) end

    write_claude_config(bin, root)

    assert {:ok, _} = ClaudeAdapter.run_turn(session, "Continue", issue(), on_message: on_msg)

    assert_received {:m, %{event: :turn_completed}}
    assert File.read!(trace) =~ "--resume s2"
  end

  test "returns {:ok, result} with resume_id for next turn" do
    %{binary: bin, workspace: ws, test_root: root} = setup_claude_env("OK")
    write_claude_config(bin, root)

    session = %{session_id: "s-resume", workspace: ws, resume_id: nil}
    assert {:ok, result} = ClaudeAdapter.run_turn(session, "Fix bug", issue())
    assert result.resume_id == "s-resume"
  end

  test "returns error on turn failure" do
    %{binary: bin, workspace: ws, test_root: root} = setup_claude_env("FAIL")
    write_claude_config(bin, root)

    test_pid = self()
    on_msg = fn m -> send(test_pid, {:m, m}) end

    assert {:error, _} =
             ClaudeAdapter.run_turn(
               %{session_id: "sf", workspace: ws, resume_id: nil},
               "x",
               issue(),
               on_message: on_msg
             )

    assert_received {:m, %{event: :turn_failed}}
  end

  test "returns error on process exit without completion" do
    %{binary: bin, workspace: ws, test_root: root} = setup_claude_env("EXIT")
    write_claude_config(bin, root)

    assert {:error, {:port_exit, 1}} =
             ClaudeAdapter.run_turn(
               %{session_id: "sx", workspace: ws, resume_id: nil},
               "x",
               issue()
             )
  end

  test "emits turn_timeout via on_message before returning error when stream stalls" do
    %{binary: bin, workspace: ws, test_root: root} = setup_claude_env("STALL")
    write_claude_config_stall(bin, root, codex_stream_timeout_ms: 120)

    test_pid = self()
    on_msg = fn m -> send(test_pid, {:m, m}) end

    assert {:error, :turn_timeout} =
             ClaudeAdapter.run_turn(
               %{session_id: "st", workspace: ws, resume_id: nil},
               "x",
               issue(),
               on_message: on_msg
             )

    assert_received {:m, %{event: :turn_timeout, timeout_ms: 120, adapter: :claude}}
  end

  test "emits turn_timeout via on_message when stream is idle past stream_timeout_ms" do
    %{binary: bin, workspace: ws, test_root: root} = setup_claude_env("SLOW")
    write_claude_config(bin, root, codex_stream_timeout_ms: 200)

    test_pid = self()
    on_msg = fn m -> send(test_pid, {:m, m}) end

    assert {:error, :turn_timeout} =
             ClaudeAdapter.run_turn(
               %{session_id: "st-slow", workspace: ws, resume_id: nil},
               "x",
               issue(),
               on_message: on_msg
             )

    assert_received {:m, %{event: :session_started}}
    assert_received {:m, %{event: :turn_timeout, timeout_ms: 200, adapter: :claude}}
  end

  test "short line split across noeol emits buffer_exceeded and completes without crash" do
    prev = Application.get_env(:symphony_elixir, :coding_agent_port_line_bytes)
    Application.put_env(:symphony_elixir, :coding_agent_port_line_bytes, 64)

    on_exit(fn ->
      if prev == nil,
        do: Application.delete_env(:symphony_elixir, :coding_agent_port_line_bytes),
        else: Application.put_env(:symphony_elixir, :coding_agent_port_line_bytes, prev)
    end)

    %{binary: bin, workspace: ws, test_root: root} = setup_claude_env("NOEOL")
    write_claude_config(bin, root)

    test_pid = self()
    on_msg = fn m -> send(test_pid, {:m, m}) end

    log =
      capture_log(fn ->
        assert {:ok, _} =
                 ClaudeAdapter.run_turn(
                   %{session_id: "no", workspace: ws, resume_id: nil},
                   "x",
                   issue(),
                   on_message: on_msg
                 )
      end)

    assert log =~ "exceeded port line buffer"
    assert_received {:m, %{event: :buffer_exceeded, adapter: :claude, chunk_bytes: 64}}
    assert_received {:m, %{event: :malformed}}
    assert_received {:m, %{event: :turn_completed}}
  end

  test "emits malformed event for non-JSON lines without crashing" do
    %{binary: bin, workspace: ws, test_root: root} = setup_claude_env("MALFORMED")
    write_claude_config(bin, root)

    test_pid = self()
    on_msg = fn m -> send(test_pid, {:m, m}) end

    assert {:ok, _} =
             ClaudeAdapter.run_turn(
               %{session_id: "sm", workspace: ws, resume_id: nil},
               "x",
               issue(),
               on_message: on_msg
             )

    assert_received {:m, %{event: :turn_completed}}
    assert_received {:m, %{event: :malformed}}
  end

  @tag :slow
  test "oversized line without newline emits buffer_exceeded and completes without crashing" do
    %{binary: bin, workspace: ws, test_root: root} = setup_claude_env("HUGE_LINE")
    write_claude_config(bin, root)

    test_pid = self()
    on_msg = fn m -> send(test_pid, {:m, m}) end

    assert {:ok, _} =
             ClaudeAdapter.run_turn(
               %{session_id: "hl", workspace: ws, resume_id: nil},
               "x",
               issue(),
               on_message: on_msg
             )

    assert_receive {:m, %{event: :buffer_exceeded}}, 10_000
    assert_received {:m, %{event: :turn_completed}}
  end

  test "remote SSH uses SSH.start_port for worker_host" do
    test_root = Path.join(System.tmp_dir!(), "symphony-elixir-claude-ssh-#{System.unique_integer([:positive])}")
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
    fake_claude = Path.join(test_root, "claude")
    System.put_env("SYMP_TEST_SSH_TRACE", ssh_trace)
    System.put_env("PATH", test_root <> ":" <> (prev_path || ""))

    File.write!(fake_ssh, """
    #!/bin/sh
    printf 'ARGS:%s\\n' "$*" >> "#{ssh_trace}"
    printf '%s\\n' '{"type":"system","subtype":"init","session_id":"ssh-s"}'
    printf '%s\\n' '{"type":"result","subtype":"success","is_error":false,"result":"ok","usage":{"input_tokens":1,"output_tokens":1}}'
    exit 0
    """)

    File.chmod!(fake_ssh, 0o755)

    File.write!(fake_claude, fake_claude_script("OK", Path.join(test_root, "claude.trace")))
    File.chmod!(fake_claude, 0o755)

    remote = "/remote/workspace/issue-1"
    write_claude_config("claude", "/remote/workspaces")

    assert {:ok, _} =
             ClaudeAdapter.run_turn(
               %{session_id: "ssh", workspace: remote, resume_id: nil},
               "Fix bug",
               issue(),
               worker_host: "worker-01:2200"
             )

    trace = File.read!(ssh_trace)
    assert trace =~ "-T -p 2200 worker-01 bash -lc"
    assert trace =~ "cd "
    assert trace =~ remote
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

  defp write_claude_config(binary, workspace_root, extra \\ []) when is_list(extra) do
    write_workflow_file!(
      Workflow.workflow_file_path(),
      Keyword.merge(
        [agent_kind: "claude", workspace_root: workspace_root, agent_command: binary],
        extra
      )
    )
  end

  defp write_claude_config_stall(binary, workspace_root, opts) do
    write_workflow_file!(
      Workflow.workflow_file_path(),
      Keyword.merge(
        [agent_kind: "claude", workspace_root: workspace_root, agent_command: binary],
        Keyword.take(opts, [:codex_stream_timeout_ms])
      )
    )
  end

  defp setup_claude_env(scenario) do
    root = Path.join(System.tmp_dir!(), "symphony-elixir-claude-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)

    ws = Path.join(root, "workspace")
    File.mkdir_p!(ws)

    binary = Path.join(root, "claude")
    trace = Path.join(root, "trace")

    File.write!(binary, fake_claude_script(scenario, trace))
    File.chmod!(binary, 0o755)

    on_exit(fn -> File.rm_rf(root) end)

    %{binary: binary, trace: trace, workspace: ws, test_root: root}
  end

  defp fake_claude_script("FAIL", trace) do
    ~s(#!/bin/sh
printf 'ARGS:%s\\n' "$*" >> "#{trace}"
printf '%s\\n' '{"type":"system","subtype":"init","session_id":"f","tools":["bash"]}'
printf '%s\\n' '{"type":"assistant","message":{"model":"s","usage":{"input_tokens":5,"output_tokens":3}}}'
printf '%s\\n' '{"type":"result","subtype":"error_during_execution","is_error":true,"errors":["boom"]}'
exit 0
)
  end

  defp fake_claude_script("EXIT", trace) do
    ~s(#!/bin/sh
printf 'ARGS:%s\\n' "$*" >> "#{trace}"
printf '%s\\n' '{"type":"system","subtype":"init","session_id":"e"}'
exit 1
)
  end

  defp fake_claude_script("STALL", trace) do
    ~s(#!/bin/sh
printf 'ARGS:%s\\n' "$*" >> "#{trace}"
printf '%s\\n' '{"type":"system","subtype":"init","session_id":"st"}'
sleep 3
printf '%s\\n' '{"type":"result","subtype":"success","is_error":false,"result":"late","usage":{"input_tokens":1,"output_tokens":1}}'
exit 0
)
  end

  defp fake_claude_script("NOEOL", trace) do
    ~s(#!/bin/sh
printf 'ARGS:%s\\n' "$*" >> "#{trace}"
printf '%s\\n' '{"type":"system","subtype":"init","session_id":"noe","tools":["bash"]}'
awk 'BEGIN{for(i=0;i<100;i++)printf "x";print ""}'
printf '%s\\n' '{"type":"result","subtype":"success","is_error":false,"result":"ok","usage":{"input_tokens":1,"output_tokens":1}}'
exit 0
)
  end

  defp fake_claude_script("BIGLINE", trace) do
    ~s(#!/bin/sh
printf 'ARGS:%s\\n' "$*" >> "#{trace}"
printf '%s\\n' '{"type":"system","subtype":"init","session_id":"big"}'
python3 <<'PY'
import sys
sys.stdout.buffer.write(b' ' * (1048576 + 1))
sys.stdout.buffer.write(b'\\n')
sys.stdout.flush()
PY
printf '%s\\n' '{"type":"result","subtype":"success","is_error":false,"result":"ok","usage":{"input_tokens":1,"output_tokens":1}}'
exit 0
)
  end

  defp fake_claude_script("SLOW", trace) do
    ~s(#!/bin/sh
printf 'ARGS:%s\\n' "$*" >> "#{trace}"
printf '%s\\n' '{"type":"system","subtype":"init","session_id":"slow","tools":["bash"]}'
sleep 3
exit 0
)
  end

  defp fake_claude_script("HUGE_LINE", trace) do
    ~s(#!/bin/sh
printf 'ARGS:%s\\n' "$*" >> "#{trace}"
printf '%s\\n' '{"type":"system","subtype":"init","session_id":"huge","tools":["bash"]}'
perl -e 'print "x" x 2_000_000; print "\\n"'
printf '%s\\n' '{"type":"assistant","message":{"model":"s","usage":{"input_tokens":1,"output_tokens":1}}}'
printf '%s\\n' '{"type":"result","subtype":"success","is_error":false,"result":"ok","usage":{"input_tokens":1,"output_tokens":1}}'
exit 0
)
  end

  defp fake_claude_script("MALFORMED", trace) do
    ~s(#!/bin/sh
printf 'ARGS:%s\\n' "$*" >> "#{trace}"
printf '%s\\n' '{"type":"system","subtype":"init","session_id":"m"}'
printf '%s\\n' 'not json at all'
printf '%s\\n' '{"type":"result","subtype":"success","is_error":false,"result":"ok","usage":{"input_tokens":1,"output_tokens":1}}'
exit 0
)
  end

  defp fake_claude_script(_ok, trace) do
    ~s(#!/bin/sh
printf 'ARGS:%s\\n' "$*" >> "#{trace}"
printf '%s\\n' '{"type":"system","subtype":"init","session_id":"ok","tools":["bash","read","write"]}'
printf '%s\\n' '{"type":"assistant","message":{"model":"sonnet","content":[{"type":"text","text":"fixed"}],"usage":{"input_tokens":42,"output_tokens":17}}}'
printf '%s\\n' '{"type":"result","subtype":"success","is_error":false,"result":"done","usage":{"input_tokens":42,"output_tokens":17}}'
exit 0
)
  end
end
