defmodule SymphonyElixir.HttpServerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias SymphonyElixir.HttpServer

  @test_mode_key :http_server_bound_port_test_mode

  setup do
    SymphonyElixir.TestSupport.stop_default_http_server()
    :ok
  end

  test "bound_port logs warning when test mode forces raise" do
    previous = Application.fetch_env(:symphony_elixir, @test_mode_key)
    Application.put_env(:symphony_elixir, @test_mode_key, :raise)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:symphony_elixir, @test_mode_key, value)
        :error -> Application.delete_env(:symphony_elixir, @test_mode_key)
      end
    end)

    log =
      capture_log(fn ->
        assert HttpServer.bound_port() == nil
      end)

    assert log =~ "HttpServer.bound_port/1: failed, returning nil"
    assert log =~ "RuntimeError"
  end

  test "bound_port logs warning when test mode forces exit" do
    previous = Application.fetch_env(:symphony_elixir, @test_mode_key)
    Application.put_env(:symphony_elixir, @test_mode_key, {:exit, :simulated_bound_port_exit})

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:symphony_elixir, @test_mode_key, value)
        :error -> Application.delete_env(:symphony_elixir, @test_mode_key)
      end
    end)

    log =
      capture_log(fn ->
        assert HttpServer.bound_port() == nil
      end)

    assert log =~ "HttpServer.bound_port/1: failed (exit), returning nil"
    assert log =~ ":simulated_bound_port_exit"
  end
end
