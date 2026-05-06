defmodule SymphonyElixir.ProcessConfig.Store do
  @moduledoc """
  GenServer that caches the loaded ProcessConfig so it can be read
  without re-parsing the YAML file.
  """

  use GenServer

  alias SymphonyElixir.ProcessConfig

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec get() :: ProcessConfig.t()
  def get(server \\ __MODULE__) do
    GenServer.call(server, :get)
  end

  @impl true
  def init(opts) do
    cli_config_arg = Keyword.get(opts, :config_arg) || Application.get_env(:symphony_elixir, :config_arg)
    {:ok, config} = ProcessConfig.load(cli_config_arg)
    {:ok, config}
  end

  @impl true
  def handle_call(:get, _from, config), do: {:reply, config, config}
end
