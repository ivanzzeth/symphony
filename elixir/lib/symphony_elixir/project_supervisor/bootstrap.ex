defmodule SymphonyElixir.ProjectSupervisor.Bootstrap do
  @moduledoc """
  Starts configured projects after the OTP application is up (unless disabled via opts).
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
      {:ok, %{}}
    else
      :ok = ProjectSupervisor.bootstrap!()
      {:ok, %{}}
    end
  end
end
