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

  test "log_error_message/2 emits prefix plus Exception.message only" do
    log =
      capture_log(fn ->
        try do
          raise ArgumentError, "short"
        rescue
          e in [ArgumentError] ->
            Rescue.log_error_message("ctx error=", e)
        end
      end)

    assert log =~ "ctx error=short"
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

  test "close_port_tree/1 is idempotent on an already-closed port" do
    port = Port.open({:spawn, "cat"}, [:binary])
    assert Rescue.close_port_tree(port) == :ok
    refute Port.info(port)
    assert Rescue.close_port_tree(port) == :ok
  end

  test "close_port_tree/1 closes an open port and reaps its OS process" do
    port = Port.open({:spawn, "cat"}, [:binary])
    {:os_pid, os_pid} = :erlang.port_info(port, :os_pid)

    assert Rescue.close_port_tree(port) == :ok
    refute Port.info(port)

    # Verify the OS process is actually dead (kill -0 returns non-zero)
    {_output, exit_code} = System.cmd("kill", ["-0", Integer.to_string(os_pid)], stderr_to_stdout: true)
    assert exit_code != 0, "OS process #{os_pid} should have been killed"
  end

  test "close_port_tree/1 does not kill processes outside the target PID" do
    # Open two ports and only close the first one with close_port_tree
    port1 = Port.open({:spawn, "cat"}, [:binary])
    {:os_pid, _pid1} = :erlang.port_info(port1, :os_pid)
    port2 = Port.open({:spawn, "cat"}, [:binary])
    {:os_pid, pid2} = :erlang.port_info(port2, :os_pid)

    assert Rescue.close_port_tree(port1) == :ok
    refute Port.info(port1)

    # Verify port2's process is still alive (close_port_tree of port1 should not affect port2)
    {_output, exit_code} = System.cmd("kill", ["-0", Integer.to_string(pid2)], stderr_to_stdout: true)
    assert exit_code == 0, "port2's OS process #{pid2} should still be alive"

    # Clean up port2
    Rescue.close_port_if_open(port2)
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
