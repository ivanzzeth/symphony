defmodule SymphonyElixir.SpecsCheckTest do
  # async: false — CodingAgent contract tests set :workflow_file_path Application env.
  use ExUnit.Case, async: false

  alias SymphonyElixir.SpecsCheck

  import SymphonyElixir.TestSupport, only: [write_workflow_file!: 2]

  alias SymphonyElixir.Claude.Adapter, as: ClaudeAdapter
  alias SymphonyElixir.Codex.AppServer
  alias SymphonyElixir.Cursor.Adapter, as: CursorAdapter
  alias SymphonyElixir.Workflow

  test "reports missing @spec for public functions" do
    dir = create_tmp_dir()

    write_module!(dir, "sample.ex", """
    defmodule Sample do
      def missing(arg), do: arg
    end
    """)

    findings = SpecsCheck.missing_public_specs([dir])

    assert Enum.map(findings, &SpecsCheck.finding_identifier/1) == ["Sample.missing/1"]
  end

  test "accepts adjacent @spec on public function" do
    dir = create_tmp_dir()

    write_module!(dir, "sample.ex", """
    defmodule Sample do
      @spec ok(term()) :: term()
      def ok(arg), do: arg
    end
    """)

    assert SpecsCheck.missing_public_specs([dir]) == []
  end

  test "allows defp without @spec" do
    dir = create_tmp_dir()

    write_module!(dir, "sample.ex", """
    defmodule Sample do
      def public do
        helper(:ok)
      end

      defp helper(value), do: value
    end
    """)

    findings = SpecsCheck.missing_public_specs([dir])

    assert Enum.map(findings, &SpecsCheck.finding_identifier/1) == ["Sample.public/0"]
  end

  test "exempts callback implementations marked with @impl" do
    dir = create_tmp_dir()

    write_module!(dir, "worker.ex", """
    defmodule Worker do
      @behaviour GenServer

      @impl true
      def init(state), do: {:ok, state}
    end
    """)

    assert SpecsCheck.missing_public_specs([dir]) == []
  end

  test "honors explicit exemptions list" do
    dir = create_tmp_dir()

    write_module!(dir, "sample.ex", """
    defmodule Sample do
      def legacy(arg), do: arg
    end
    """)

    findings = SpecsCheck.missing_public_specs([dir], exemptions: ["Sample.legacy/1"])

    assert findings == []
  end

  describe "CodingAgent contract — Codex AppServer" do
    setup do
      workflow_root =
        Path.join(
          System.tmp_dir!(),
          "specs-check-codex-#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(workflow_root)
      workflow_file = Path.join(workflow_root, "WORKFLOW.md")
      write_workflow_file!(workflow_file, agent_kind: "codex")
      Workflow.set_workflow_file_path(workflow_file)

      on_exit(fn ->
        Application.delete_env(:symphony_elixir, :workflow_file_path)
        File.rm_rf(workflow_root)
      end)

      :ok
    end

    test "exports CodingAgent callbacks (behaviour checked at compile time)" do
      assert {:module, AppServer} == Code.ensure_compiled(AppServer)
      assert :erlang.function_exported(AppServer, :start_session, 2)
      assert :erlang.function_exported(AppServer, :run_turn, 4)
      assert :erlang.function_exported(AppServer, :stop_session, 1)
    end
  end

  describe "CodingAgent contract — Claude adapter" do
    # Fake CLI + Port stream-json can exceed the default 60s ExUnit timeout under CI load.
    @describetag timeout: 120_000

    setup do
      workflow_root =
        Path.join(
          System.tmp_dir!(),
          "specs-check-claude-#{System.unique_integer([:positive])}"
        )

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

    test "start_session returns {:ok, %{session_id: _, workspace: _}}" do
      workspace =
        Path.join(
          System.tmp_dir!(),
          "specs-check-claude-ws-#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(workspace)

      assert {:ok, %{session_id: session_id, workspace: ws}} =
               ClaudeAdapter.start_session(workspace, [])

      assert is_binary(session_id)
      assert ws == workspace
    end

    test "run_turn returns {:ok, %{input_tokens: _, output_tokens: _, resume_id: _}}" do
      %{binary: bin, workspace: ws, test_root: root} = setup_claude_ok_env()
      write_claude_config(bin, root)

      test_pid = self()
      on_msg = fn m -> send(test_pid, {:m, m}) end

      assert {:ok,
              %{
                input_tokens: input_tokens,
                output_tokens: output_tokens,
                resume_id: resume_id
              }} =
               ClaudeAdapter.run_turn(
                 %{session_id: "cl-spec", workspace: ws, resume_id: nil},
                 "Fix bug",
                 coding_agent_issue(),
                 on_message: on_msg
               )

      assert is_integer(input_tokens)
      assert is_integer(output_tokens)
      assert resume_id == "ok"
      assert_received {:m, %{event: :turn_completed}}
    end
  end

  describe "CodingAgent contract — Cursor adapter" do
    @describetag timeout: 120_000

    setup do
      workflow_root =
        Path.join(
          System.tmp_dir!(),
          "specs-check-cursor-contract-#{System.unique_integer([:positive])}"
        )

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

    test "exports CodingAgent callbacks (behaviour checked at compile time)" do
      assert {:module, CursorAdapter} == Code.ensure_compiled(CursorAdapter)
      assert :erlang.function_exported(CursorAdapter, :start_session, 2)
      assert :erlang.function_exported(CursorAdapter, :run_turn, 4)
      assert :erlang.function_exported(CursorAdapter, :stop_session, 1)
    end

    test "start_session returns {:ok, %{session_id: _, workspace: _}}" do
      workspace =
        Path.join(
          System.tmp_dir!(),
          "specs-check-cursor-ws-#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(workspace)

      assert {:ok, %{session_id: session_id, workspace: ws}} =
               CursorAdapter.start_session(workspace, [])

      assert is_binary(session_id)
      assert ws == workspace
    end

    test "run_turn returns {:ok, %{input_tokens: _, output_tokens: _, resume_id: _}}" do
      %{binary: bin, workspace: ws, test_root: root} = setup_cursor_ok_env()
      write_cursor_config(bin, root)

      test_pid = self()
      on_msg = fn m -> send(test_pid, {:m, m}) end

      assert {:ok,
              %{
                input_tokens: input_tokens,
                output_tokens: output_tokens,
                resume_id: resume_id
              }} =
               CursorAdapter.run_turn(
                 %{session_id: "cs-spec", workspace: ws, resume_id: nil},
                 "Fix bug",
                 coding_agent_issue(),
                 on_message: on_msg
               )

      assert is_integer(input_tokens)
      assert is_integer(output_tokens)
      assert resume_id == "ok"
      assert_received {:m, %{event: :turn_completed}}
    end
  end

  defp create_tmp_dir do
    unique = :erlang.unique_integer([:positive, :monotonic])
    dir = Path.join(System.tmp_dir!(), "specs-check-test-#{unique}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end

  defp write_module!(dir, rel_path, source) do
    path = Path.join(dir, rel_path)
    File.write!(path, source)
  end

  defp coding_agent_issue do
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

  defp write_claude_config(binary, workspace_root) do
    write_workflow_file!(Workflow.workflow_file_path(),
      agent_kind: "claude",
      workspace_root: workspace_root,
      agent_command: line_buffered_cli(binary)
    )
  end

  defp write_cursor_config(binary, workspace_root) do
    write_workflow_file!(Workflow.workflow_file_path(),
      agent_kind: "cursor",
      workspace_root: workspace_root,
      agent_command: line_buffered_cli(binary)
    )
  end

  # Fake CLIs run without a TTY; stdout can be fully buffered so the Port never
  # sees newlines until ExUnit's default 60s test timeout. `stdbuf` forces
  # line-buffered stdout/stderr when coreutils is available.
  defp line_buffered_cli(binary) do
    case System.find_executable("stdbuf") do
      nil -> binary
      stdbuf -> "#{stdbuf} -oL -eL #{binary}"
    end
  end

  defp setup_claude_ok_env do
    root =
      Path.join(System.tmp_dir!(), "specs-check-claude-cli-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)

    ws = Path.join(root, "workspace")
    File.mkdir_p!(ws)

    binary = Path.join(root, "claude")
    trace = Path.join(root, "trace")

    File.write!(binary, fake_claude_ok_script(trace))
    File.chmod!(binary, 0o755)

    on_exit(fn -> File.rm_rf(root) end)

    %{binary: binary, trace: trace, workspace: ws, test_root: root}
  end

  defp fake_claude_ok_script(trace) do
    ~s(#!/bin/sh
printf 'ARGS:%s\\n' "$*" >> "#{trace}"
printf '%s\\n' '{"type":"system","subtype":"init","session_id":"ok","tools":["bash"]}'
printf '%s\\n' '{"type":"assistant","message":{"model":"sonnet","usage":{"input_tokens":42,"output_tokens":17}}}'
printf '%s\\n' '{"type":"result","subtype":"success","is_error":false,"result":"done","usage":{"input_tokens":42,"output_tokens":17}}'
exit 0
)
  end

  defp setup_cursor_ok_env do
    root =
      Path.join(System.tmp_dir!(), "specs-check-cursor-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)

    ws = Path.join(root, "workspace")
    File.mkdir_p!(ws)

    binary = Path.join(root, "cursor")
    trace = Path.join(root, "trace")

    File.write!(binary, fake_cursor_ok_script(trace))
    File.chmod!(binary, 0o755)

    on_exit(fn -> File.rm_rf(root) end)

    %{binary: binary, trace: trace, workspace: ws, test_root: root}
  end

  defp fake_cursor_ok_script(trace) do
    ~s(#!/bin/sh
printf 'ARGS:%s\\n' "$*" >> "#{trace}"
printf '%s\\n' '{"type":"system","subtype":"init","session_id":"ok","tools":["bash","read","write"]}'
printf '%s\\n' '{"type":"assistant","message":{"model":"gpt-5","content":[{"type":"text","text":"fixed"}],"usage":{"inputTokens":42,"outputTokens":17}}}'
printf '%s\\n' '{"type":"result","subtype":"success","is_error":false,"result":"done","usage":{"inputTokens":42,"outputTokens":17}}'
exit 0
)
  end
end
