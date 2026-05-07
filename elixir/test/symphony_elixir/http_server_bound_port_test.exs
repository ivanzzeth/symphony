defmodule SymphonyElixir.HttpServerBoundPortTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias SymphonyElixir.HttpServer

  setup do
    SymphonyElixir.TestSupport.stop_default_http_server()
    :ok
  end

  test "bound_port logs warning on :raise test force" do
    log =
      capture_log(fn ->
        with_app_env(:symphony_elixir, :http_server_bound_port_test_force, :raise, fn ->
          assert HttpServer.bound_port() == nil
        end)
      end)

    assert log =~ "HttpServer.bound_port failed:"
  end

  test "bound_port logs warning on :exit test force" do
    log =
      capture_log(fn ->
        with_app_env(:symphony_elixir, :http_server_bound_port_test_force, :exit, fn ->
          assert HttpServer.bound_port() == nil
        end)
      end)

    assert log =~ "HttpServer.bound_port failed:"
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
