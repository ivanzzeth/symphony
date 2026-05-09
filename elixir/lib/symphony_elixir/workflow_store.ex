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
    case Application.get_env(:symphony_elixir, :primary_project_id) do
      id when is_binary(id) ->
        case Registry.lookup(SymphonyElixir.ProjectProcessRegistry, {id, :workflow_store}) do
          [{pid, _}] -> pid
          [] -> Process.whereis(__MODULE__)
        end

      _ ->
        Process.whereis(__MODULE__)
    end
  end

  def whereis(name) when is_pid(name), do: name

  def whereis({:via, Registry, _} = via) do
    {:via, Registry, {reg, key}} = via

    case Registry.lookup(reg, key) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  def whereis(name) when is_atom(name) and name == __MODULE__, do: whereis(:auto)

  def whereis(name) when is_atom(name), do: Process.whereis(name)

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
        GenServer.call(pid, :current)

      _ ->
        Workflow.load()
    end
  end

  @spec force_reload(:auto | GenServer.server()) :: :ok | {:error, term()}
  def force_reload(which \\ :auto) do
    case whereis(which) do
      pid when is_pid(pid) ->
        GenServer.call(pid, :force_reload)

      _ ->
        case Workflow.load() do
          {:ok, _workflow} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @impl true
  def init(opts) do
    path =
      case Keyword.get(opts, :workflow_file_path) do
        p when is_binary(p) -> Path.expand(p)
        _ -> Workflow.workflow_file_path()
      end

    project_id = Keyword.get(opts, :project_id)

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
        maybe_notify_workflow_changed(old_stamp, new_state.stamp)
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
        maybe_notify_workflow_changed(old_stamp, new_state.stamp)
        {:noreply, new_state}

      {:error, _reason, new_state} ->
        {:noreply, new_state}
    end
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval_ms)
  end

  defp maybe_notify_workflow_changed(stamp, stamp), do: :ok

  defp maybe_notify_workflow_changed(_old_stamp, _new_stamp) do
    _ = spawn(fn -> StatusDashboard.notify_update() end)
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
