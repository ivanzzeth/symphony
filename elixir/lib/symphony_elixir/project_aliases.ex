defmodule SymphonyElixir.ProjectAliases do
  @moduledoc """
  Tracks the primary `project_id` for legacy call sites that resolve `WorkflowStore`,
  `Orchestrator`, and related modules via `Application` env instead of an explicit server.
  """

  alias SymphonyElixir.ProjectNaming

  @env_key :primary_project_id

  @doc """
  Registers `project_id` as the routing target for `WorkflowStore.whereis/0` and related helpers.

  First registration wins until `clear_aliases/0`.
  """
  @spec register_primary(binary()) :: :ok
  def register_primary(project_id) when is_binary(project_id) do
    case Application.get_env(:symphony_elixir, @env_key) do
      nil ->
        Application.put_env(:symphony_elixir, @env_key, project_id, persistent: false)
        :ok

      _ ->
        :ok
    end
  end

  @spec clear_aliases() :: :ok
  def clear_aliases do
    Application.delete_env(:symphony_elixir, @env_key)
    :ok
  end

  @doc """
  GenServer name for snapshot/dashboard APIs: primary project's orchestrator via Registry when set,
  otherwise the legacy `SymphonyElixir.Orchestrator` module name.
  """
  @spec primary_orchestrator_name() :: GenServer.server()
  def primary_orchestrator_name do
    case Application.get_env(:symphony_elixir, @env_key) do
      project_id when is_binary(project_id) ->
        ProjectNaming.via(project_id, :orchestrator)

      _ ->
        case SymphonyElixir.Orchestrator.whereis() do
          pid when is_pid(pid) -> pid
          _ -> SymphonyElixir.Orchestrator
        end
    end
  end
end
