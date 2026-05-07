defmodule SymphonyElixir.RescueLoggingTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias SymphonyElixir.{HttpServer, StatusDashboard}

  defp with_bound_port_test_force(value, fun) do
    env = Application.get_all_env(:symphony_elixir)
    had_key? = Keyword.has_key?(env, :http_server_bound_port_test_force)
    prev = Keyword.get(env, :http_server_bound_port_test_force)

    try do
      Application.put_env(:symphony_elixir, :http_server_bound_port_test_force, value)
      fun.()
    after
      if had_key? do
        Application.put_env(:symphony_elixir, :http_server_bound_port_test_force, prev)
      else
        Application.delete_env(:symphony_elixir, :http_server_bound_port_test_force)
      end
    end
  end

  test "HttpServer.bound_port/1 logs when forced to raise" do
    log =
      capture_log(fn ->
        with_bound_port_test_force(:raise, fn ->
          assert HttpServer.bound_port() == nil
        end)
      end)

    assert log =~ "HttpServer.bound_port failed:"
    assert log =~ "%ArgumentError{message: \"simulated HttpServer.bound_port failure\"}"
  end

  test "HttpServer.bound_port/1 logs when forced to exit" do
    log =
      capture_log(fn ->
        with_bound_port_test_force(:exit, fn ->
          assert HttpServer.bound_port() == nil
        end)
      end)

    assert log =~ "HttpServer.bound_port failed:"
    assert log =~ ":simulated_http_server_bound_port_exit"
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
