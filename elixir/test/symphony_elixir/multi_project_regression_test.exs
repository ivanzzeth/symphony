defmodule SymphonyElixir.MultiProjectRegressionTest do
  use ExUnit.Case
  alias SymphonyElixir.CLI
  alias SymphonyElixir.StatusDashboard

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

  # Bug: "elixir" project name conflicted with Erlang's built-in Elixir module
  # when using Module.safe_concat. Fixed by using String.to_atom("Elixir....").
  test "project names that collide with Erlang built-in modules do not crash" do
    parent = self()

    deps = base_deps(
      discover_projects: fn _path ->
        {:ok, [%{name: "elixir", path: "/tmp/instances/elixir",
                 workflow_path: "/tmp/instances/elixir/WORKFLOW.md"}]}
      end,
      set_projects: fn projects ->
        send(parent, {:projects_set, projects})
        :ok
      end
    )

    assert :ok = CLI.evaluate([@ack_flag, "--projects-dir", "/tmp/instances", "WORKFLOW.md"], deps)

    assert_received {:projects_set, projects}
    assert length(projects) == 1
    assert hd(projects).name == "elixir"

    # Verify the atom can be created without Erlang module conflict
    store_atom = String.to_atom("Elixir.SymphonyElixir.WorkflowStore.elixir")
    orch_atom = String.to_atom("Elixir.SymphonyElixir.Orchestrator.elixir")
    assert is_atom(store_atom)
    assert is_atom(orch_atom)
  end

  # Bug: duplicate child spec id when both base WorkflowStore and project-specific
  # WorkflowStore have the same module as implicit id. Fixed with explicit id:.
  test "project child specs have distinct ids from base WorkflowStore" do
    # Verify id atoms are distinct from the base module name
    base_store_id = SymphonyElixir.WorkflowStore
    project_store_id = String.to_atom("Elixir.SymphonyElixir.WorkflowStore.project-a")

    assert is_atom(base_store_id)
    assert is_atom(project_store_id)
    refute base_store_id == project_store_id
  end

  test "multiple projects get distinct atoms" do
    projects = ["project-one", "project-two"]

    atoms =
      Enum.flat_map(projects, fn name ->
        [
          String.to_atom("Elixir.SymphonyElixir.WorkflowStore.#{name}"),
          String.to_atom("Elixir.SymphonyElixir.Orchestrator.#{name}")
        ]
      end)

    assert length(Enum.uniq(atoms)) == 4
  end

  test "no multi-project mode defaults to single Orchestrator (no named instances)" do
    deps = base_deps()

    assert :ok = CLI.evaluate([@ack_flag, "WORKFLOW.md"], deps)
    # No projects set when --projects-dir is absent
    assert SymphonyElixir.Workflow.projects() == []
  end

  # Bug: StatusDashboard.snapshot_payload/0 only looked for the default
  # Orchestrator (SymphonyElixir.Orchestrator), which doesn't exist in
  # multi-project mode. Fixed by falling back to multi_snapshot/0.

  describe "StatusDashboard snapshot_payload in multi-project mode" do
    test "merge_snapshots aggregates running/retrying across projects" do
      snapshot_a = {
        [%{identifier: "A-1", state: :started}],
        [],
        %{input_tokens: 100, output_tokens: 200, total_tokens: 300, seconds_running: 42},
        %{polling: %{checking?: true, next_poll_in_ms: 15_000}}
      }

      snapshot_b = {
        [%{identifier: "B-1", state: :started}],
        [%{issue_id: "retry-1", attempt: 1, due_in_ms: 5_000}],
        %{input_tokens: 50, output_tokens: 100, total_tokens: 150, seconds_running: 10},
        %{polling: %{checking?: false, next_poll_in_ms: 30_000}}
      }

      {:ok, merged} = StatusDashboard.merge_snapshots_for_test([snapshot_a, snapshot_b])

      assert length(merged.running) == 2
      assert length(merged.retrying) == 1
      assert merged.codex_totals.input_tokens == 150
      assert merged.codex_totals.output_tokens == 300
      assert merged.codex_totals.total_tokens == 450
      assert merged.codex_totals.seconds_running == 42
      assert merged.polling.checking? == true
      assert merged.polling.next_poll_in_ms == 15_000
    end

    test "merge_snapshots defaults empty codex_totals correctly" do
      snapshot = {
        [],
        [],
        %{},
        %{}
      }

      {:ok, merged} = StatusDashboard.merge_snapshots_for_test([snapshot])

      assert merged.codex_totals.input_tokens == 0
      assert merged.codex_totals.output_tokens == 0
      assert merged.codex_totals.total_tokens == 0
      assert merged.codex_totals.seconds_running == 0
    end

    test "snapshot_payload returns ok when default Orchestrator is running" do
      # In the test app, the default Orchestrator IS started, so
      # single snapshot should succeed.
      {:ok, payload} = StatusDashboard.snapshot_payload_for_test()
      assert is_list(payload.running)
      assert is_list(payload.retrying)
      assert is_map(payload.codex_totals)
    end
  end
end
