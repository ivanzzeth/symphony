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
  Closes an Erlang port when it is still registered; swallows `ArgumentError` from `Port.close/1`.
  """
  @spec close_port_if_open(port()) :: :ok
  def close_port_if_open(port) when is_port(port) do
    case :erlang.port_info(port) do
      :undefined ->
        :ok

      _ ->
        try do
          Port.close(port)
          :ok
        rescue
          ArgumentError -> :ok
        end
    end
  end
end
