defmodule SymphonyElixir.GitHubTrackerTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Linear.Issue
  alias SymphonyElixir.Tracker
  alias SymphonyElixir.Tracker.GitHub.Client

  test "github client fetches and normalizes candidate issues" do
    setup_fake_gh!("ok")

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "github",
      tracker_repo: "acme/repo",
      tracker_active_states: ["open"]
    )

    assert {:ok, issues} = Client.fetch_candidate_issues()
    assert length(issues) == 1

    issue = hd(issues)
    assert %Issue{} = issue
    assert issue.id == "101"
    assert issue.identifier == "gh-101"
    assert issue.title == "Open issue"
    assert issue.description == "Needs work"
    assert issue.state == "open"
    assert issue.labels == ["backend", "priority:high"]
    assert issue.assigned_to_worker
    assert %DateTime{} = issue.created_at
    assert %DateTime{} = issue.updated_at
  end

  test "github client handles missing repo and empty fetch filters" do
    setup_fake_gh!("ok")
    write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "github", tracker_repo: nil)

    assert {:error, :missing_github_repo} = Client.fetch_candidate_issues()
    assert {:ok, []} = Client.fetch_issues_by_states([])
    assert {:ok, []} = Client.fetch_issue_states_by_ids([])
  end

  test "github client filters by state and issue ids" do
    setup_fake_gh!("ok")
    write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "github", tracker_repo: "acme/repo")

    assert {:ok, state_filtered} = Client.fetch_issues_by_states(["OPEN", " closed "])
    assert Enum.map(state_filtered, & &1.id) == ["101", "102"]

    assert {:ok, id_filtered} = Client.fetch_issue_states_by_ids(["102", "999"])
    assert Enum.map(id_filtered, & &1.id) == ["102"]
  end

  test "github client reports cli and json failures" do
    setup_fake_gh!("bad_json")
    write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "github", tracker_repo: "acme/repo")
    assert {:error, :github_json_decode} = Client.fetch_candidate_issues()

    setup_fake_gh!("not_list")
    assert {:error, :github_unexpected_json} = Client.fetch_candidate_issues()

    setup_fake_gh!("error")
    assert {:error, {:github_cli, 17, "gh failed"}} = Client.fetch_candidate_issues()
  end

  test "github adapter writes comments and transitions issue state" do
    setup_fake_gh!("ok")
    write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "github", tracker_repo: "acme/repo")

    assert :ok = Tracker.create_comment("101", "looks good")
    assert :ok = Tracker.update_issue_state("101", "closed")
    assert :ok = Tracker.update_issue_state("101", "in progress")
  end

  test "github adapter returns errors when repo missing or cli fails" do
    setup_fake_gh!("ok")
    write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "github", tracker_repo: nil)

    assert {:error, :missing_github_repo} = Tracker.create_comment("101", "looks good")
    assert {:error, :missing_github_repo} = Tracker.update_issue_state("101", "closed")

    setup_fake_gh!("error")
    write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "github", tracker_repo: "acme/repo")

    assert {:error, {:github_cli, 17, "gh failed"}} = Tracker.create_comment("101", "looks good")
    assert {:error, {:github_cli, 17, "gh failed"}} = Tracker.update_issue_state("101", "closed")
  end

  defp setup_fake_gh!(mode) do
    test_root = Path.join(System.tmp_dir!(), "symphony-elixir-gh-#{System.unique_integer([:positive])}")
    fake_gh = Path.join(test_root, "gh")
    previous_path = System.get_env("PATH")
    previous_mode = System.get_env("SYMP_TEST_GH_MODE")

    File.mkdir_p!(test_root)

    File.write!(fake_gh, """
    #!/bin/sh
    mode="${SYMP_TEST_GH_MODE:-ok}"
    cmd="$1"
    subcmd="$2"

    if [ "$cmd" = "issue" ] && [ "$subcmd" = "list" ]; then
      case "$mode" in
        bad_json)
          printf '%s\\n' '{'
          exit 0
          ;;
        not_list)
          printf '%s\\n' '{"items":[]}'
          exit 0
          ;;
        error)
          printf '%s\\n' 'gh failed'
          exit 17
          ;;
        *)
          printf '%s\\n' '[{"number":101,"title":"Open issue","body":"Needs work","state":"open","labels":[{"name":"Backend"},{"name":"priority:high"}],"url":"https://github.example/issues/101","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-02T00:00:00Z","id":"gid-101"},{"number":102,"title":"Closed issue","body":"Already done","state":"closed","labels":[],"url":"https://github.example/issues/102","createdAt":"2026-01-03T00:00:00Z","updatedAt":"2026-01-04T00:00:00Z","id":"gid-102"}]'
          exit 0
          ;;
      esac
    fi

    if [ "$cmd" = "issue" ] && { [ "$subcmd" = "comment" ] || [ "$subcmd" = "close" ] || [ "$subcmd" = "reopen" ]; }; then
      case "$mode" in
        error)
          printf '%s\\n' 'gh failed'
          exit 17
          ;;
        *)
          exit 0
          ;;
      esac
    fi

    printf '%s\\n' 'unknown command'
    exit 99
    """)

    File.chmod!(fake_gh, 0o755)
    System.put_env("SYMP_TEST_GH_MODE", mode)
    System.put_env("PATH", test_root <> ":" <> (previous_path || ""))

    on_exit(fn ->
      restore_env("PATH", previous_path)
      restore_env("SYMP_TEST_GH_MODE", previous_mode)
      File.rm_rf(test_root)
    end)
  end
end
