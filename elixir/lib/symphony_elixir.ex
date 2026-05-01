defmodule SymphonyElixir do
  @moduledoc """
  Entry point for the Symphony orchestrator.
  """

  @doc """
  Start the orchestrator in the current BEAM node.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    SymphonyElixir.Orchestrator.start_link(opts)
  end
end

defmodule SymphonyElixir.Application do
  @moduledoc """
  OTP application entrypoint that starts core supervisors and workers.
  """

  use Application

  @impl true
  def start(_type, _args) do
    :ok = SymphonyElixir.LogFile.configure()

    projects = Application.get_env(:symphony_elixir, :projects, [])

    shared_children = [
      {Phoenix.PubSub, name: SymphonyElixir.PubSub},
      {Task.Supervisor, name: SymphonyElixir.TaskSupervisor},
      SymphonyElixir.HttpServer,
      SymphonyElixir.StatusDashboard
    ]

    project_children =
      if projects == [] do
        [SymphonyElixir.WorkflowStore, SymphonyElixir.Orchestrator]
      else
        Enum.flat_map(projects, fn project ->
          store_name = String.to_atom("Elixir.SymphonyElixir.WorkflowStore.#{project.name}")
          orch_name = String.to_atom("Elixir.SymphonyElixir.Orchestrator.#{project.name}")

          [
            {SymphonyElixir.WorkflowStore,
             id: store_name,
             name: store_name,
             workflow_file_path: project.workflow_path},
            {SymphonyElixir.Orchestrator,
             id: orch_name,
             name: orch_name,
             workflow_store: store_name,
             project_name: project.name}
          ]
        end)
      end

    children = shared_children ++ project_children

    Supervisor.start_link(
      children,
      strategy: :one_for_one,
      name: SymphonyElixir.Supervisor
    )
  end

  @impl true
  def stop(_state) do
    SymphonyElixir.StatusDashboard.render_offline_status()
    :ok
  end
end
