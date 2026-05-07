defmodule SymphonyElixir.RescueLoggingTest do
  @moduledoc """
  Exercises rescue paths that emit `Logger.warning`, using `ExUnit.CaptureLog`.

  Covers `HttpServer`, `Config.Schema`, `StatusDashboard`, and `Workspace` per WEB-72.
  """

  use SymphonyElixir.TestSupport, async: false

  alias SymphonyElixir.HttpServer
  alias SymphonyElixir.StatusDashboard

  defp with_symphony_app_env(key, value, fun) do
    env = Application.get_all_env(:symphony_elixir)
    had_key? = Keyword.has_key?(env, key)
    prev = Keyword.get(env, key)

    try do
      Application.put_env(:symphony_elixir, key, value)
      fun.()
    after
      if had_key? do
        Application.put_env(:symphony_elixir, key, prev)
      else
        Application.delete_env(:symphony_elixir, key)
      end
    end
  end

  defp capture_warning_log(fun) do
    log = capture_log([level: :warning], fun)
    assert log != "", "expected Logger.warning (or higher) output"
    log
  end

  test "HttpServer.bound_port/1 logs warning when phoenix server_info raises" do
    with_symphony_app_env(
      :http_server_phoenix_http_server_info_stub,
      fn -> raise RuntimeError, "symphony test: bound_port server_info failure" end,
      fn ->
        log =
          capture_warning_log(fn ->
            assert HttpServer.bound_port() == nil
          end)

        assert log =~ "HttpServer.bound_port/1"
      end
    )
  end

  test "StatusDashboard.dashboard_enabled? logs warning when Mix.env path is forced to fail" do
    with_symphony_app_env(:status_dashboard_mix_env_raise, true, fn ->
      log =
        capture_warning_log(fn ->
          assert StatusDashboard.dashboard_enabled_for_test() == true
        end)

      assert log =~ "StatusDashboard.dashboard_enabled?"
    end)
  end

  test "StatusDashboard.render_offline_status/0 logs warning when terminal render raises" do
    with_symphony_app_env(
      :status_dashboard_render_to_terminal_stub,
      fn _content -> raise ArgumentError, "symphony test: offline render failure" end,
      fn ->
        log =
          capture_warning_log(fn ->
            assert StatusDashboard.render_offline_status() == :ok
          end)

        assert log =~ "Failed rendering offline status"
      end
    )
  end

  test "StatusDashboard maybe_render logs warning when render pipeline raises ArgumentError" do
    name = :"status_dash_maybe_render_#{System.unique_integer([:positive])}"

    {:ok, pid} =
      StatusDashboard.start_link(
        name: name,
        enabled: true,
        refresh_ms: 99_999,
        render_interval_ms: 99_999,
        render_fun: fn _ -> :ok end
      )

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(name, :normal, 5_000)
    end)

    with_symphony_app_env(:status_dashboard_maybe_render_raise_exception, ArgumentError, fn ->
      log =
        capture_warning_log(fn ->
          send(name, :tick)
          _ = :sys.get_state(name, 5_000)
        end)

      assert log =~ "Failed rendering status dashboard"
    end)
  end

  test "StatusDashboard render_content logs warning when render_fun raises" do
    state = %StatusDashboard{
      refresh_ms: 99_999,
      enabled: true,
      render_interval_ms: 16,
      refresh_ms_override: nil,
      enabled_override: nil,
      render_interval_ms_override: nil,
      render_fun: fn _ -> raise ArgumentError, "symphony test: render_fun failure" end,
      token_samples: [],
      last_tps_second: nil,
      last_tps_value: nil,
      last_rendered_content: nil,
      last_rendered_at_ms: nil,
      pending_content: nil,
      flush_timer_ref: nil,
      last_snapshot_fingerprint: nil
    }

    log =
      capture_warning_log(fn ->
        _ = StatusDashboard.render_content_for_test(state, "content", 0)
      end)

    assert log =~ "Failed rendering terminal dashboard frame"
  end

  test "Config.Schema logs warning when disallowed-workflow key list references a non-existing atom" do
    bad_key = "symphony_bad_disallowed_key_#{System.unique_integer([:positive])}"

    assert_raise ArgumentError, fn ->
      String.to_existing_atom(bad_key)
    end

    with_symphony_app_env(:extra_disallowed_workflow_keys_for_test, [bad_key], fn ->
      root = Path.join(System.tmp_dir!(), "symphony-schema-rescue-#{System.unique_integer([:positive])}")

      log =
        capture_warning_log(fn ->
          assert {:ok, _} =
                   SymphonyElixir.Config.Schema.parse(%{
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
    end)
  end

  test "Workspace logs warning when hook command template hits render_hook_command rescue" do
    log =
      capture_warning_log(fn ->
        assert Workspace.render_hook_command_for_tests("{{") == "{{"
      end)

    assert log =~ "Workspace.render_hook_command"
  end
end
