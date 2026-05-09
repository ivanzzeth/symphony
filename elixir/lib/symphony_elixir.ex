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

    bootstrap_opts = Application.get_env(:symphony_elixir, :project_bootstrap_opts, [])

    core = [
      {Phoenix.PubSub, name: SymphonyElixir.PubSub},
      {Task.Supervisor, name: SymphonyElixir.TaskSupervisor},
      SymphonyElixir.ProcessConfig.Store,
      {Registry, keys: :unique, name: SymphonyElixir.ProjectProcessRegistry},
      SymphonyElixir.ProjectSupervisor.Meta,
      SymphonyElixir.ProjectSupervisor,
      SymphonyElixir.ProjectRegistry
    ]

    global_stack =
      if Application.get_env(:symphony_elixir, :symphony_global_stack, false) do
        [
          SymphonyElixir.WorkflowStore,
          SymphonyElixir.Harness.Manager,
          SymphonyElixir.Orchestrator
        ]
      else
        []
      end

    tail = [
      {SymphonyElixir.ProjectSupervisor.Bootstrap, bootstrap_opts},
      SymphonyElixir.HttpServer,
      SymphonyElixir.StatusDashboard
    ]

    children = core ++ global_stack ++ tail

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
