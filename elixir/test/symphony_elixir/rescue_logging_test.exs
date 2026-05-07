defmodule SymphonyElixir.RescueLoggingTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import SymphonyElixir.TestSupport, only: [write_workflow_file!: 2, stop_default_http_server: 0]

  alias SymphonyElixir.HttpServer
  alias SymphonyElixir.StatusDashboard
  alias SymphonyElixir.Config.Schema
  alias SymphonyElixir.Workspace
  alias SymphonyElixir.Workflow
  alias SymphonyElixir.WorkflowStore

  test "HttpServer.bound_port/1 logs warning when forced to raise" do
    env = Application.get_all_env(:symphony_elixir)
    had_key? = Keyword.has_key?(env, :http_server_bound_port_force_raise)
    prev = Keyword.get(env, :http_server_bound_port_force_raise)

    try do
      Application.put_env(:symphony_elixir, :http_server_bound_port_force_raise, true)

      log =
        capture_log([level: :warning], fn ->
          assert HttpServer.bound_port() == nil
        end)

      assert log =~ "HttpServer.bound_port/1"
    after
      if had_key? do
        Application.put_env(:symphony_elixir, :http_server_bound_port_force_raise, prev)
      else
        Application.delete_env(:symphony_elixir, :http_server_bound_port_force_raise)
      end
    end
  end

  test "StatusDashboard.dashboard_enabled? logs warning when Mix.env path is forced to fail" do
    env = Application.get_all_env(:symphony_elixir)
    had_key? = Keyword.has_key?(env, :status_dashboard_mix_env_raise)
    prev = Keyword.get(env, :status_dashboard_mix_env_raise)

    try do
      Application.put_env(:symphony_elixir, :status_dashboard_mix_env_raise, true)

      log =
        capture_log([level: :warning], fn ->
          assert StatusDashboard.dashboard_enabled_for_test() == true
        end)

      assert log =~ "StatusDashboard.dashboard_enabled?"
    after
      if had_key? do
        Application.put_env(:symphony_elixir, :status_dashboard_mix_env_raise, prev)
      else
        Application.delete_env(:symphony_elixir, :status_dashboard_mix_env_raise)
      end
    end
  end

  test "Config.Schema parse logs warnings when disallowed-key helpers hit invalid atom keys" do
    env = Application.get_all_env(:symphony_elixir)
    had_extra? = Keyword.has_key?(env, :extra_disallowed_workflow_keys_for_test)
    prev_extra = Keyword.get(env, :extra_disallowed_workflow_keys_for_test)

    bad_key = "nonexistent_atom_key_#{System.unique_integer([:positive])}"
    Application.put_env(:symphony_elixir, :extra_disallowed_workflow_keys_for_test, [bad_key])

    on_exit(fn ->
      if had_extra? do
        Application.put_env(:symphony_elixir, :extra_disallowed_workflow_keys_for_test, prev_extra)
      else
        Application.delete_env(:symphony_elixir, :extra_disallowed_workflow_keys_for_test)
      end
    end)

    root = Path.join(System.tmp_dir!(), "symphony-schema-rescue-#{System.unique_integer([:positive])}")

    log =
      capture_log([level: :warning], fn ->
        assert {:ok, _settings} =
                 Schema.parse(%{
                   "tracker" => %{"kind" => "memory"},
                   "polling" => %{"interval_ms" => 30_000},
                   "workspace" => %{"root" => root, "base_branch" => "main"},
                   "worker" => %{},
                   "agent" => %{"kind" => "codex", "command" => "codex app-server"},
                   "codex" => %{"command" => "codex app-server"},
                   "hooks" => %{}
                 })
      end)

    assert log =~ "Config.Schema.warn_disallowed_keys"
    assert log =~ "Config.Schema.strip_disallowed_keys"
  end

  test "Workspace hook path logs warning when hook command template fails to parse" do
    workflow_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-rescue-hook-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(workflow_root)
    workflow_file = Path.join(workflow_root, "WORKFLOW.md")

    prev_path = Application.get_env(:symphony_elixir, :workflow_file_path)

    write_workflow_file!(workflow_file, hook_before_run: "{% if issue.identifier %}")
    Workflow.set_workflow_file_path(workflow_file)

    if Process.whereis(WorkflowStore) do
      WorkflowStore.force_reload()
    end

    stop_default_http_server()

    workspace = Path.join(workflow_root, "ws")
    File.mkdir_p!(workspace)

    on_exit(fn ->
      case prev_path do
        nil -> Application.delete_env(:symphony_elixir, :workflow_file_path)
        path -> Application.put_env(:symphony_elixir, :workflow_file_path, path)
      end

      if Process.whereis(WorkflowStore) do
        try do
          WorkflowStore.force_reload()
        catch
          :exit, _ -> :ok
        end
      end

      File.rm_rf(workflow_root)
    end)

    log =
      capture_log([level: :warning], fn ->
        assert :ok = Workspace.run_before_run_hook(workspace, %{issue_id: 1, issue_identifier: "X-1"}, nil)
      end)

    assert log =~ "Workspace.render_hook_command"
  end
end
