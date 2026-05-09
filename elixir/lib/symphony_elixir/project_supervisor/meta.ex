defmodule SymphonyElixir.ProjectSupervisor.Meta do
  @moduledoc false

  use GenServer

  alias SymphonyElixir.ProjectRegistry

  @type status :: :starting | :running | :stopped | :error

  @type row :: %{
          project_id: binary(),
          status: status(),
          workflow_path: binary() | nil,
          tree_pid: pid() | nil,
          orchestrator_pid: pid() | nil,
          error_reason: term() | nil,
          updated_at: DateTime.t()
        }

  @spec child_spec() :: Supervisor.child_spec()
  def child_spec do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [[]]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec begin_start(binary(), binary()) :: :ok | {:error, :already_started}
  def begin_start(project_id, workflow_path)
      when is_binary(project_id) and is_binary(workflow_path) do
    GenServer.call(__MODULE__, {:begin_start, project_id, workflow_path})
  end

  @spec mark_running(binary(), pid(), pid()) :: :ok
  def mark_running(project_id, tree_pid, orchestrator_pid)
      when is_binary(project_id) and is_pid(tree_pid) and is_pid(orchestrator_pid) do
    GenServer.cast(__MODULE__, {:mark_running, project_id, tree_pid, orchestrator_pid})
    :ok
  end

  @spec mark_stopped(binary()) :: :ok
  def mark_stopped(project_id) when is_binary(project_id) do
    GenServer.cast(__MODULE__, {:mark_stopped, project_id})
    :ok
  end

  @spec mark_error(binary(), term()) :: :ok
  def mark_error(project_id, reason) when is_binary(project_id) do
    GenServer.cast(__MODULE__, {:mark_error, project_id, reason})
    :ok
  end

  @spec monitor_tree(binary(), pid()) :: :ok
  def monitor_tree(project_id, tree_pid)
      when is_binary(project_id) and is_pid(tree_pid) do
    GenServer.cast(__MODULE__, {:monitor_tree, project_id, tree_pid})
    :ok
  end

  @spec demonitor_tree(binary()) :: :ok
  def demonitor_tree(project_id) when is_binary(project_id) do
    GenServer.cast(__MODULE__, {:demonitor_tree, project_id})
    :ok
  end

  @spec fetch(binary()) :: row() | nil
  def fetch(project_id) when is_binary(project_id) do
    GenServer.call(__MODULE__, {:fetch, project_id})
  end

  @spec list_rows() :: [row()]
  def list_rows do
    GenServer.call(__MODULE__, :list_rows)
  end

  @impl true
  def init(_opts) do
    tid = :ets.new(:symphony_project_supervisor_meta, [:set, :protected, {:read_concurrency, true}])

    {:ok,
     %{
       tid: tid,
       monitor_refs: %{},
       project_refs: %{}
     }}
  end

  @impl true
  def handle_cast({:mark_running, project_id, tree_pid, orch_pid}, %{tid: tid} = state) do
    case :ets.lookup(tid, project_id) do
      [{^project_id, %{workflow_path: wf}}] when is_binary(wf) ->
        row = base_row(project_id, :running, wf, tree_pid, orch_pid, nil)
        :ets.insert(tid, {project_id, row})

      _ ->
        row = base_row(project_id, :running, nil, tree_pid, orch_pid, nil)
        :ets.insert(tid, {project_id, row})
    end

    {:noreply, state}
  end

  def handle_cast({:mark_stopped, project_id}, %{tid: tid} = state) do
    case :ets.lookup(tid, project_id) do
      [{^project_id, %{workflow_path: wf}}] ->
        row = base_row(project_id, :stopped, wf, nil, nil, nil)
        :ets.insert(tid, {project_id, row})

      [] ->
        :ok
    end

    {:noreply, state}
  end

  def handle_cast({:mark_error, project_id, reason}, %{tid: tid} = state) do
    case :ets.lookup(tid, project_id) do
      [{^project_id, %{workflow_path: wf}}] ->
        row = base_row(project_id, :error, wf, nil, nil, reason)
        :ets.insert(tid, {project_id, row})

      [] ->
        row = base_row(project_id, :error, nil, nil, nil, reason)
        :ets.insert(tid, {project_id, row})
    end

    {:noreply, state}
  end

  def handle_cast({:monitor_tree, project_id, tree_pid}, state) do
    state =
      case Map.fetch(state.project_refs, project_id) do
        {:ok, old_ref} ->
          Process.demonitor(old_ref, [:flush])

          %{
            state
            | monitor_refs: Map.delete(state.monitor_refs, old_ref),
              project_refs: Map.delete(state.project_refs, project_id)
          }

        :error ->
          state
      end

    ref = Process.monitor(tree_pid)

    {:noreply,
     %{
       state
       | monitor_refs: Map.put(state.monitor_refs, ref, project_id),
         project_refs: Map.put(state.project_refs, project_id, ref)
     }}
  end

  def handle_cast({:demonitor_tree, project_id}, state) do
    case Map.fetch(state.project_refs, project_id) do
      {:ok, ref} ->
        Process.demonitor(ref, [:flush])

        {:noreply,
         %{
           state
           | monitor_refs: Map.delete(state.monitor_refs, ref),
             project_refs: Map.delete(state.project_refs, project_id)
         }}

      :error ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{tid: tid} = state) do
    case Map.fetch(state.monitor_refs, ref) do
      {:ok, project_id} ->
        _ = ProjectRegistry.unregister(project_id)
        apply_tree_exit(tid, project_id, reason)

        {:noreply,
         %{
           state
           | monitor_refs: Map.delete(state.monitor_refs, ref),
             project_refs: Map.delete(state.project_refs, project_id)
         }}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call({:begin_start, project_id, workflow_path}, _from, %{tid: tid} = state) do
    reply =
      case :ets.lookup(tid, project_id) do
        [{^project_id, %{status: :running, tree_pid: pid}}] when is_pid(pid) ->
          if Process.alive?(pid), do: {:error, :already_started}, else: :reserve

        [{^project_id, %{status: :starting}}] ->
          {:error, :already_started}

        _ ->
          :reserve
      end

    case reply do
      {:error, _} = err ->
        {:reply, err, state}

      :reserve ->
        row = base_row(project_id, :starting, workflow_path, nil, nil, nil)
        :ets.insert(tid, {project_id, row})
        {:reply, :ok, state}
    end
  end

  def handle_call({:fetch, project_id}, _from, %{tid: tid} = state) do
    reply =
      case :ets.lookup(tid, project_id) do
        [{^project_id, row}] -> row
        [] -> nil
      end

    {:reply, reply, state}
  end

  def handle_call(:list_rows, _from, %{tid: tid} = state) do
    rows =
      tid
      |> :ets.tab2list()
      |> Enum.map(fn {_id, row} -> row end)
      |> Enum.sort_by(& &1.project_id)

    {:reply, rows, state}
  end

  defp apply_tree_exit(tid, project_id, reason) do
    status =
      if reason in [:normal, :shutdown], do: :stopped, else: :error

    err =
      if status == :stopped, do: nil, else: {:tree_down, reason}

    case :ets.lookup(tid, project_id) do
      [{^project_id, %{workflow_path: wf}}] ->
        row = base_row(project_id, status, wf, nil, nil, err)
        :ets.insert(tid, {project_id, row})

      [] ->
        row = base_row(project_id, status, nil, nil, nil, err)
        :ets.insert(tid, {project_id, row})
    end
  end

  defp base_row(project_id, status, workflow_path, tree_pid, orch_pid, error_reason) do
    %{
      project_id: project_id,
      status: status,
      workflow_path: workflow_path,
      tree_pid: tree_pid,
      orchestrator_pid: orch_pid,
      error_reason: error_reason,
      updated_at: DateTime.utc_now(:microsecond)
    }
  end
end
