defmodule SymphonyElixir.ProjectSupervisor.Bootstrap do
  @moduledoc """
  Starts configured projects after the OTP application is up (unless disabled via opts).

  Runs `ProjectSupervisor.bootstrap!/0` asynchronously so sibling workers (for example
  `HttpServer`) can boot without waiting for every project tree.
  """

  use GenServer

  alias SymphonyElixir.ProjectSupervisor

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :transient,
      shutdown: 60_000
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    if Keyword.get(opts, :skip_bootstrap, false) do
      {:ok, %{skipped: true}}
    else
      send(self(), :bootstrap)
      {:ok, %{skipped: false}}
    end
  end

  @impl true
  def handle_info(:bootstrap, %{skipped: true} = state), do: {:noreply, state}

  def handle_info(:bootstrap, state) do
    _ = ProjectSupervisor.bootstrap!()
    {:noreply, Map.put(state, :bootstrap_done, true)}
  end
end
