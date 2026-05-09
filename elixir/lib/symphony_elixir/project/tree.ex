defmodule SymphonyElixir.Project.Tree do
  @moduledoc """
  Root `Supervisor` for one project's process tree — `WorkflowStore`, `Harness.Manager`,
  `Task.Supervisor` (agent runs), `SymphonyElixir.Agent.Supervisor`, `SymphonyElixir.Project.Tracker`,
  and `Orchestrator`.
  """

  use Supervisor

  alias SymphonyElixir.ProjectNaming

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    project_id = Keyword.fetch!(opts, :project_id)

    %{
      id: {__MODULE__, project_id},
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :temporary
    }
  end

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    project_id = Keyword.fetch!(opts, :project_id)
    workflow_rel = Keyword.fetch!(opts, :workflow_path)
    base_dir = Keyword.get(opts, :config_base_dir, File.cwd!()) |> Path.expand()
    wf_path = workflow_rel |> Path.expand(base_dir)
    project_root = Path.dirname(wf_path)

    reg = ProjectNaming.registry()

    ws_via = {:via, Registry, {reg, {project_id, :workflow_store}}}
    hm_via = {:via, Registry, {reg, {project_id, :harness_manager}}}
    task_via = {:via, Registry, {reg, {project_id, :task_supervisor}}}
    orch_via = {:via, Registry, {reg, {project_id, :orchestrator}}}
    tracker_via = {:via, Registry, {reg, {project_id, :tracker}}}

    children = [
      {SymphonyElixir.WorkflowStore, name: ws_via, workflow_file_path: wf_path, project_id: project_id},
      {SymphonyElixir.Harness.Manager, name: hm_via, project_dir: project_root, workflow_file_path: wf_path, workflow_store: ws_via},
      {Task.Supervisor, name: task_via},
      {SymphonyElixir.Agent.Supervisor, project_id: project_id},
      {SymphonyElixir.Project.Tracker, name: tracker_via, project_id: project_id},
      {SymphonyElixir.Orchestrator, name: orch_via, workflow_store: ws_via, task_supervisor: task_via, workflow_path: wf_path, project_id: project_id}
    ]

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 10, max_seconds: 60)
  end
end
