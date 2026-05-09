defmodule SymphonyElixir.ProjectSupervisor do
  @moduledoc """
  Per-project process supervision (SPEC V1.2 Appendix B.4 / WEB-79).

  Registered `DynamicSupervisor` (`:one_for_one`) for all project trees plus the public API
  for `start_project/1`, `stop_project/1`, `list_projects/0`, and `startup_failure/1`.

  Each child is `SymphonyElixir.Project.Tree`: `WorkflowStore`, `Harness.Manager`,
  `Task.Supervisor`, `Orchestrator`, `Agent.Supervisor`, and `Project.Tracker`.

  On success, the orchestrator pid is registered in `ProjectRegistry` under `project_id`.
  """

  use DynamicSupervisor

  alias SymphonyElixir.Project.Tree
  alias SymphonyElixir.ProjectAliases
  alias SymphonyElixir.ProjectNaming
  alias SymphonyElixir.ProjectRegistry
  alias SymphonyElixir.ProjectSupervisor.Meta

  require Logger

  @type start_opts :: %{
          required(:project_id) => binary(),
          required(:workflow_path) => binary(),
          optional(:config_base_dir) => binary()
        }

  @orch_poll_attempts 50
  @orch_poll_interval_ms 10

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts \\ []) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent,
      shutdown: :infinity
    }
  end

  @doc false
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, :ok, Keyword.merge([name: __MODULE__], opts))
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a project tree under this `DynamicSupervisor`.

  Registers the orchestrator pid in `ProjectRegistry` once it joins the process registry.
  """
  @spec start_project(start_opts() | keyword()) :: {:ok, pid()} | {:error, term()}
  def start_project(%{} = opts) do
    start_project(
      project_id: Map.fetch!(opts, :project_id) |> to_string(),
      workflow_path: Map.fetch!(opts, :workflow_path) |> to_string(),
      config_base_dir: Map.get(opts, :config_base_dir)
    )
  end

  def start_project(opts) when is_list(opts) do
    project_id = Keyword.fetch!(opts, :project_id) |> to_string()
    config_base_dir = Keyword.get(opts, :config_base_dir, File.cwd!()) |> to_string() |> Path.expand()

    workflow_abs =
      opts |> Keyword.fetch!(:workflow_path) |> to_string() |> Path.expand(config_base_dir)

    cond do
      project_id == "" ->
        {:error, :invalid_project_id}

      not File.regular?(workflow_abs) ->
        {:error, {:workflow_not_found, workflow_abs}}

      true ->
        case Meta.begin_start(project_id, workflow_abs) do
          {:error, :already_started} ->
            {:error, :already_started}

          :ok ->
            do_start_child(project_id, workflow_abs, config_base_dir)
        end
    end
  end

  defp do_start_child(project_id, workflow_abs, config_base_dir) do
    spec =
      Tree.child_spec(
        project_id: project_id,
        workflow_path: workflow_abs,
        config_base_dir: config_base_dir
      )

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, tree_pid} ->
        case await_orchestrator_pid(project_id, @orch_poll_attempts, @orch_poll_interval_ms) do
          {:ok, orch_pid} ->
            :ok = Meta.mark_running(project_id, tree_pid, orch_pid)
            :ok = Meta.monitor_tree(project_id, tree_pid)
            maybe_register_primary(project_id)
            {:ok, tree_pid}

          :timeout ->
            reason = :orchestrator_not_registered
            _ = Supervisor.stop(tree_pid, :shutdown)
            :ok = Meta.mark_error(project_id, reason)
            {:error, reason}
        end

      {:error, {:already_started, tree_pid}} ->
        {:ok, tree_pid}

      {:error, reason} = err ->
        :ok = Meta.mark_error(project_id, reason)
        err
    end
  end

  defp maybe_register_primary(project_id) do
    case Application.get_env(:symphony_elixir, :primary_project_id) do
      nil -> ProjectAliases.register_primary(project_id)
      _ -> :ok
    end
  end

  defp lookup_orchestrator_pid(project_id) do
    case Registry.lookup(ProjectNaming.registry(), {project_id, :orchestrator}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  defp await_orchestrator_pid(_project_id, attempts, _) when attempts <= 0, do: :timeout

  defp await_orchestrator_pid(project_id, attempts, interval_ms)
       when is_integer(attempts) and attempts > 0 do
    case lookup_orchestrator_pid(project_id) do
      pid when is_pid(pid) ->
        {:ok, pid}

      _ ->
        Process.sleep(interval_ms)
        await_orchestrator_pid(project_id, attempts - 1, interval_ms)
    end
  end

  @doc """
  Stops a project tree, unregisters `ProjectRegistry`, and updates metadata.
  """
  @spec stop_project(binary()) :: :ok | {:error, term()}
  def stop_project(project_id) when is_binary(project_id) do
    case Meta.fetch(project_id) do
      %{status: :running, tree_pid: pid} when is_pid(pid) ->
        stop_tree(project_id, pid)

      %{tree_pid: pid} when is_pid(pid) ->
        stop_tree(project_id, pid)

      _ ->
        {:error, :not_found}
    end
  end

  defp stop_tree(project_id, pid) do
    :ok = Meta.demonitor_tree(project_id)

    case Supervisor.stop(pid, :shutdown, 60_000) do
      :ok ->
        _ = ProjectRegistry.unregister(project_id)
        :ok = Meta.mark_stopped(project_id)
        maybe_clear_aliases(project_id)
        :ok

      err ->
        err
    end
  end

  defp maybe_clear_aliases(project_id) do
    case Application.get_env(:symphony_elixir, :primary_project_id) do
      ^project_id -> ProjectAliases.clear_aliases()
      _ -> :ok
    end
  end

  @doc """
  Returns metadata for projects that are not stopped (`:running`, `:starting`, or `:error`).
  """
  @spec list_projects() :: [Meta.row()]
  def list_projects do
    Meta.list_rows()
    |> Enum.reject(&(&1.status == :stopped))
  end

  @doc """
  Marks a project as failed during startup or bootstrap without affecting other projects.
  """
  @spec startup_failure(binary()) :: :ok
  @spec startup_failure(binary(), term()) :: :ok
  def startup_failure(project_id, reason \\ :startup_failure) when is_binary(project_id) do
    :ok = Meta.mark_error(project_id, reason)
    :ok
  end

  @doc false
  @spec bootstrap!() :: :ok
  def bootstrap! do
    cfg = SymphonyElixir.Config.process_config()

    projects =
      cfg.projects
      |> Enum.filter(& &1.enabled)
      |> Enum.sort_by(& &1.id)

    cond do
      projects != [] ->
        base_dir =
          case SymphonyElixir.ProcessConfig.config_path() do
            nil -> File.cwd!()
            p -> p |> Path.expand() |> Path.dirname()
          end

        Enum.each(projects, fn p ->
          case start_project(%{
                 project_id: p.id,
                 workflow_path: p.workflow_path,
                 config_base_dir: base_dir
               }) do
            {:ok, _} ->
              :ok

            {:error, :already_started} ->
              :ok

            {:error, {:already_started, _}} ->
              :ok

            {:error, reason} ->
              Logger.warning(
                "symphony project bootstrap failed project_id=#{p.id} reason=#{inspect(reason)}"
              )

              startup_failure(p.id, reason)
          end
        end)

      true ->
        wf_path = SymphonyElixir.Workflow.workflow_file_path()

        case start_project(%{
               project_id: "default",
               workflow_path: wf_path,
               config_base_dir: File.cwd!()
             }) do
          {:ok, _} ->
            :ok

          {:error, :already_started} ->
            :ok

          {:error, {:already_started, _}} ->
            :ok

          {:error, reason} ->
            Logger.warning("symphony default project bootstrap failed reason=#{inspect(reason)}")
            startup_failure("default", reason)
        end
    end

    :ok
  end
end
