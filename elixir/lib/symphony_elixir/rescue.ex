defmodule SymphonyElixir.Rescue do
  @moduledoc """
  Shared logging and helpers for `rescue` / `catch` fallbacks (WEB-71).

  Centralizes `Exception.format/3` usage and best-effort port cleanup so modules stay consistent.
  """

  require Logger

  @doc """
  Logs a rescued exception at `:warning` using `Exception.format/3`.
  """
  @spec log_warning(String.t(), Exception.t(), Exception.stacktrace()) :: :ok
  def log_warning(prefix, exception, stacktrace) when is_binary(prefix) do
    Logger.warning(fn -> "#{prefix}: #{Exception.format(:error, exception, stacktrace)}" end)
    :ok
  end

  @doc """
  Logs a rescued exception at `:error` using `Exception.format/3`.
  """
  @spec log_error(String.t(), Exception.t(), Exception.stacktrace()) :: :ok
  def log_error(prefix, exception, stacktrace) when is_binary(prefix) do
    Logger.error(fn -> "#{prefix}: #{Exception.format(:error, exception, stacktrace)}" end)
    :ok
  end

  @doc """
  Logs `prefix <> Exception.message(exception)` at `:error` (no stacktrace).

  Used when rescue paths intentionally surface a short operator-facing line.
  """
  @spec log_error_message(String.t(), Exception.t()) :: :ok
  def log_error_message(prefix, exception) when is_binary(prefix) do
    Logger.error(fn -> prefix <> Exception.message(exception) end)
    :ok
  end

  @doc """
  Logs a `catch` exit reason at `:warning` (no stacktrace from exits).
  """
  @spec log_exit_warning(String.t(), term()) :: :ok
  def log_exit_warning(prefix, reason) when is_binary(prefix) do
    Logger.warning(fn -> "#{prefix}: #{inspect(reason)}" end)
    :ok
  end

  @doc """
  `String.to_existing_atom/1` or the original string when the atom does not exist.
  """
  @spec to_existing_atom_or_same(String.t()) :: atom() | String.t()
  def to_existing_atom_or_same(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end

  @doc """
  Closes a port after safely killing only its direct OS process (not the process group).

  Two-phase termination:
  1. SIGTERM to the OS PID only (never the PGID)
  2. After 500ms grace period, SIGKILL if still alive
  3. Port close (idempotent)

  This replaces the aggressive `kill -TERM -PID` PGID kill that could cascade to
  unrelated processes sharing the same process group.
  """
  @spec close_port_tree(port()) :: :ok
  def close_port_tree(port) when is_port(port) do
    case os_pid_from_port(port) do
      nil ->
        close_port_if_open(port)

      os_pid ->
        kill_os_pid(os_pid)
        close_port_if_open(port)
    end
  end

  defp os_pid_from_port(port) when is_port(port) do
    case :erlang.port_info(port, :os_pid) do
      {:os_pid, pid} when pid > 0 -> pid
      _ -> nil
    end
  end

  defp kill_os_pid(os_pid) when is_integer(os_pid) and os_pid > 0 do
    # Phase 1: SIGTERM to the specific PID only (not the PGID — no `-` prefix)
    send_signal("-TERM", os_pid)
    Process.sleep(500)

    # Phase 2: SIGKILL if still alive
    if process_alive?(os_pid) do
      send_signal("-KILL", os_pid)
    end
  end

  defp send_signal(signal_flag, pid) when is_binary(signal_flag) and is_integer(pid) do
    _ = System.cmd("kill", [signal_flag, Integer.to_string(pid)], stderr_to_stdout: true)
    :ok
  rescue
    _ -> :ok
  end

  defp process_alive?(pid) when is_integer(pid) do
    case System.cmd("kill", ["-0", Integer.to_string(pid)], stderr_to_stdout: true) do
      {_output, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  @doc """
  Closes a port when it is still registered; swallows `ArgumentError` from `Port.close/1`.
  """
  @spec close_port_if_open(port()) :: :ok
  def close_port_if_open(port) when is_port(port) do
    case :erlang.port_info(port) do
      :undefined ->
        :ok

      _ ->
        safe_port_close(port)
    end
  end

  defp safe_port_close(port) do
    Port.close(port)
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Run `try_fun`; on exception, invoke `rescue_fun` with the exception and stacktrace.
  """
  @spec rescue_map((-> result), (Exception.t(), Exception.stacktrace() -> result)) :: result
        when result: var
  def rescue_map(try_fun, rescue_fun)
      when is_function(try_fun, 0) and is_function(rescue_fun, 2) do
    try_fun.()
  rescue
    exception -> rescue_fun.(exception, __STACKTRACE__)
  end
end
