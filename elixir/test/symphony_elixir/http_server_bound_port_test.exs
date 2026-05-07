defmodule SymphonyElixir.HttpServerBoundPortTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.HttpServer

  describe "bound_port/1" do
    test "logs and returns nil when server_info raises (simulated)" do
      log =
        capture_log(fn ->
          with_app_env(:symphony_elixir, :http_server_bound_port_test_force, :raise, fn ->
            assert HttpServer.bound_port() == nil
          end)
        end)

      assert log =~ "HttpServer.bound_port failed:"
      assert log =~ "ArgumentError"
      assert log =~ "simulated HttpServer.bound_port failure"
    end

    test "logs and returns nil when server_info exits (simulated)" do
      log =
        capture_log(fn ->
          with_app_env(:symphony_elixir, :http_server_bound_port_test_force, :exit, fn ->
            assert HttpServer.bound_port() == nil
          end)
        end)

      assert log =~ "HttpServer.bound_port failed:"
      assert log =~ ":simulated_http_server_bound_port_exit"
    end
  end

  defp with_app_env(app, key, value, fun) do
    previous = Application.fetch_env(app, key)
    Application.put_env(app, key, value)

    try do
      fun.()
    after
      case previous do
        {:ok, val} -> Application.put_env(app, key, val)
        :error -> Application.delete_env(app, key)
      end
    end
  end
end
