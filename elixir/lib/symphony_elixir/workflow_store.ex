defmodule SymphonyElixir.WorkflowStore do
  @moduledoc """
  Caches the last known good workflow and reloads it when `WORKFLOW.md` changes.
  """

  use GenServer
  require Logger

  alias SymphonyElixir.{StatusDashboard, Workflow}

  @poll_interval_ms 1_000

  defmodule State do
    @moduledoc false

    defstruct [:path, :stamp, :workflow, :project_id]
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec whereis(:auto | GenServer.server()) :: pid() | nil
  def whereis(which \\ :auto)

  def whereis(:auto) do
    pid =
      case registry_alive?() do
        true ->
          case Application.get_env(:symphony_elixir, :primary_project_id) do
            id when is_binary(id) ->
              case Registry.lookup(SymphonyElixir.ProjectProcessRegistry, {id, :workflow_store}) do
                [{p, _}] -> p
                [] -> Process.whereis(__MODULE__)
              end

            _ ->
              case Registry.lookup(SymphonyElixir.ProjectProcessRegistry, {"default", :workflow_store}) do
                [{p, _}] -> p
                [] -> Process.whereis(__MODULE__)
              end
          end

        false ->
          Process.whereis(__MODULE__)
      end

    alive_pid(pid)
  end

  def whereis(name) when is_pid(name), do: alive_pid(name)

  def whereis({:via, Registry, _} = via) do
    {:via, Registry, {reg, key}} = via

    pid =
      case Registry.lookup(reg, key) do
        [{p, _}] -> p
        [] -> nil
      end

    alive_pid(pid)
  end

  def whereis(name) when is_atom(name) and name == __MODULE__, do: whereis(:auto)

  def whereis(name) when is_atom(name), do: alive_pid(Process.whereis(name))

  defp registry_alive? do
    case Process.whereis(SymphonyElixir.ProjectProcessRegistry) do
      pid when is_pid(pid) -> Process.alive?(pid)
      _ -> false
    end
  end

  defp alive_pid(pid) when is_pid(pid) do
    if node(pid) == node() and Process.alive?(pid), do: pid, else: nil
  end

  defp alive_pid(_), do: nil

  @doc """
  Workflow store for UI/dashboard and cross-cutting reads: primary env project, else first
  registered project, else `nil` (caller falls back to `Workflow.current/0` via `Config`).
  """
  @spec primary_server() :: GenServer.server() | nil
  def primary_server do
    case Application.get_env(:symphony_elixir, :primary_project_id) do
      id when is_binary(id) ->
        {:via, Registry, {SymphonyElixir.ProjectProcessRegistry, {id, :workflow_store}}}

      _ ->
        case SymphonyElixir.ProjectRegistry.list() do
          [%{project_id: id} | _] ->
            {:via, Registry, {SymphonyElixir.ProjectProcessRegistry, {id, :workflow_store}}}

          [] ->
            nil
        end
    end
  end

  @spec current(:auto | GenServer.server()) :: {:ok, Workflow.loaded_workflow()} | {:error, term()}
  def current(which \\ :auto) do
    case whereis(which) do
      pid when is_pid(pid) ->
        try do
          GenServer.call(pid, :current)
        catch
          :exit, reason ->
            if call_exit_recoverable?(reason), do: Workflow.load(), else: :erlang.raise(:exit, reason, __STACKTRACE__)
        end

      _ ->
        Workflow.load()
    end
  end

  @spec force_reload(:auto | GenServer.server()) :: :ok | {:error, term()}
  def force_reload(which \\ :auto) do
    case whereis(which) do
      pid when is_pid(pid) ->
        try do
          GenServer.call(pid, :force_reload)
        catch
          :exit, reason ->
            if call_exit_recoverable?(reason) do
              case Workflow.load() do
                {:ok, _workflow} -> :ok
                {:error, err} -> {:error, err}
              end
            else
              :erlang.raise(:exit, reason, __STACKTRACE__)
            end
        end

      _ ->
        case Workflow.load() do
          {:ok, _workflow} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp call_exit_recoverable?(:noproc), do: true
  defp call_exit_recoverable?({:noproc, _}), do: true
  defp call_exit_recoverable?(:normal), do: true
  defp call_exit_recoverable?({:normal, _}), do: true
  defp call_exit_recoverable?(:shutdown), do: true
  defp call_exit_recoverable?({:shutdown, _}), do: true
  defp call_exit_recoverable?(_), do: false

  @impl true
  def init(opts) do
    opts_path =
      case Keyword.get(opts, :workflow_file_path) do
        p when is_binary(p) -> Path.expand(p)
        _ -> Path.expand(Workflow.workflow_file_path())
      end

    path = effective_workflow_path_on_init(opts, opts_path)
    project_id = Keyword.get(opts, :project_id)

    if is_binary(project_id) do
      Logger.metadata(project_id: project_id)
    end

    case load_state(path) do
      {:ok, state} ->
        state = %{state | project_id: project_id}
        schedule_poll()
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:current, _from, %State{} = state) do
    # Return cached workflow immediately — no synchronous I/O.
    # The poll timer (every 1s) handles file change detection asynchronously.
    {:reply, {:ok, state.workflow}, state}
  end

  def handle_call(:force_reload, _from, %State{} = state) do
    old_stamp = state.stamp

    case reload_state(state) do
      {:ok, new_state} ->
        maybe_notify_workflow_changed(old_stamp, new_state.stamp, new_state)
        {:reply, :ok, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  def handle_call(:sync_application_workflow_path, _from, %State{} = state) do
    path = Workflow.workflow_file_path() |> Path.expand()

    if path == state.path do
      case reload_state(state) do
        {:ok, new_state} ->
          {:reply, :ok, new_state}

        {:error, _reason, new_state} ->
          {:reply, :ok, new_state}
      end
    else
      case load_state(path) do
        {:ok, new_state} ->
          new_state = %{new_state | project_id: state.project_id}
          schedule_poll()
          {:reply, :ok, new_state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_info(:poll, %State{} = state) do
    schedule_poll()
    old_stamp = state.stamp

    case reload_state(state) do
      {:ok, new_state} ->
        maybe_notify_workflow_changed(old_stamp, new_state.stamp, new_state)
        {:noreply, new_state}

      {:error, _reason, new_state} ->
        {:noreply, new_state}
    end
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval_ms)
  end

  # `Supervisor.restart_child/2` reuses the tree's original `workflow_file_path` opt, but tests
  # (and operators) may switch the active file via `Application` + `Workflow.set_workflow_file_path/1`
  # for the primary project. Prefer the app path when it is an alternate file in the same directory.
  defp effective_workflow_path_on_init(opts, opts_path) do
    project_id = Keyword.get(opts, :project_id)
    primary_id = Application.get_env(:symphony_elixir, :primary_project_id) || "default"
    primary? = project_id == primary_id

    app_raw = Application.get_env(:symphony_elixir, :workflow_file_path)

    if primary? and is_binary(app_raw) do
      app_path = Path.expand(app_raw)

      if app_path != opts_path and Path.dirname(app_path) == Path.dirname(opts_path) do
        app_path
      else
        opts_path
      end
    else
      opts_path
    end
  end

  defp maybe_notify_workflow_changed(stamp, stamp, _state), do: :ok

  defp maybe_notify_workflow_changed(_old_stamp, _new_stamp, state) do
    project_id =
      case state.project_id do
        id when is_binary(id) -> id
        _ -> Application.get_env(:symphony_elixir, :primary_project_id) || "default"
      end

    _ =
      spawn(fn ->
        StatusDashboard.notify_update(SymphonyElixir.StatusDashboard, project_id: project_id)
      end)

    :ok
  end

  defp reload_state(%State{path: path} = state) do
    reload_current_path(path, state)
  end

  defp reload_path(path, state) do
    case load_state(path) do
      {:ok, new_state} ->
        {:ok, %{new_state | project_id: state.project_id}}

      {:error, reason} ->
        log_reload_error(path, reason)
        {:error, reason, state}
    end
  end

  defp reload_current_path(path, state) do
    case current_stamp(path) do
      {:ok, stamp} when stamp == state.stamp ->
        {:ok, state}

      {:ok, _stamp} ->
        reload_path(path, state)

      {:error, reason} ->
        log_reload_error(path, reason)
        {:error, reason, state}
    end
  end

  defp load_state(path) do
    with {:ok, workflow} <- Workflow.load(path),
         {:ok, stamp} <- current_stamp(path) do
      {:ok, %State{path: path, stamp: stamp, workflow: workflow, project_id: nil}}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp current_stamp(path) when is_binary(path) do
    with {:ok, stat} <- File.stat(path, time: :posix),
         {:ok, content} <- File.read(path) do
      {:ok, {stat.mtime, stat.size, :erlang.phash2(content)}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp log_reload_error(path, reason) do
    Logger.error("Failed to reload workflow path=#{path} reason=#{inspect(reason)}; keeping last known good configuration")
  end
end
