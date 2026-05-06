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
  def handle_call(:get, _from, config) do
    # Compute effective config by overlaying runtime overrides on the stored
    # (file-loaded) config. Crucially we do NOT persist the overridden values
    # back into state, so a subsequent call re-evaluates Application.env afresh.
    # This matters in test where overrides are set/unset between tests.
    effective = apply_overrides(config)
    {:reply, effective, config}
  end

  defp apply_overrides(config) do
    config =
      case Application.get_env(:symphony_elixir, :server_port_override) do
        port when is_integer(port) and port >= 0 ->
          put_in(config.server.port, port)

        _ ->
          config
      end

    case Application.get_env(:symphony_elixir, :server_host_override) do
      host when is_binary(host) and host != "" ->
        put_in(config.server.host, host)

      _ ->
        config
    end
  end
end
