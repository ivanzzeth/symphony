defmodule SymphonyElixir.RescueTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias SymphonyElixir.Rescue

  test "log_warning/3 emits formatted exception" do
    log =
      capture_log(fn ->
        try do
          raise ArgumentError, "x"
        rescue
          e in [ArgumentError] ->
            Rescue.log_warning("test-prefix", e, __STACKTRACE__)
        end
      end)

    assert log =~ "test-prefix:"
    assert log =~ "ArgumentError"
    assert log =~ "x"
  end

  test "log_error/3 emits formatted exception" do
    log =
      capture_log(fn ->
        try do
          raise "boom"
        rescue
          e ->
            Rescue.log_error("err-prefix", e, __STACKTRACE__)
        end
      end)

    assert log =~ "err-prefix:"
    assert log =~ "boom"
  end

  test "log_exit_warning/2 emits inspect(reason)" do
    log =
      capture_log(fn ->
        Rescue.log_exit_warning("exit-prefix", :noproc)
      end)

    assert log =~ "exit-prefix:"
    assert log =~ "noproc"
  end

  test "to_existing_atom_or_same/1 returns atom when it exists" do
    assert Rescue.to_existing_atom_or_same("ok") == :ok
  end

  test "to_existing_atom_or_same/1 returns string when atom does not exist" do
    assert Rescue.to_existing_atom_or_same("___symphony_nonexistent_atom___") == "___symphony_nonexistent_atom___"
  end

  test "close_port_if_open/1 is safe after the port is already closed" do
    port = Port.open({:spawn, "cat"}, [:binary])
    assert Rescue.close_port_if_open(port) == :ok
    refute Port.info(port)
    assert Rescue.close_port_if_open(port) == :ok
  end

  test "close_port_if_open/1 closes an open port" do
    port = Port.open({:spawn, "cat"}, [:binary])
    assert is_port(port)
    assert Rescue.close_port_if_open(port) == :ok
    refute Port.info(port)
  end

  test "rescue_map/2 returns try_fun result on success" do
    assert Rescue.rescue_map(fn -> 42 end, fn _, _ -> :bad end) == 42
  end

  test "rescue_map/2 invokes rescue_fun on error" do
    assert_raise RuntimeError, "wrapped", fn ->
      Rescue.rescue_map(fn -> raise "inner" end, fn _e, st ->
        reraise %RuntimeError{message: "wrapped"}, st
      end)
    end
  end
end
