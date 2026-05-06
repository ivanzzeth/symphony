defmodule SymphonyElixir.AgentRunnerTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.AgentRunner
  alias SymphonyElixir.Linear.Issue
  alias SymphonyElixir.Workflow

  defmodule FakeCodingAgent do
    @behaviour SymphonyElixir.CodingAgent

    @impl true
    def start_session(workspace, _opts) do
      {:ok, %{workspace: workspace, session_id: "seed-session", resume_id: nil}}
    end

    @impl true
    def run_turn(session, _prompt, _issue, opts) do
      _ = Keyword.get(opts, :on_message, fn _ -> :ok end)

      n = Process.get(:agent_runner_fake_turn_n, 0) + 1
      Process.put(:agent_runner_fake_turn_n, n)

      log = Process.get(:agent_runner_fake_log, [])
      Process.put(:agent_runner_fake_log, log ++ [{n, session[:resume_id]}])

      {:ok, %{session_id: "turn-out-#{n}", resume_id: "resume-after-#{n}"}}
    end

    @impl true
    def stop_session(_session), do: :ok
  end

  defp issue(id, identifier) do
    %Issue{
      id: id,
      identifier: identifier,
      title: "Agent runner unit test",
      description: "Coverage",
      state: "In Progress",
      url: "https://example.org/issues/#{identifier}",
      labels: []
    }
  end

  defp with_minimal_workspace(test_root, overrides, fun) do
    template_repo = Path.join(test_root, "source")
    workspace_root = Path.join(test_root, "workspaces")

    File.mkdir_p!(template_repo)
    File.write!(Path.join(template_repo, "README.md"), "# test")
    System.cmd("git", ["-C", template_repo, "init", "-b", "main"])
    System.cmd("git", ["-C", template_repo, "config", "user.name", "Test User"])
    System.cmd("git", ["-C", template_repo, "config", "user.email", "test@example.com"])
    System.cmd("git", ["-C", template_repo, "add", "README.md"])
    System.cmd("git", ["-C", template_repo, "commit", "-m", "initial"])

    write_workflow_file!(
      Workflow.workflow_file_path(),
      Keyword.merge(
        [
          workspace_root: workspace_root,
          hook_after_create: "cp #{Path.join(template_repo, "README.md")} README.md",
          codex_command: "true"
        ],
        overrides
      )
    )

    fun.(workspace_root)
  end

  setup do
    on_exit(fn ->
      Process.delete(:agent_runner_fake_turn_n)
      Process.delete(:agent_runner_fake_log)
      Process.delete(:agent_runner_fetch_n)
    end)

    :ok
  end

  test "merges resume_id from each turn into app_session for the next adapter.run_turn" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-agent-runner-resume-#{System.unique_integer([:positive])}"
      )

    try do
      with_minimal_workspace(
        test_root,
        [max_turns: 5],
        fn _workspace_root ->
          issue = issue("issue-resume", "AR-RESUME")

          state_fetcher = fn [_issue_id] ->
            n = (Process.get(:agent_runner_fetch_n) || 0) + 1
            Process.put(:agent_runner_fetch_n, n)
            state = if n < 3, do: "In Progress", else: "Done"
            {:ok, [Map.put(issue, :state, state)]}
          end

          assert :ok =
                   AgentRunner.run(issue, nil,
                     coding_agent_adapter: FakeCodingAgent,
                     issue_state_fetcher: state_fetcher
                   )

          log = Process.get(:agent_runner_fake_log, [])

          assert length(log) == 3

          assert {1, nil} == Enum.at(log, 0)
          assert {2, "resume-after-1"} == Enum.at(log, 1)
          assert {3, "resume-after-2"} == Enum.at(log, 2)
        end
      )
    after
      File.rm_rf(test_root)
    end
  end

  test "does not schedule another turn once max_turns is reached while issue stays active" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-agent-runner-max-#{System.unique_integer([:positive])}"
      )

    try do
      with_minimal_workspace(
        test_root,
        [max_turns: 3],
        fn _workspace_root ->
          issue = issue("issue-max", "AR-MAX")

          state_fetcher = fn [_issue_id] ->
            {:ok, [Map.put(issue, :state, "In Progress")]}
          end

          assert :ok =
                   AgentRunner.run(issue, nil,
                     coding_agent_adapter: FakeCodingAgent,
                     max_turns: 3,
                     issue_state_fetcher: state_fetcher
                   )

          n_turns = Process.get(:agent_runner_fake_turn_n, 0)
          assert n_turns == 3
        end
      )
    after
      File.rm_rf(test_root)
    end
  end
end
