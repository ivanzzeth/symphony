defmodule SymphonyElixir.Agent.Supervisor do
  @moduledoc """
  Per-project `DynamicSupervisor` for agent-related dynamic children.

  Issue dispatch still uses `Task.Supervisor` under each project tree; this supervisor
  anchors an explicit branch for future dynamic agent workers.
  """

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    project_id = Keyword.fetch!(opts, :project_id)
    name = SymphonyElixir.ProjectNaming.via(project_id, :agent_supervisor)

    %{
      id: {__MODULE__, project_id},
      start: {DynamicSupervisor, :start_link, [[strategy: :one_for_one, name: name]]},
      type: :supervisor,
      restart: :permanent,
      shutdown: :infinity
    }
  end
end
