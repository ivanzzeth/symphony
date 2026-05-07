defmodule SymphonyElixir.RescueLoggingTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias SymphonyElixir.Config.Schema
  alias SymphonyElixir.HttpServer
  alias SymphonyElixir.StatusDashboard

  defp minimal_schema_parse_config(root) do
    %{
      "tracker" => %{"kind" => "memory"},
      "polling" => %{"interval_ms" => 30_000},
      "workspace" => %{"root" => root, "base_branch" => "main"},
      "worker" => %{},
      "agent" => %{"kind" => "codex", "command" => "codex app-server"},
      "codex" => %{"command" => "codex app-server"},
      "hooks" => %{}
    }
  end

  test "Config.Schema warn_disallowed_keys rescue logs warning with error reason" do
    root =
      Path.join(System.tmp_dir!(), "symphony-schema-warn-rescue-#{System.unique_integer([:positive])}")

    env = Application.get_all_env(:symphony_elixir)
    had_key? = Keyword.has_key?(env, :symphony_test_schema_warn_disallowed_raise)
    prev = Keyword.get(env, :symphony_test_schema_warn_disallowed_raise)

    try do
      Application.put_env(:symphony_elixir, :symphony_test_schema_warn_disallowed_raise, true)

      log =
        capture_log(fn ->
          assert {:ok, _} = Schema.parse(minimal_schema_parse_config(root))
        end)

      assert log =~ "Config.Schema.warn_disallowed_keys/1 failed, continuing:"
      assert log =~ "simulated warn_disallowed_keys failure"
    after
      if had_key? do
        Application.put_env(:symphony_elixir, :symphony_test_schema_warn_disallowed_raise, prev)
      else
        Application.delete_env(:symphony_elixir, :symphony_test_schema_warn_disallowed_raise)
      end
    end
  end

  test "Config.Schema strip_disallowed_keys rescue logs warning with error reason" do
    root =
      Path.join(System.tmp_dir!(), "symphony-schema-strip-rescue-#{System.unique_integer([:positive])}")

    env = Application.get_all_env(:symphony_elixir)
    had_key? = Keyword.has_key?(env, :symphony_test_schema_strip_disallowed_raise)
    prev = Keyword.get(env, :symphony_test_schema_strip_disallowed_raise)

    try do
      Application.put_env(:symphony_elixir, :symphony_test_schema_strip_disallowed_raise, true)

      log =
        capture_log(fn ->
          assert {:ok, _} = Schema.parse(minimal_schema_parse_config(root))
        end)

      assert log =~ "Config.Schema.strip_disallowed_keys/1 failed, returning raw config:"
      assert log =~ "simulated strip_disallowed_keys failure"
    after
      if had_key? do
        Application.put_env(:symphony_elixir, :symphony_test_schema_strip_disallowed_raise, prev)
      else
        Application.delete_env(:symphony_elixir, :symphony_test_schema_strip_disallowed_raise)
      end
    end
  end

  test "HttpServer.bound_port/1 logs when forced to raise" do
    env = Application.get_all_env(:symphony_elixir)
    had_key? = Keyword.has_key?(env, :http_server_bound_port_force_raise)
    prev = Keyword.get(env, :http_server_bound_port_force_raise)

    try do
      Application.put_env(:symphony_elixir, :http_server_bound_port_force_raise, true)

      log =
        capture_log(fn ->
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

  test "StatusDashboard.dashboard_enabled? logs when Mix.env path is forced to fail" do
    env = Application.get_all_env(:symphony_elixir)
    had_key? = Keyword.has_key?(env, :status_dashboard_mix_env_raise)
    prev = Keyword.get(env, :status_dashboard_mix_env_raise)

    try do
      Application.put_env(:symphony_elixir, :status_dashboard_mix_env_raise, true)

      log =
        capture_log(fn ->
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
end
