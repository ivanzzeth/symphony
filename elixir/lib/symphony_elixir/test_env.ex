defmodule SymphonyElixir.TestEnv do
  @moduledoc false

  @doc """
  True only when the app is running under ExUnit (`Mix.env() == :test`).

  Used to gate test-only Application env hooks so release and dev shells cannot
  accidentally enable them.
  """
  @spec active?() :: boolean()
  def active? do
    Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) and Mix.env() == :test
  end
end
