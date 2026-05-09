defmodule SymphonyElixir.Project.Tracker do
  @moduledoc """
  Per-project anchor process (registry-named) reserved for future tracker routing.

  Issue reads still go through `SymphonyElixir.Tracker` using each process's config context.
  """

  use GenServer

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    project_id = Keyword.fetch!(opts, :project_id)
    name = Keyword.fetch!(opts, :name)

    %{
      id: {__MODULE__, project_id},
      start: {__MODULE__, :start_link, [[name: name, project_id: project_id]]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    project_id = Keyword.fetch!(opts, :project_id)
    GenServer.start_link(__MODULE__, project_id, name: name)
  end

  @impl true
  def init(project_id) when is_binary(project_id) do
    {:ok, %{project_id: project_id}}
  end
end
