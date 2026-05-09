defmodule SymphonyElixir.ProjectRegistry do
  @moduledoc """
  Registry mapping `project_id` (binary) to orchestrator pids.

  Backed by a protected ETS `:set` table owned by this GenServer so inserts/deletes
  are serialized while lookups remain fast via `GenServer.call/3`.
  """

  use GenServer

  @type project_id :: binary()
  @type entry :: %{
          project_id: project_id(),
          pid: pid(),
          registered_at: DateTime.t()
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
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Registers `pid` as the orchestrator for `project_id`.

  Replaces any existing mapping for the same `project_id`.
  """
  @spec register(project_id(), pid(), GenServer.server()) :: :ok
  def register(project_id, pid, server \\ __MODULE__)
      when is_binary(project_id) and is_pid(pid) do
    GenServer.call(server, {:register, project_id, pid})
  end

  @doc """
  Removes the mapping for `project_id`, if present.
  """
  @spec unregister(project_id(), GenServer.server()) :: :ok
  def unregister(project_id, server \\ __MODULE__) when is_binary(project_id) do
    GenServer.call(server, {:unregister, project_id})
  end

  @doc """
  Returns `{:ok, pid}` when registered, else `:error`.
  """
  @spec lookup(project_id(), GenServer.server()) :: {:ok, pid()} | :error
  def lookup(project_id, server \\ __MODULE__) when is_binary(project_id) do
    GenServer.call(server, {:lookup, project_id})
  end

  @doc """
  Returns all registered projects with metadata, sorted by `project_id`.
  """
  @spec list(GenServer.server()) :: [entry()]
  def list(server \\ __MODULE__) do
    GenServer.call(server, :list)
  end

  @impl true
  def init(_opts) do
    tid =
      :ets.new(:symphony_project_registry, [
        :set,
        :protected,
        {:read_concurrency, true}
      ])

    {:ok, %{tid: tid}}
  end

  @impl true
  def handle_call({:register, project_id, pid}, _from, %{tid: tid} = state) do
    entry = %{
      project_id: project_id,
      pid: pid,
      registered_at: DateTime.utc_now(:microsecond)
    }

    :ets.insert(tid, {project_id, entry})
    {:reply, :ok, state}
  end

  def handle_call({:unregister, project_id}, _from, %{tid: tid} = state) do
    :ets.delete(tid, project_id)
    {:reply, :ok, state}
  end

  def handle_call({:lookup, project_id}, _from, %{tid: tid} = state) do
    reply =
      case :ets.lookup(tid, project_id) do
        [{^project_id, %{pid: p}}] -> {:ok, p}
        [] -> :error
      end

    {:reply, reply, state}
  end

  def handle_call(:list, _from, %{tid: tid} = state) do
    entries =
      tid
      |> :ets.tab2list()
      |> Enum.map(fn {_id, entry} -> entry end)
      |> Enum.sort_by(& &1.project_id)

    {:reply, entries, state}
  end
end
