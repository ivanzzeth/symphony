defmodule SymphonyElixir.RescueLoggingTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias SymphonyElixir.HttpServer
  alias SymphonyElixir.StatusDashboard

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
