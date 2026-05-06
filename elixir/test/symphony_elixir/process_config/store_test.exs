defmodule SymphonyElixir.ProcessConfig.StoreTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.ProcessConfig.Store

  setup do
    # Write a minimal config file for the Store to load
    tmp_yaml =
      Path.join(
        System.tmp_dir!(),
        "symphony-store-test-#{System.unique_integer([:positive])}.yaml"
      )

    content = """
    server:
      port: 4000
      host: "127.0.0.1"
    observability:
      dashboard_enabled: true
      refresh_ms: 500
      render_interval_ms: 32
    """

    File.write!(tmp_yaml, content)

    on_exit(fn ->
      File.rm(tmp_yaml)
      Application.delete_env(:symphony_elixir, :server_port_override)
      Application.delete_env(:symphony_elixir, :server_host_override)
    end)

    {:ok, tmp_yaml: tmp_yaml}
  end

  describe "Store.get/0 with runtime overrides" do
    test "returns overridden port when server_port_override is set", %{tmp_yaml: tmp_yaml} do
      Application.put_env(:symphony_elixir, :server_port_override, 9999)
      {:ok, _pid} = Store.start_link(config_arg: tmp_yaml, name: :store_test_port_override)

      config = Store.get(:store_test_port_override)

      assert config.server.port == 9999
    end

    test "returns overridden host when server_host_override is set", %{tmp_yaml: tmp_yaml} do
      Application.put_env(:symphony_elixir, :server_host_override, "10.0.0.1")
      {:ok, _pid} = Store.start_link(config_arg: tmp_yaml, name: :store_test_host_override)

      config = Store.get(:store_test_host_override)

      assert config.server.host == "10.0.0.1"
    end

    test "override does NOT persist into state across consecutive calls", %{tmp_yaml: tmp_yaml} do
      # Start a Store with the yaml config (port: 4000)
      {:ok, _pid} = Store.start_link(config_arg: tmp_yaml, name: :store_test_isolation)

      # First call with override set
      Application.put_env(:symphony_elixir, :server_port_override, 9999)
      config1 = Store.get(:store_test_isolation)
      assert config1.server.port == 9999

      # Clear the override
      Application.delete_env(:symphony_elixir, :server_port_override)

      # Second call must return the original file-loaded value, NOT 9999
      config2 = Store.get(:store_test_isolation)
      assert config2.server.port == 4000,
             "expected port 4000 (file value) but got #{inspect(config2.server.port)} — " <>
               "override leaked into GenServer state"
    end

    test "override does NOT persist into state for host across consecutive calls", %{
      tmp_yaml: tmp_yaml
    } do
      Application.put_env(:symphony_elixir, :server_host_override, "10.0.0.1")
      {:ok, _pid} = Store.start_link(config_arg: tmp_yaml, name: :store_test_host_isolation)

      config1 = Store.get(:store_test_host_isolation)
      assert config1.server.host == "10.0.0.1"

      Application.delete_env(:symphony_elixir, :server_host_override)

      config2 = Store.get(:store_test_host_isolation)
      assert config2.server.host == "127.0.0.1",
             "expected host 127.0.0.1 (file value) but got #{inspect(config2.server.host)} — " <>
               "override leaked into GenServer state"
    end

    test "returns file-loaded values when no overrides are set", %{tmp_yaml: tmp_yaml} do
      {:ok, _pid} = Store.start_link(config_arg: tmp_yaml, name: :store_test_no_overrides)

      config = Store.get(:store_test_no_overrides)

      assert config.server.port == 4000
      assert config.server.host == "127.0.0.1"
      assert config.observability.dashboard_enabled == true
      assert config.observability.refresh_ms == 500
      assert config.observability.render_interval_ms == 32
    end
  end
end
