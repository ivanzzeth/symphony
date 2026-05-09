defmodule SymphonyElixir.ProjectDynamicSupervisor do
  @moduledoc false

  use DynamicSupervisor

  @spec start_link(term()) :: Supervisor.on_start()
  def start_link(init_arg \\ :ok) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
