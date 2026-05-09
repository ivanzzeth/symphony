defmodule SymphonyElixir.TestProjectRuntime do
  @moduledoc false

  alias SymphonyElixir.{Orchestrator, ProjectSupervisor.Meta, WorkflowStore}

  @spec primary_id() :: binary()
  def primary_id do
    Application.get_env(:symphony_elixir, :primary_project_id) || "default"
  end

  @spec tree_supervisor() :: pid() | nil
  def tree_supervisor do
    case Meta.fetch(primary_id()) do
      %{tree_pid: pid} when is_pid(pid) -> pid
      _ -> nil
    end
  end

  @spec orchestrator_pid() :: pid() | nil
  def orchestrator_pid, do: Orchestrator.whereis()

  @spec workflow_store_pid() :: pid() | nil
  def workflow_store_pid do
    WorkflowStore.whereis()
  end

  @spec terminate_workflow_store!() :: :ok | {:error, term()}
  def terminate_workflow_store! do
    case tree_supervisor() do
      pid when is_pid(pid) -> Supervisor.terminate_child(pid, WorkflowStore)
      _ -> {:error, :no_project_tree}
    end
  end

  @spec restart_workflow_store!() :: {:ok, pid()} | {:error, term()}
  def restart_workflow_store! do
    case tree_supervisor() do
      pid when is_pid(pid) -> Supervisor.restart_child(pid, WorkflowStore)
      _ -> {:error, :no_project_tree}
    end
  end

  @spec terminate_orchestrator!() :: :ok | {:error, term()}
  def terminate_orchestrator! do
    case tree_supervisor() do
      pid when is_pid(pid) -> Supervisor.terminate_child(pid, Orchestrator)
      _ -> {:error, :no_project_tree}
    end
  end

  @spec restart_orchestrator!() :: {:ok, pid()} | {:error, term()}
  def restart_orchestrator! do
    case tree_supervisor() do
      pid when is_pid(pid) -> Supervisor.restart_child(pid, Orchestrator)
      _ -> {:error, :no_project_tree}
    end
  end
end
